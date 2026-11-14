"""Approved-AVD check: preserve app data, verify real app routing, then restore it."""
import argparse
import base64
import io
import tarfile
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

from local_fixture import Fixture

TARGET = 'com.follow.clash.dev'
CLIENT = 'com.follow.clash.observationclient.'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--avd', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--clients', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    adb = [str(Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk')) / 'platform-tools/adb'), '-s', args.serial]

    def command(*words, check=True, data=None):
        result = subprocess.run([*adb, *map(str, words)], input=data, capture_output=True)
        if check and result.returncode:
            raise RuntimeError('ADB command failed: ' + str(words[:3]) + '\n' + result.stderr.decode(errors='replace'))
        return result.stdout

    if command('emu', 'avd', 'name').decode().splitlines()[0] != args.avd or command('shell', 'getprop', 'ro.kernel.qemu').strip() != b'1':
        raise RuntimeError('Explicit AVD identity mismatch')
    installed = command('shell', 'pm', 'list', 'packages').decode().splitlines()
    owned = [name for name in ('a', 'b', 'instrumentation') if 'package:' + ('com.follow.clash.observationtest' if name == 'instrumentation' else CLIENT + name) not in installed]
    command('shell', 'am', 'force-stop', TARGET)
    directories = [name for name in ('files', 'shared_prefs', 'app_flutter', 'databases') if command('shell', 'run-as', TARGET, 'test', '-d', name, check=False) == b'']
    # tar omits missing paths; the backup must exist before any fixture is launched.
    backup = command('exec-out', 'run-as', TARGET, 'tar', 'cf', '-', *directories, check=False)
    if not backup or len(backup) < 512:
        raise RuntimeError('No private-data backup')
    (args.out / 'private-data.tar').write_bytes(backup)
    canonical_backup = args.out / 'restore-data.tar'
    with tarfile.open(fileobj=io.BytesIO(backup)) as original, tarfile.open(canonical_backup, 'w', format=tarfile.USTAR_FORMAT) as clean:
        for member in original.getmembers():
            member.pax_headers = {}
            member.uid = member.gid = 0
            member.uname = member.gname = ''
            member.mtime = int(member.mtime)
            clean.addfile(member, original.extractfile(member) if member.isfile() else None)
    with tarfile.open(fileobj=io.BytesIO(backup)) as archive:
        if not archive.getmembers():
            raise RuntimeError('Empty private-data archive')
    prior_vpn_op = command('shell', 'appops', 'get', TARGET, 'ACTIVATE_VPN').decode()
    prior_vpn_mode = next((mode for mode in ('allow', 'ignore', 'deny', 'default') if 'ACTIVATE_VPN: ' + mode in prior_vpn_op), 'default')
    fixture = Fixture()
    process = None
    report = {'cases': [], 'errors': []}

    def read(package, path):
        raw = command('exec-out', 'run-as', package, 'cat', path, check=False)
        try:
            return json.loads(raw)
        except (ValueError, UnicodeError):
            return None

    def wait_read(package, path, predicate=lambda value: value is not None):
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            value = read(package, path)
            if value is not None and predicate(value):
                return value
            failure = read(TARGET, 'files/observation-fixture/failure.json')
            if failure:
                raise RuntimeError(str(failure))
            time.sleep(.1)
        raise RuntimeError('Timed out: ' + path)

    def send(action, result, **values):
        content = json.dumps(dict(action=action, result=result, **values)).encode()
        command('shell', "run-as " + TARGET + " sh -c 'cat > files/observation-fixture/command.tmp'", data=content)
        command('shell', 'run-as', TARGET, 'mv', 'files/observation-fixture/command.tmp', 'files/observation-fixture/command.json')
        if action == 'stop':
            return None
        value = wait_read(TARGET, 'files/observation-fixture/' + result + '.json')
        (args.out / (result + '.json')).write_text(json.dumps(value, indent=2))
        return value

    def wire(version, entries):
        canonical = '1\n' + str(version) + '\n' + ''.join(package + '\0' + target + '\0-\n' for package, target in entries)
        return dict(profileId=1, version=version, revision=hashlib.sha256(canonical.encode()).hexdigest(), rules=[dict(package=p, target=t) for p, t in entries])

    try:
        for name in ('a', 'b', 'instrumentation'):
            command('install', '-r', args.clients / (name + '.apk'))
        command('shell', 'appops', 'set', TARGET, 'ACTIVATE_VPN', 'allow')
        log = (args.out / 'instrumentation.log').open('wb')
        process = subprocess.Popen([*adb, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'profile', base64.b64encode(fixture.profile().encode()).decode(), 'com.follow.clash.observationtest/com.follow.clash.observationtest.ObservationInstrumentation'], stdout=log, stderr=subprocess.STDOUT)
        wait_read(TARGET, 'files/observation-fixture/ready.json')
        version = 0
        cases = [('rule', 'fixture.group', 'DIRECT'), ('direct', 'fixture.group', 'DIRECT'), ('global', 'REJECT', 'DIRECT'), ('rule', 'REJECT', 'DIRECT'), ('direct', None, None)]
        for index, (mode, a_target, b_target) in enumerate(cases):
            version += 1
            entries = [] if a_target is None else [(CLIENT + 'a', a_target), (CLIENT + 'b', b_target)]
            response = send('patch', 'patch-' + str(index), patch={'mode': mode, 'application-routing': wire(version, entries)})
            if response:
                raise RuntimeError('Patch rejected: ' + str(response))
            for name in ('a', 'b'):
                run = 'routing-' + str(index) + '-' + name
                command('shell', 'am', 'start', '-W', '-n', CLIENT + name + '/com.follow.clash.observationclient.ConnectionClientActivity', '--es', 'case', run, '--ei', 'directPort', fixture.direct, '--ei', 'proxyPort', fixture.proxy_target, '--ei', 'count', 1, '--ei', 'holdMillis', 2000)
                facts = wait_read(CLIENT + name, 'files/socket-facts.json', lambda value: isinstance(value, list) and len(value) == 3 and all(item.get('case') == run for item in value))
                snapshot = send('snapshot', run)
                target = a_target if name == 'a' else b_target
                expected_proxy = mode == 'global' or target == 'fixture.group'
                rejected = mode != 'global' and target == 'REJECT'
                for fact in facts:
                    found = any(value.get('case') == run and value.get('protocol') == fact['protocol'] for value in fixture.proxied)
                    if bool(fact['ok']) == rejected or found != expected_proxy:
                        report['errors'].append({'case': run, 'protocol': fact['protocol'], 'ok': fact['ok'], 'proxied': found})
                    if not rejected:
                        key = ('tcp' if fact['protocol'] == 'tcp' else 'udp', fact.get('sourcePort'), fact['destinationPort'])
                        tracked = next((item for item in snapshot.get('connections', []) if (item['metadata']['network'], int(item['metadata']['sourcePort']), int(item['metadata']['destinationPort'])) == key), None)
                        if tracked is None or tracked.get('observation', {}).get('application', {}).get('packages') != [CLIENT + name]:
                            report['errors'].append({'case': run, 'reason': 'wrong app attribution'})
                report['cases'].append({'case': run, 'mode': mode, 'target': target, 'facts': facts})
        adopted = send('capture', 'capture-b-only', packages=[CLIENT + 'b'])
        if adopted.get('status') != 'activated':
            raise RuntimeError('VPN scope not adopted: ' + str(adopted))
        report['capture'] = adopted
        report['captureCases'] = []
        for name, excluded in [('a', True), ('b', False)]:
            run = 'scope-' + name
            command('shell', 'am', 'start', '-W', '-n', CLIENT + name + '/com.follow.clash.observationclient.ConnectionClientActivity', '--es', 'case', run, '--ei', 'directPort', fixture.direct, '--ei', 'proxyPort', fixture.proxy_target, '--ei', 'count', 1, '--ei', 'holdMillis', 2000)
            facts = wait_read(CLIENT + name, 'files/socket-facts.json', lambda value: isinstance(value, list) and len(value) == 3 and all(item.get('case') == run for item in value))
            snapshot = send('snapshot', run)
            for fact in facts:
                key = ('tcp' if fact['protocol'] == 'tcp' else 'udp', fact.get('sourcePort'), fact['destinationPort'])
                tracked = next((item for item in snapshot.get('connections', []) if (item['metadata']['network'], int(item['metadata']['sourcePort']), int(item['metadata']['destinationPort'])) == key), None)
                if not fact['ok'] or (tracked is not None) == excluded:
                    report['errors'].append({'case': run, 'reason': 'VPN scope mismatch', 'protocol': fact['protocol']})
                if tracked and (tracked.get('observation', {}).get('capture', {}).get('status') != 'vpn' or tracked.get('observation', {}).get('application', {}).get('packages') != [CLIENT + name]):
                    report['errors'].append({'case': run, 'reason': 'wrong capture or identity'})
            report['captureCases'].append({'case': run, 'excluded': excluded, 'facts': facts})
        send('stop', 'stopped')
        process.wait(timeout=30)
        log.close()
        report['received'], report['proxied'] = fixture.received, fixture.proxied
        (args.out / 'report.json').write_text(json.dumps(report, indent=2))
        if report['errors']:
            raise RuntimeError('Routing verification failed; see local report')
        print(json.dumps({'cases': len(report['cases']), 'errors': len(report['errors'])}))
    finally:
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        for name in ('a', 'b'):
            command('shell', 'am', 'force-stop', CLIENT + name, check=False)
        command('shell', 'am', 'force-stop', TARGET, check=False)
        command('push', canonical_backup, '/data/local/tmp/application-routing-backup.tar')
        command('shell', "run-as " + TARGET + " sh -c 'rm -rf files shared_prefs app_flutter databases; tar xf /data/local/tmp/application-routing-backup.tar'")
        command('shell', 'appops', 'set', TARGET, 'ACTIVATE_VPN', prior_vpn_mode)
        command('shell', 'rm', '/data/local/tmp/application-routing-backup.tar')
        for name in owned:
            command('uninstall', 'com.follow.clash.observationtest' if name == 'instrumentation' else CLIENT + name, check=False)
        fixture.close()


if __name__ == '__main__':
    main()
