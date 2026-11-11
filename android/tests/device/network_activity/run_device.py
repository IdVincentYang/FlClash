"""Run the real development APK only on an explicitly named, authorized emulator."""
import argparse
import base64
import json
from pathlib import Path
import statistics
import subprocess
import time
import uuid

from local_fixture import Fixture


TARGET = 'com.follow.clash.dev'
CLIENT = 'com.follow.clash.observationclient.'
CLIENTS = ('a', 'b', 'shareda', 'sharedb')
ROOT = Path(__file__).resolve().parents[4]


def main(args):
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    run_id = uuid.uuid4().hex[:12]
    adb = ['adb', '-s', args.serial]

    def command(*words, check=True, data=None):
        result = subprocess.run([*adb, *map(str, words)], input=data, capture_output=True)
        if check and result.returncode:
            raise RuntimeError((result.stdout + result.stderr).decode(errors='replace'))
        return result.stdout

    avd = command('emu', 'avd', 'name').decode().splitlines()[0].strip()
    if avd != args.avd or command('shell', 'getprop', 'ro.kernel.qemu').strip() != b'1':
        raise RuntimeError('The emulator does not match the explicitly authorized AVD')

    def read(package, path):
        result = command('exec-out', 'run-as', package, 'cat', path, check=False)
        try:
            return json.loads(result)
        except (ValueError, UnicodeError):
            return None

    def wait_read(package, path, predicate=lambda value: value is not None, timeout=60):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = read(package, path)
            if predicate(value):
                return value
            failure = read(TARGET, 'files/observation-fixture/failure.json')
            if failure:
                raise RuntimeError(failure)
            if process is not None and process.poll() is not None:
                raise RuntimeError((out / 'instrumentation.log').read_text(encoding='utf-8'))
            time.sleep(.15)
        raise RuntimeError('Timed out waiting for ' + package + ':' + path)

    def send(action, name, **fields):
        path = out / 'command.json'
        path.write_text(json.dumps({'action': action, 'result': name, **fields}), encoding='utf-8')
        command('push', path, '/data/local/tmp/na01-command.json')
        command('shell', 'run-as', TARGET, 'cp', '/data/local/tmp/na01-command.json', 'files/observation-fixture/command.json')
        if action != 'stop':
            return wait_read(TARGET, 'files/observation-fixture/' + name + '.json')

    def tokens(values):
        return {(v['case'], v['package'], v['index'], v['protocol']) for v in values}

    def verify_observation(fact, tracked, mode, expected_input):
        identity = tracked.get('observation', {}).get('application', {})
        if fact['package'] in {CLIENT + 'shareda', CLIENT + 'sharedb'}:
            if identity.get('status') != 'ambiguous' or identity.get('uid') != fact['uid'] or identity.get('packages') != [CLIENT + 'shareda', CLIENT + 'sharedb'] or tracked['metadata'].get('process'):
                report['errors'].append({'case': fact, 'reason': 'shared UID was not explicitly ambiguous', 'identity': identity})
        elif identity.get('status') != 'known':
            report['unknown'].append({'case': fact, 'identity': identity})
        elif identity.get('uid') != fact['uid'] or identity.get('packages') != [fact['package']]:
            report['errors'].append({'case': fact, 'reason': 'wrong App', 'identity': identity})
        if tracked['observation'].get('capture', {}).get('status') != 'vpn':
            report['errors'].append({'case': fact, 'reason': 'missing VPN capture evidence'})
        configuration = tracked['observation'].get('configuration', {})
        if configuration.get('status') == 'unknown' and not configuration.get('inputId'):
            report['configurationUnknown'].append({'case': fact, 'id': tracked['id']})
        elif configuration.get('status') != 'known' or configuration.get('inputId') != expected_input or configuration.get('mode') != mode:
            report['errors'].append({'case': fact, 'reason': 'configuration fact mismatch', 'configuration': configuration})
        else:
            report['configurationKnown'] += 1

    print('Installing controlled APKs on ' + avd, flush=True)
    command('install', '-r', '-d', args.apk.resolve())
    command('shell', 'pm', 'clear', TARGET)
    clients = ROOT / 'build/verification/na-t01-01/clients'
    for name in (*CLIENTS, 'instrumentation'):
        command('install', '-r', clients / (name + '.apk'))
    for name in CLIENTS:
        command('shell', 'pm', 'clear', CLIENT + name)
    command('shell', 'pm', 'grant', TARGET, 'android.permission.POST_NOTIFICATIONS')
    command('shell', 'appops', 'set', TARGET, 'ACTIVATE_VPN', 'allow')
    fixture = Fixture()
    process = None
    facts, snapshots, before = [], {}, {}
    report = {'variant': args.variant, 'modes': {}, 'errors': [], 'unknown': [], 'memory': {}, 'configurationKnown': 0, 'configurationUnknown': []}
    try:
        with (out / 'instrumentation.log').open('wb') as log:
            process = subprocess.Popen([*adb, 'shell', 'am', 'instrument', '-w', '-e', 'profile',
                                       base64.b64encode(fixture.profile().encode()).decode(),
                                       'com.follow.clash.observationtest/.ObservationInstrumentation'], stdout=log, stderr=subprocess.STDOUT)
            ready = wait_read(TARGET, 'files/observation-fixture/ready.json', timeout=75)
            (out / 'ready.json').write_text(json.dumps(ready), encoding='utf-8')
            print('Production ServiceState activated the accepted input', flush=True)
            for mode in ('rule', 'global', 'direct'):
                if mode != 'rule':
                    send('patch', 'patch-' + mode, patch={'mode': mode})
                started = time.monotonic()
                cpu_before = send('cpu', 'cpu-before-' + mode)
                for name in CLIENTS:
                    command('shell', 'am', 'start', '-W', '--activity-single-top', '-n', CLIENT + name + '/com.follow.clash.observationclient.ConnectionClientActivity',
                            '--es', 'case', run_id + '-' + mode + '-' + name, '--ei', 'directPort', fixture.direct, '--ei', 'proxyPort', fixture.proxy_target,
                            '--ei', 'count', args.count, '--ei', 'holdMillis', 90000)
                mode_facts = []
                known_before = report['configurationKnown']
                for name in CLIENTS:
                    result = wait_read(CLIENT + name, 'files/socket-facts.json',
                                       lambda value: isinstance(value, list) and len(value) == args.count * 3
                                       and all(v.get('case') == run_id + '-' + mode + '-' + name for v in value))
                    mode_facts.extend(result)
                facts.extend(mode_facts)
                snapshot = send('snapshot', 'snapshot-' + mode)
                fact_state = send('fact', 'fact-' + mode)
                snapshots[mode] = snapshot
                command('logcat', '-d', '-s', 'AndroidRuntime:E')
                report['memory'][mode] = command('shell', 'dumpsys', 'meminfo', TARGET).decode()
                incoming = snapshot.get('connections', [])
                index = {(v['metadata']['network'], int(v['metadata']['sourcePort']), int(v['metadata']['destinationPort'])): v for v in incoming}
                for fact in mode_facts:
                    key = ('tcp' if fact['protocol'] == 'tcp' else 'udp', fact.get('sourcePort'), fact['destinationPort'])
                    tracked = index.get(key)
                    if not fact['ok'] or tracked is None:
                        report['errors'].append({'case': fact, 'reason': 'connection failed or missing from Core snapshot'})
                        continue
                    if args.variant == 'candidate':
                        verify_observation(fact, tracked, mode, fact_state.get('inputId'))
                    expected_proxy = mode == 'global' or mode == 'rule' and fact['destinationPort'] == fixture.proxy_target
                    token = next(iter(tokens([fact])))
                    if token not in tokens(fixture.received) or (token in tokens(fixture.proxied)) != expected_proxy:
                        report['errors'].append({'case': fact, 'reason': 'independent server path mismatch'})
                    expected_chain = 'fixture.exit' if expected_proxy else 'DIRECT'
                    if expected_chain not in tracked.get('chains', []):
                        report['errors'].append({'case': fact, 'reason': 'Core chain disagrees with received path'})
                for value in incoming:
                    if value['id'] in before and value.get('observation') != before[value['id']]:
                        report['errors'].append({'reason': 'old connection observation changed', 'id': value['id']})
                    before[value['id']] = value.get('observation')
                times = sorted(v['elapsedNanos'] / 1e6 for v in mode_facts if v['ok'])
                cpu_after = send('cpu', 'cpu-after-' + mode)
                report['modes'][mode] = {'connections': len(mode_facts), 'elapsedSeconds': time.monotonic() - started,
                                         'nativeProcessCPUMilliseconds': cpu_after['cpuMillis'] - cpu_before['cpuMillis'],
                                         'p50Milliseconds': statistics.median(times) if times else None,
                                         'p95Milliseconds': times[min(len(times) - 1, int(len(times) * .95))] if times else None}
                if args.variant == 'candidate' and report['configurationKnown'] == known_before:
                    report['errors'].append({'reason': 'no verified configuration version in mode', 'mode': mode})
                print(mode + ': ' + json.dumps(report['modes'][mode]), flush=True)
            short_facts = []
            for name in CLIENTS:
                command('shell', 'am', 'start', '-W', '--activity-single-top', '-n', CLIENT + name + '/com.follow.clash.observationclient.ConnectionClientActivity',
                        '--es', 'case', run_id + '-short-' + name, '--ei', 'directPort', fixture.direct, '--ei', 'proxyPort', fixture.proxy_target,
                        '--ei', 'count', args.count, '--ei', 'holdMillis', 0, '--ez', 'short', 'true')
            for name in CLIENTS:
                short_facts.extend(wait_read(CLIENT + name, 'files/socket-facts.json',
                    lambda value: isinstance(value, list) and len(value) == args.count * 3
                    and all(v.get('case') == run_id + '-short-' + name for v in value)))
            facts.extend(short_facts)
            snapshots['short'] = send('snapshot', 'snapshot-short')
            print('short: ' + str(len(short_facts)) + ' controlled sockets closed after echo', flush=True)
            command('shell', 'am', 'start', '-W', '--activity-single-top', '-n', CLIENT + 'a/com.follow.clash.observationclient.ConnectionClientActivity',
                    '--es', 'case', run_id + '-bulk', '--ei', 'directPort', fixture.direct, '--ei', 'proxyPort', fixture.proxy_target,
                    '--ei', 'count', 1, '--ei', 'holdMillis', 90000, '--ei', 'bulkBytes', 524288)
            bulk_facts = wait_read(CLIENT + 'a', 'files/socket-facts.json', lambda value: isinstance(value, list) and len(value) == 3
                                   and all(v.get('case') == run_id + '-bulk' for v in value))
            facts.extend(bulk_facts)
            bulk = next(v for v in bulk_facts if v['protocol'] == 'tcp')
            if not all(v['ok'] for v in bulk_facts):
                report['errors'].append({'reason': 'bulk fixture failed', 'facts': bulk_facts})
            else:
                report['echoPayloadMiBPerSecond'] = bulk['bulkBytes'] / 1048576 / (bulk['bulkElapsedNanos'] / 1e9)
            snapshots['bulk'] = send('snapshot', 'snapshot-bulk')
            if args.variant == 'candidate':
                sample = next(v['metadata'] for v in snapshots['bulk']['connections']
                              if v['metadata']['network'] == 'tcp'
                              and v.get('observation', {}).get('application', {}).get('status') == 'known'
                              and v.get('observation', {}).get('configuration', {}).get('mode') == 'direct')
                report['identityBenchmark'] = send('benchmark', 'identity-benchmark', metadata=sample)
            data = command('exec-out', 'run-as', TARGET, 'cat', 'files/observation-fixture/events.jsonl')
            (out / 'events.jsonl').write_bytes(data)
            events = {v['id']: v for v in (json.loads(line) for line in data.splitlines())}
            event_index = {(v['metadata']['network'], int(v['metadata']['sourcePort']), int(v['metadata']['destinationPort'])): v for v in events.values()}
            live_ids = {v['id'] for v in snapshots['short'].get('connections', [])}
            short_closed = 0
            for fact in short_facts:
                key = ('tcp' if fact['protocol'] == 'tcp' else 'udp', fact.get('sourcePort'), fact['destinationPort'])
                tracked = event_index.get(key)
                if not fact['ok'] or tracked is None:
                    report['errors'].append({'case': fact, 'reason': 'short connection missing from events'})
                    continue
                if args.variant == 'candidate':
                    verify_observation(fact, tracked, 'direct', fact_state.get('inputId'))
                token = next(iter(tokens([fact])))
                if token not in tokens(fixture.received) or token in tokens(fixture.proxied):
                    report['errors'].append({'case': fact, 'reason': 'short connection server path mismatch'})
                if fact['protocol'] == 'tcp' and tracked['id'] not in live_ids:
                    short_closed += 1
            for fact in bulk_facts:
                key = ('tcp' if fact['protocol'] == 'tcp' else 'udp', fact.get('sourcePort'), fact['destinationPort'])
                tracked = event_index.get(key)
                if tracked is None:
                    report['errors'].append({'reason': 'bulk connection event missing', 'case': fact})
                elif args.variant == 'candidate':
                    verify_observation(fact, tracked, 'direct', fact_state.get('inputId'))
            report['shortClosedTCPEvents'] = short_closed
            if short_closed == 0:
                report['errors'].append({'reason': 'short TCP test did not exercise an event absent from the live snapshot'})
            for snapshot in snapshots.values():
                for value in snapshot.get('connections', []):
                    event = events.get(value['id'])
                    if event is None or event.get('observation') != value.get('observation'):
                        report['errors'].append({'reason': 'event/snapshot mismatch', 'id': value['id']})
            send('stop', 'stop')
            process.wait(timeout=20)
    finally:
        if process is not None and process.poll() is None:
            command('shell', 'am', 'force-stop', TARGET, check=False)
            process.wait(timeout=10)
        for name in CLIENTS:
            command('shell', 'am', 'force-stop', CLIENT + name, check=False)
        fixture.close()
        for name, data in [('facts', facts), ('snapshots', snapshots), ('received', fixture.received), ('proxied', fixture.proxied), ('report', report)]:
            (out / (name + '.json')).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'errors': len(report['errors']), 'unknown': len(report['unknown'])}), flush=True)
    if report['errors'] or report['unknown']:
        raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--avd', required=True)
    parser.add_argument('--apk', type=Path, default=ROOT / 'build/verification/na-t01-01/clients/app-under-test.apk')
    parser.add_argument('--variant', choices=('baseline', 'candidate'), default='candidate')
    parser.add_argument('--count', type=int, default=4)
    parser.add_argument('--out', type=Path, default=ROOT / 'build/verification/na-t01-01/device-candidate')
    main(parser.parse_args())
