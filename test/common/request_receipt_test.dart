import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Native extends Mock implements Service {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ProviderContainer container;
  late Request client;
  late _Native native;
  final calls = <Map<String, Object?>>[];
  var ack = 'ok';
  var granted = false;
  var owner = 1;
  var revision = 1;
  Map<String, Object?> getState() => {
    'processEpoch': 'fixture',
    'revision': revision,
    'intentRevision': 1,
    'intentRunning': false,
    'paused': false,
    'phase': 'stopped',
    'reason': 'userStop',
  };
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('request-receipt-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
    globalState.packageInfo = PackageInfo(
      appName: 'fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
    );
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    ack = 'ok';
    granted = false;
    owner = 1;
    revision = 1;
    native = _Native();
    when(() => native.requestControl(any())).thenAnswer((call) async {
      final data = Map<String, Object?>.from(
        call.positionalArguments.first as Map,
      );
      calls.add(data);
      if (data['action'] == 'complete') {
        if (ack == 'before') throw StateError('synthetic ack failure');
        granted = false;
        if (ack == 'after') throw StateError('synthetic ack loss');
      }
      if (data['action'] == 'grant' || data['action'] == 'lock') granted = true;
      return switch (data['action']) {
        'attach' => {'client': 'fixture'},
        'inspect' => {
          'state': getState(),
          'phase': 'ready',
          'owner': owner,
          'dataset': 1,
          'sourceRevision': 0,
          'operation': 0,
          'commits': granted && data['id'] == null ? 1 : 0,
          'hasProxy': false,
        },
        'begin' => {
          'id': 'fixture-request',
          'owner': owner,
          'dataset': 1,
          'sourceRevision': 0,
          'operation': 0,
          'user': 'fixture',
          'password': 'fixture',
          'endpoint': '127.0.0.1:1',
        },
        'lock' => {'id': 'fixture-lock'},
        _ => {'ok': true},
      };
    });
    when(native.getRequestState).thenAnswer((_) async => getState());
    container = ProviderContainer();
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    client = Request.scoped(native: native, isAndroid: true)..attach(container);
    await client.ready();
  });
  tearDown(() async {
    await client.detach();
    container.dispose();
    final marker = File('${root.path}/request-recovery-required');
    if (await marker.exists()) await marker.delete();
  });

  for (final local in [false, true]) {
    for (final failure in ['before', 'after']) {
      test(
        '${local ? 'localCommit' : 'RequestSession.commit'} preserves recovery marker for ack loss $failure release',
        () async {
          ack = failure;
          var actionRan = false;
          final work = local
              ? client.localCommit(() async {
                  actionRan = true;
                })
              : () async {
                  final session = await client.begin(
                    key: 'profile:1',
                    url: 'http://127.0.0.1/',
                    mode: RequestMode.direct,
                  );
                  try {
                    await session.commit(() async {
                      actionRan = true;
                    });
                  } finally {
                    session.close();
                  }
                }();
          await expectLater(
            work.timeout(const Duration(seconds: 2)),
            throwsA(
              isA<RequestUnavailable>().having(
                (e) => e.code,
                'code',
                'request_partial_commit',
              ),
            ),
          );
          expect(actionRan, true);
          expect(client.partialCommit, true);
          expect(
            await File('${root.path}/request-recovery-required').exists(),
            true,
          );
          expect(
            calls.where((c) => c['action'] == 'inspect' && c['id'] != null),
            isNotEmpty,
          );
        },
      );
    }
  }
  test('normal receipt removes its marker after native release', () async {
    await client.localCommit(() async {});
    expect(granted, false);
    expect(client.partialCommit, false);
    expect(
      await File('${root.path}/request-recovery-required').exists(),
      false,
    );
  });
  test(
    'ordinary material source survives own begin cancellation and uses the current Owner',
    () async {
      final source = await client.captureSource('profile:1');
      owner = 2;
      revision = 2;
      final session = await client.begin(
        key: 'profile:1',
        url: 'http://127.0.0.1/',
        mode: RequestMode.direct,
        queuedMaterialSource: source,
        sourceIsCurrent: () async => true,
      );
      try {
        expect(calls.lastWhere((c) => c['action'] == 'begin')['owner'], 2);
        expect(
          await client.materialSessionCurrent(
            session,
            await client.captureSource('profile:1'),
          ),
          true,
        );
      } finally {
        session.close();
      }
    },
  );
  test(
    'explicit source retains native intent and Owner restrictions',
    () async {
      final source = await client.captureSource('profile:1');
      owner = 2;
      revision = 2;
      await expectLater(
        client.begin(
          key: 'profile:1',
          url: 'http://127.0.0.1/',
          mode: RequestMode.direct,
          expectedSource: source,
        ),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(calls.where((c) => c['action'] == 'begin'), isEmpty);
    },
  );
  test('desktop registration also checks the source callback', () async {
    final desktop = Request.scoped(native: native, isAndroid: false)
      ..attach(container);
    await expectLater(
      desktop.begin(
        key: 'profile:1',
        url: 'http://127.0.0.1/',
        sourceIsCurrent: () async => false,
      ),
      throwsA(isA<RequestUnavailable>()),
    );
    await desktop.detach();
  });
}
