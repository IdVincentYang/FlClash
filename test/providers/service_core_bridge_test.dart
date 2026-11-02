import 'dart:io';

import 'package:fl_clash/common/config_input.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/models/managed_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/policy_core_bridge.dart';

class _UnusedNative extends Mock implements Service {}

void main() {
  final classpath = Platform.environment['L2_JVM_BRIDGE_CLASSPATH'];
  final executable = Platform.environment['FLCLASH_APPLICATION_INPUT_BRIDGE'];
  final compiler = Platform.environment['FLCLASH_MANAGED_PROFILE_COMPILER'];
  test(
    'native intent publications retire real business and DNS without direct fallback',
    () async {
      final home = await Directory.systemTemp.createTemp('service-core-');
      final bridge = PolicyCoreBridge(
        await Process.start(
          Platform.environment['L2_JAVA'] ?? 'java',
          ['-cp', classpath!, 'com.follow.clash.ServiceCoreBridge'],
          environment: {
            'L2_CORE_BRIDGE_HOME': home.path,
            'L2_CORE_BRIDGE_CWD': Directory('core').absolute.path,
          },
        ),
      );
      addTearDown(() async {
        await bridge.close();
        await home.delete(recursive: true);
      });
      final policy = await bridge.call('fixture');
      final before = await bridge.call('fact');
      final input = await ConfigInput.write(
        home: home.path,
        yaml: compileManagedProfile(ManagedPolicy.fromJson(policy)),
        runtimeEpoch: before['runtimeEpoch'] as String,
        profileId: 7,
        profileName: 'Synthetic service',
        selectedMap: {},
        testUrl: 'http://127.0.0.1/',
        sources: [
          await Request.scoped(
            native: _UnusedNative(),
            isAndroid: false,
          ).captureSource('profile:7'),
        ],
      );
      Future<void> apply(Map state) async {
        final result = await bridge.call(
          'apply',
          input.toRequest(
            active: true,
            requestId:
                state['requestId'] as int? ?? state['intentRevision'] as int,
          ),
        );
        expect(result['status'], 'activated', reason: '$result');
      }

      await apply(await bridge.call('prepare', true));
      expect((await bridge.call('probe', 'before.example.test'))['body'], 'A');
      final direct = await bridge.call('probe', 'before.lan.test');
      expect(direct['body'], 'DIRECT');
      expect(direct['dnsFailed'], false);
      final pause = await bridge.call('pause');
      expect(pause['stopped'], true);
      expect((pause['state'] as Map)['intentRunning'], true);
      expect((pause['state'] as Map)['serviceId'], '');
      final stopped = await bridge.call('probe', 'paused.example.test');
      expect(stopped['businessFailed'], true);
      expect(stopped['dnsFailed'], true);
      expect(stopped['direct'], direct['direct']);
      final resume = await bridge.call('pauseIntent', false);
      await apply(resume['state'] as Map);
      expect((await bridge.call('probe', 'resumed.example.test'))['body'], 'A');
      await bridge.call('lose');
      expect(
        ((await bridge.call('snapshot'))['state'] as Map)['intentRunning'],
        false,
      );
      final lost = await bridge.call('probe', 'lost.example.test');
      expect(lost['businessFailed'], true);
      expect(lost['dnsFailed'], true);
      expect(lost['direct'], direct['direct']);
      final noResume = await bridge.call('pauseIntent', false);
      expect((noResume['state'] as Map)['intentRunning'], false);
      expect(
        ((await bridge.call('snapshot'))['fact'] as Map)['businessActive'],
        false,
      );
    },
    skip: classpath == null || executable == null || compiler == null
        ? 'requires local JVM/Core bridges and the managed profile compiler'
        : false,
  );
}
