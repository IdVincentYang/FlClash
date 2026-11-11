import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _connection() => {
  'id': 'controlled-connection',
  'start': '2026-11-11T00:00:00Z',
  'metadata': {'network': 'udp', 'uid': 10123, 'process': 'test.app'},
  'chains': ['test.exit', 'test.group'],
  'rule': 'Domain',
  'rulePayload': 'controlled.test',
  'observation': {
    'version': 1,
    'runtimeEpoch': 'controlled-runtime',
    'application': {
      'status': 'known',
      'uid': 10123,
      'userScope': 'current',
      'packages': ['test.app'],
      'method': 'androidUid',
    },
    'capture': {'status': 'vpn', 'serviceId': 'test-service', 'generation': 7},
    'configuration': {
      'status': 'known',
      'inputId': 'controlled-input',
      'mode': 'rule',
      'routeEpoch': 3,
      'picksVersion': 5,
    },
  },
};

class _RequestListener with CoreEventListener {
  final received = Completer<TrackerInfo>();

  @override
  void onRequest(TrackerInfo connection) => received.complete(connection);
}

class _RequestCollection with CoreEventListener {
  _RequestCollection(this.expected);

  final int expected;
  final records = <TrackerInfo>[];
  final completed = Completer<void>();

  @override
  void onRequest(TrackerInfo connection) {
    records.add(connection);
    if (records.length == expected) completed.complete();
  }
}

void main() {
  test(
    'request dispatch and snapshot decoding preserve the same facts',
    () async {
      final connection = _connection();
      final listener = _RequestListener();
      coreEventManager.addListener(listener);
      addTearDown(() => coreEventManager.removeListener(listener));
      final events = coreEventsFromData(
        jsonDecode(jsonEncode({'type': 'request', 'data': connection})),
      );
      expect(events.single.type, CoreEventType.request);
      coreEventManager.sendEvent(events.single);
      final event = await listener.received.future;
      final snapshot = TrackerInfo.fromJson(connection);
      expect(event.observation, snapshot.observation);
      expect(event.observation!.toJson(), snapshot.observation!.toJson());
      expect(event.observation!.application.packageName, 'test.app');
      expect(event.observation!.application.uid, 10123);
      expect(event.observation!.capture.isVpn, isTrue);
      expect(event.observation!.configuration.inputId, 'controlled-input');
      expect(event.observation!.configuration.mode, 'rule');
      expect(event.chains, ['test.exit', 'test.group']);
      expect(event.rulePayload, 'controlled.test');
      final roundTrip = TrackerInfo.fromJson(
        jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.observation!.toJson(), event.observation!.toJson());
      expect(
        () => event.observation!.application.packages.add('test.wrong'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'legacy records keep unknown identity rather than inferring uid zero',
    () {
      final connection = _connection()..remove('observation');
      final tracker = TrackerInfo.fromJson(connection);
      expect(tracker.observation, isNull);
      expect(const ApplicationIdentity().uid, isNull);
      expect(const ApplicationIdentity().packageName, isNull);
    },
  );

  test('shared uid candidates and other users are never a unique package', () {
    for (final identity in [
      const ApplicationIdentity(
        status: 'ambiguous',
        uid: 10123,
        userScope: 'current',
        packages: ['test.a', 'test.b'],
      ),
      const ApplicationIdentity(
        status: 'known',
        uid: 1010123,
        userScope: 'other',
        packages: ['test.a'],
      ),
    ]) {
      expect(identity.packageName, isNull);
    }
  });

  test('unsupported observation versions cannot assert an application', () {
    final json = Map<String, Object?>.from(_connection()['observation']! as Map)
      ..['version'] = 2;
    final observation = ConnectionObservation.fromJson(json);
    expect(observation.version, 2);
    expect(observation.application.packageName, isNull);
    expect(observation.application.uid, isNull);
    expect(observation.capture.isVpn, isFalse);
    expect(observation.configuration.inputId, isEmpty);
  });

  final bridge = Platform.environment['FLCLASH_CONNECTION_OBSERVATION_FIXTURE'];
  test('decodes actual Go encoder output', () {
    final tracker = TrackerInfo.fromJson(
      jsonDecode(File(bridge!).readAsStringSync()) as Map<String, dynamic>,
    );
    expect(tracker.metadata.process, 'test.app');
    expect(tracker.observation!.application.packageName, 'test.app');
    expect(tracker.observation!.application.uid, 10123);
    expect(tracker.metadata.network, 'udp');
    expect(tracker.rule, 'Match');
  }, skip: bridge == null ? 'Run with the Go encoder fixture path' : false);

  final androidEvents =
      Platform.environment['FLCLASH_ANDROID_OBSERVATION_EVENTS'];
  test(
    'dispatches real Android JNI observations without relabeling',
    () async {
      final values = File(androidEvents!).readAsLinesSync().map((line) {
        return jsonDecode(line) as Map<String, dynamic>;
      }).toList();
      expect(values, isNotEmpty);
      final listener = _RequestCollection(values.length);
      coreEventManager.addListener(listener);
      addTearDown(() => coreEventManager.removeListener(listener));
      for (final event in coreEventsFromData([
        for (final value in values) {'type': 'request', 'data': value},
      ])) {
        coreEventManager.sendEvent(event);
      }
      await listener.completed.future;
      for (var i = 0; i < values.length; i++) {
        final connection = listener.records[i];
        final observation = connection.observation!;
        expect(connection, TrackerInfo.fromJson(values[i]));
        expect(observation.version, 1);
        expect(observation.runtimeEpoch, isNotEmpty);
        expect(observation.capture.isVpn, isTrue);
        expect(observation.application.uid, connection.metadata.uid);
        expect(observation.configuration.status, isIn(['known', 'unknown']));
        if (observation.configuration.status == 'known') {
          expect(observation.configuration.inputId, isNotEmpty);
          expect(
            observation.configuration.mode,
            isIn(['rule', 'global', 'direct']),
          );
        } else {
          expect(observation.configuration.inputId, isEmpty);
        }
        if (observation.application.status == 'ambiguous') {
          expect(observation.application.packageName, isNull);
          expect(observation.application.packages, hasLength(2));
          expect(connection.metadata.process, isEmpty);
        } else {
          expect(observation.application.status, 'known');
          expect(
            observation.application.packageName,
            connection.metadata.process,
          );
        }
      }
      expect(
        listener.records.any(
          (record) => record.observation!.configuration.status == 'known',
        ),
        isTrue,
      );
    },
    skip: androidEvents == null ? 'Run with the Android JNI event file' : false,
  );
}
