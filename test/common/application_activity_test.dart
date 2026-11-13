import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/application_activity.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 2);
  ApplicationActivityStore store({int capacity = 4096}) =>
      ApplicationActivityStore(capacity: capacity)
        ..setContext('runtime-a', observing: true, now: now);

  test('Core internal DNS is excluded from both events and snapshots', () {
    final s = store();
    final internal = [
      for (final address in ['8.8.8.8', '1.1.1.1'])
        activityConnection(
          'core-$address',
          status: 'notObserved',
          host: '',
          ip: address,
        ).copyWith(
          metadata: Metadata(
            inboundType: 'Inner',
            network: 'tcp',
            sourcePort: '0',
            destinationIP: address,
            destinationPort: '443',
          ),
        ),
    ];
    for (final info in internal) {
      s.addEvent(info);
    }
    expect(s.snapshot().connections, isEmpty);
    s.applySnapshot(internal, startedRevision: s.revision, now: now);
    expect(s.snapshot().apps, isEmpty);
    expect(s.snapshot().hasSnapshot, true);
    expect(s.snapshot().interrupted, false);
  });

  test(
    'apps visiting the same DNS addresses still retain known or unknown owners',
    () {
      final s = store();
      final chrome =
          activityConnection(
            'chrome',
            package: 'com.android.chrome',
            host: '',
            ip: '8.8.8.8',
          ).copyWith(
            metadata: const Metadata(
              inboundType: 'Tun',
              destinationIP: '8.8.8.8',
              destinationPort: '443',
            ),
          );
      final unknown =
          activityConnection(
            'unknown',
            status: 'lookupFailed',
            host: '',
            ip: '1.1.1.1',
          ).copyWith(
            metadata: const Metadata(
              inboundType: 'Tun',
              destinationIP: '1.1.1.1',
              destinationPort: '443',
            ),
          );
      s.applySnapshot([chrome, unknown], startedRevision: s.revision, now: now);
      expect(s.snapshot().connections.map((item) => item.info.id), [
        'chrome',
        'unknown',
      ]);
      expect(s.snapshot().apps.map((item) => item.application.status).toSet(), {
        'known',
        'lookupFailed',
      });
    },
  );

  test(
    'internal runtime metadata does not invalidate a valid app snapshot',
    () {
      final s = store();
      final internal = activityConnection(
        'core',
        epoch: 'another-runtime',
      ).copyWith(metadata: const Metadata(inboundType: 'Inner'));
      s.applySnapshot(
        [internal, activityConnection('app')],
        startedRevision: s.revision,
        now: now,
      );
      expect(s.snapshot().fresh, true);
      expect(s.snapshot().connections.single.info.id, 'app');
    },
  );

  test('App, App plus Host, and Host across Apps share one retained set', () {
    final s = store();
    for (final info in [
      activityConnection('a1'),
      activityConnection('a2'),
      activityConnection('b1', package: 'test.app.b', uid: 10002),
      activityConnection('a3', host: 'other.test'),
    ]) {
      s.addEvent(info);
    }
    final state = s.snapshot();
    expect(state.apps.map((item) => item.totals.connectionCount), [3, 1]);
    expect(
      state
          .hostsForApp('package:test.app.a')
          .map((item) => item.totals.connectionCount),
      [2, 1],
    );
    expect(
      state
          .appsForHost('host:example.test')
          .map((item) => item.totals.connectionCount),
      [2, 1],
    );
    expect(() => state.connections.clear(), throwsUnsupportedError);
  });

  test('duplicate events and overlapping snapshots count one connection', () {
    final s = store();
    final info = activityConnection('a');
    s.addEvent(info);
    s.addEvent(info);
    s.applySnapshot([info], startedRevision: s.revision, now: now);
    s.addEvent(info);
    expect(s.snapshot().apps.single.totals.connectionCount, 1);
    expect(s.snapshot().apps.single.totals.activeCount, 1);
  });

  test('a short connection survives a complete empty snapshot', () {
    final s = store()..addEvent(activityConnection('short'));
    expect(s.snapshot().apps.single.totals.activeCount, null);
    s.applySnapshot([], startedRevision: s.revision, now: now);
    expect(s.snapshot().apps.single.totals.connectionCount, 1);
    expect(s.snapshot().apps.single.totals.activeCount, 0);
    s.addEvent(activityConnection('short'));
    expect(s.snapshot().apps.single.totals.activeCount, 0);
  });

  test('an event arriving during a snapshot is not declared closed by it', () {
    final s = store();
    final revision = s.revision;
    s.addEvent(activityConnection('new'));
    s.applySnapshot([], startedRevision: revision, now: now);
    expect(s.snapshot().connections.single.active, null);
    s.applySnapshot([], startedRevision: s.revision, now: now);
    expect(s.snapshot().connections.single.active, false);
  });

  test(
    'failure and background gaps keep counts but invalidate active claims',
    () {
      final s = store();
      final info = activityConnection('live');
      s.applySnapshot([info], startedRevision: s.revision, now: now);
      s.markUncertain(failed: true);
      expect(s.snapshot().snapshotFailed, true);
      expect(s.snapshot().apps.single.totals.activeCount, null);
      expect(s.snapshot().connections.length, 1);
      s.markUncertain(interrupted: true);
      s.applySnapshot([info], startedRevision: s.revision, now: now);
      expect(s.snapshot().apps.single.totals.activeCount, 1);
      expect(s.snapshot().snapshotFailed, false);
      expect(s.snapshot().interrupted, true);
    },
  );

  test(
    'later samples only update counters, not identity, rule or exit facts',
    () {
      final s = store();
      final original = activityConnection('same');
      s.addEvent(original);
      s.applySnapshot(
        [
          activityConnection(
            'same',
            package: 'wrong.app',
            exit: 'changed',
            input: 'new-input',
            host: 'wrong.test',
            upload: 10,
          ),
        ],
        startedRevision: s.revision,
        now: now,
      );
      final record = s.snapshot().connections.single;
      expect(record.info, original);
      expect(record.upload, 10);
      expect(record.activityAt, now);
      expect(record.info.observation!.configuration.inputId, 'input-a');
    },
  );

  test('shared UID is not counted once under every candidate app', () {
    final s = store()
      ..addEvent(
        activityConnection(
          'shared',
          status: 'ambiguous',
          candidates: ['test.app.a', 'test.app.b'],
        ),
      );
    expect(s.snapshot().apps.length, 1);
    expect(s.snapshot().apps.single.application.packageName, null);
    expect(s.snapshot().hostsForApp('package:test.app.a'), isEmpty);
  });

  test(
    'unknown legacy UID and future observation versions do not become apps',
    () {
      final s = store();
      final info = activityConnection('legacy').copyWith(
        observation: null,
        metadata: const Metadata(uid: 0, process: 'wrong.app'),
      );
      s.addEvent(info);
      expect(s.snapshot().connections, isEmpty);
      s.applySnapshot([info], startedRevision: s.revision, now: now);
      expect(s.snapshot().apps.single.application.packageName, null);
      expect(s.snapshot().apps.single.application.uid, null);
    },
  );

  test('Host normalization retains IP fallback without guessing a domain', () {
    final s = store();
    s.addEvent(activityConnection('domain', host: 'Example.Test.'));
    s.addEvent(activityConnection('ip', host: ''));
    expect(
      s.snapshot().hostsForApp('package:test.app.a').map((item) => item.key),
      containsAll(['host:example.test', 'ip:192.0.2.1']),
    );
  });

  test('old runtime events cannot switch the authoritative runtime', () {
    final s = store()..addEvent(activityConnection('old'));
    s.setContext('runtime-b', observing: true, now: now);
    s.addEvent(activityConnection('late'));
    s.addEvent(activityConnection('new', epoch: 'runtime-b'));
    expect(s.snapshot().connections.map((item) => item.info.id), ['new']);
    s.applySnapshot(
      [activityConnection('late')],
      startedRevision: s.revision,
      now: now,
    );
    expect(s.snapshot().connections.map((item) => item.info.id), ['new']);
    expect(s.snapshot().snapshotFailed, true);
  });

  test('stop retains history; clear excludes pre-clear live connections', () {
    final s = store()..addEvent(activityConnection('old'));
    s.setContext('runtime-a', observing: false, now: now);
    s.addEvent(activityConnection('while-stopped'));
    expect(s.snapshot().connections.length, 1);
    s.setContext('runtime-a', observing: true, now: now);
    s.clear(now);
    s.applySnapshot(
      [
        activityConnection('old'),
        activityConnection('new', start: now.add(const Duration(seconds: 1))),
      ],
      startedRevision: s.revision,
      now: now,
    );
    expect(s.snapshot().connections.map((item) => item.info.id), ['new']);
    expect(s.snapshot().since, now);
  });

  test(
    'retention is bounded and an earlier immutable view stays unchanged',
    () {
      final s = store(capacity: 2)..addEvent(activityConnection('one'));
      final old = s.snapshot();
      for (final id in ['two', 'three', 'four']) {
        s.addEvent(activityConnection(id));
      }
      expect(s.snapshot().connections.map((item) => item.info.id), [
        'three',
        'four',
      ]);
      expect(s.snapshot().truncated, true);
      expect(old.connections.single.info.id, 'one');
      expect(old.truncated, false);
    },
  );

  test(
    'ten thousand connections remain bounded and the three query scopes agree',
    () {
      final s = store();
      final ingest = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        s.addEvent(
          activityConnection(
            'load-$i',
            package: 'test.app.${i % 10}',
            uid: 10001 + i % 10,
            host: 'host-${i % 20}.test',
          ),
        );
      }
      ingest.stop();
      final view = s.snapshot();
      final query = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        expect(view.apps.length, 10);
        expect(view.hostsForApp('package:test.app.0').length, 2);
        expect(view.appsForHost('host:host-0.test').length, 1);
      }
      query.stop();
      expect(view.connections.length, 4096);
      expect(
        view.apps.fold(0, (sum, app) => sum + app.totals.connectionCount),
        4096,
      );
      expect(view.truncated, true);
      final output = Platform.environment['FLCLASH_ACTIVITY_BENCHMARK_FILE'];
      if (output != null) {
        File(output).writeAsStringSync(
          jsonEncode({
            'ingestConnections': 10000,
            'retained': view.connections.length,
            'ingestMicroseconds': ingest.elapsedMicroseconds,
            'queryRounds': 100,
            'threeScopeQueryMicroseconds': query.elapsedMicroseconds,
          }),
        );
      }
    },
  );

  final nativeSnapshot =
      Platform.environment['FLCLASH_INTERNAL_CONNECTION_FIXTURE'];
  if (nativeSnapshot != null) {
    test('native snapshot separates Core DNS from application traffic', () {
      final data = jsonDecode(File(nativeSnapshot).readAsStringSync()) as Map;
      final infos = (data['connections'] as List)
          .map((item) => TrackerInfo.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      expect(infos.map((item) => item.metadata.inboundType), ['Inner', 'Tun']);
      final s = ApplicationActivityStore()
        ..setContext(
          infos.last.observation!.runtimeEpoch,
          observing: true,
          now: now,
        );
      s.applySnapshot(infos, startedRevision: s.revision, now: now);
      expect(
        s.snapshot().connections.single.info.metadata.destinationIP,
        '8.8.8.8',
      );
      expect(
        s.snapshot().apps.single.application.packageName,
        'com.android.chrome',
      );
      expect(s.snapshot().fresh, true);
      expect(infos.length, 2);
    });
  }

  final path = Platform.environment['FLCLASH_ANDROID_OBSERVATION_EVENTS'];
  if (path != null) {
    test(
      'real Android JNI events aggregate after production model decoding',
      () {
        final infos = File(path)
            .readAsLinesSync()
            .map(
              (line) => TrackerInfo.fromJson(
                Map<String, Object?>.from(jsonDecode(line) as Map),
              ),
            )
            .toList();
        final s = ApplicationActivityStore()
          ..setContext(
            infos.first.observation!.runtimeEpoch,
            observing: true,
            now: now,
          );
        for (final info in infos) {
          s.addEvent(info);
          s.addEvent(info);
        }
        final state = s.snapshot();
        expect(infos.length, 195);
        expect(state.connections.length, 195);
        expect(state.apps.length, 3);
        expect(
          state.apps
              .where((item) => item.application.packageName != null)
              .fold(0, (sum, item) => sum + item.totals.connectionCount),
          99,
        );
        expect(
          state.apps
              .where((item) => item.application.status == 'ambiguous')
              .single
              .totals
              .connectionCount,
          96,
        );
        expect(
          state.connections.map((item) => item.info).toSet(),
          infos.toSet(),
        );
      },
    );
  }
}
