"""Build the local-only AVD probe with installed Android/JDK tools; no downloads."""
from pathlib import Path
import os
import re
import subprocess
import zipfile

root = Path(__file__).resolve().parents[3]
sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
out = root / 'build/verification/l2-t03/avd/client'
out.mkdir(parents=True, exist_ok=True)
java = Path(subprocess.check_output(['/usr/libexec/java_home', '-v', '17'], text=True).strip())
tools = max((sdk / 'build-tools').iterdir(), key=lambda p: tuple(int(v) for v in p.name.split('.') if v.isdigit()))
platform = max((sdk / 'platforms').glob('android-*'), key=lambda p: tuple(map(int, re.findall(r'\d+', p.name)))) / 'android.jar'
classes, dex = out / 'classes', out / 'dex'
classes.mkdir(exist_ok=True)
dex.mkdir(exist_ok=True)
subprocess.run([str(java / 'bin/javac'), '-source', '8', '-target', '8', '-classpath', str(platform), '-d', str(classes), str(Path(__file__).with_name('ProbeActivity.java'))], check=True)
subprocess.run([str(tools / 'd8'), '--min-api', '23', '--lib', str(platform), '--output', str(dex), *map(str, classes.rglob('*.class'))], check=True)
base = out / 'unsigned.apk'
subprocess.run([str(tools / 'aapt2'), 'link', '-o', str(base), '-I', str(platform), '--manifest', str(Path(__file__).with_name('AndroidManifest.xml')), '--min-sdk-version', '23', '--target-sdk-version', '34'], check=True)
with zipfile.ZipFile(base, 'a') as archive:
    archive.write(dex / 'classes.dex', 'classes.dex')
key = out / 'probe.keystore'
if not key.exists():
    subprocess.run([str(java / 'bin/keytool'), '-genkeypair', '-keystore', str(key), '-storepass', 'android', '-keypass', 'android', '-alias', 'probe', '-dname', 'CN=Local Test', '-keyalg', 'RSA', '-validity', '30'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run([str(tools / 'apksigner'), 'sign', '--ks', str(key), '--ks-key-alias', 'probe', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', str(out / 'local-probe.apk'), str(base)], check=True)
print(out / 'local-probe.apk')
