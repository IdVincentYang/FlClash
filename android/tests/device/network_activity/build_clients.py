"""Build two controlled clients and an instrumentation APK using installed tools."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import zipfile


def build(out, app=None, baseline_core=None, keystore=None):
    source = Path(__file__).resolve().parent
    keystore = keystore or Path.home() / '.android/debug.keystore'
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
    java = Path(subprocess.check_output(['/usr/libexec/java_home', '-v', '17'], text=True).strip())
    version = lambda path: tuple(map(int, re.findall(r'\d+', path.name)))
    tools = max((sdk / 'build-tools').iterdir(), key=version)
    platform = max((sdk / 'platforms').glob('android-*'), key=version) / 'android.jar'
    out.mkdir(parents=True, exist_ok=True)
    classes, dex = out / 'classes', out / 'dex'
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    subprocess.run([str(java / 'bin/javac'), '-source', '8', '-target', '8', '-classpath', str(platform), '-d', str(classes),
                    str(source / 'ObservationInstrumentation.java'), str(source / 'ConnectionClientActivity.java'),
                    str(source / 'ConnectionClientService.java')], check=True)
    subprocess.run([str(tools / 'd8'), '--min-api', '24', '--lib', str(platform), '--output', str(dex),
                    *map(str, classes.rglob('*.class'))], check=True)
    for name in ('a', 'b', 'shareda', 'sharedb', 'instrumentation'):
        package = ('com.follow.clash.observationtest' if name == 'instrumentation'
                   else 'com.follow.clash.observationclient.' + name)
        component = ('<instrumentation android:name="com.follow.clash.observationtest.ObservationInstrumentation" '
                     'android:targetPackage="com.follow.clash.dev" />' if name == 'instrumentation' else '')
        activity = ('' if name == 'instrumentation' else
                    '<activity android:name="com.follow.clash.observationclient.ConnectionClientActivity" android:exported="true" />'
                    '<service android:name="com.follow.clash.observationclient.ConnectionClientService" android:foregroundServiceType="dataSync" />')
        shared = ' android:sharedUserId="com.follow.clash.observation.shared"' if name.startswith('shared') else ''
        manifest = out / (name + '-manifest.xml')
        manifest.write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{package}"{shared}>
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<application android:label="Observation {name}" android:debuggable="true">{activity}</application>
{component}</manifest>''', encoding='utf-8')
        unsigned = out / (name + '-unsigned.apk')
        subprocess.run([str(tools / 'aapt2'), 'link', '-o', str(unsigned), '-I', str(platform), '--manifest', str(manifest),
                        '--min-sdk-version', '24', '--target-sdk-version', '34'], check=True)
        with zipfile.ZipFile(unsigned, 'a') as archive:
            archive.write(dex / 'classes.dex', 'classes.dex')
        subprocess.run([str(tools / 'apksigner'), 'sign', '--ks', str(keystore),
                        '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
                        '--out', str(out / (name + '.apk')), str(unsigned)], check=True)
        print(out / (name + '.apk'))
    if app is not None:
        subprocess.run([str(tools / 'apksigner'), 'sign', '--ks', str(keystore),
                        '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
                        '--out', str(out / 'app-under-test.apk'), str(app.resolve())], check=True)
        print(out / 'app-under-test.apk')
        if baseline_core is not None:
            unsigned, aligned = out / 'baseline-unsigned.apk', out / 'baseline-aligned.apk'
            with zipfile.ZipFile(app) as original, zipfile.ZipFile(unsigned, 'w') as target:
                for item in original.infolist():
                    if item.filename.startswith('META-INF/') and item.filename.endswith(('.RSA', '.DSA', '.EC', '.SF', 'MANIFEST.MF')):
                        continue
                    data = baseline_core.read_bytes() if item.filename == 'lib/arm64-v8a/libclash.so' else original.read(item.filename)
                    target.writestr(item, data)
            subprocess.run([str(tools / 'zipalign'), '-f', '4', str(unsigned), str(aligned)], check=True)
            subprocess.run([str(tools / 'apksigner'), 'sign', '--ks', str(keystore),
                            '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
                            '--out', str(out.parent / 'baseline.apk'), str(aligned)], check=True)
            unsigned.unlink()
            aligned.unlink()
            print(out.parent / 'baseline.apk')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=Path(__file__).resolve().parents[4] / 'build/verification/na-t01-01/clients')
    parser.add_argument('--app', type=Path)
    parser.add_argument('--baseline-core', type=Path)
    parser.add_argument('--keystore', type=Path)
    args = parser.parse_args()
    build(args.out, args.app, args.baseline_core, args.keystore)
