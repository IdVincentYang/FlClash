import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/lib.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Bridge {
  _Bridge(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final response = json.decode(line) as Map;
          if (response['event'] == 'requestState') {
            onNativeState?.call(response['value'] as String);
            return;
          }
          _pending.remove(response['id'])?.complete(response['result']);
        });
  }

  final Process process;
  void Function(String)? onNativeState;
  final _pending = <int, Completer<Object?>>{};
  int _sequence = 0;

  Future<Object?> call(String method, [Object? arguments]) {
    final id = ++_sequence;
    final result = Completer<Object?>();
    _pending[id] = result;
    process.stdin.writeln(
      json.encode({'id': id, 'method': method, 'arguments': arguments}),
    );
    return result.future.timeout(const Duration(seconds: 15));
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
}

class _BridgeSetup extends SetupAction {
  _BridgeSetup(Service native, Request requests)
    : super.scoped(isAndroid: true, native: native, requests: requests);

  Completer<void>? buildGate;
  Completer<void>? buildEntered;
  int builds = 0;

  @override
  void resetCoreTraffic() {}

  @override
  Future<AuthorizeCode> authorizeCore() async => AuthorizeCode.none;

  @override
  Future<({String yaml, String md5})> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    NetworkProps? network,
    bool? dnsOverride,
    bool? ntpOverride,
    bool? safeMode,
  }) async {
    final gate = buildGate;
    buildGate = null;
    if (gate != null) {
      buildEntered?.complete();
      await gate.future;
    }
    final yaml =
        '# build ${++builds}\nmixed-port: 7890\nmode: rule\nrules: ["MATCH,DIRECT"]\n';
    return (yaml: yaml, md5: md5.convert(utf8.encode(yaml)).toString());
  }
}

class _BridgeRequests extends Request {
  _BridgeRequests(Service native)
    : super.scoped(native: native, isAndroid: true);
  Completer<void>? geoEntered;
  Completer<void>? geoGate;
  @override
  Future<bool> recoverMissingGeo(CoreController core) async {
    geoEntered!.complete();
    await geoGate!.future;
    return true;
  }
}

class _BridgeProfiles extends ProfilesAction {
  _BridgeProfiles(this.requests);
  final Request requests;
  @override
  Request get requestClient => requests;
  @override
  Future<Profile?> ensureFile(
    Profile profile, {
    Future<bool> Function()? isCurrent,
  }) async => profile;
}

class _BridgeProxies extends ProxiesAction {
  @override
  Future<void> updateGroups({Future<bool> Function()? isCurrent}) async {}
}

class _BridgeCommon extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

class _BridgeProviders extends Providers {
  @override
  Future<void> syncProviders({Future<bool> Function()? isCurrent}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final classpath = Platform.environment['L2_JVM_BRIDGE_CLASSPATH'];
  test(
    'real Dart setup waits for JVM owned cleanup and starts a new activation',
    () async {
      final directory = await Directory.systemTemp.createTemp('config-bridge-');
      AppPath.supportDirectory = () async => directory;
      AppPath.temporaryDirectory = () async => directory;
      AppPath.cacheDirectory = () async => directory;
      SharedPreferences.setMockInitialValues({});
      await AppLocalizations.load(const Locale('en'));
      globalState.packageInfo = PackageInfo(
        appName: 'FlClash',
        packageName: 'test.config.bridge',
        version: '0',
        buildNumber: '0',
      );
      final process = await Process.start(
        Platform.environment['L2_JAVA'] ?? 'java',
        ['-cp', classpath!, 'com.follow.clash.ConfigApplyBridge'],
      );
      final stderr = StringBuffer();
      final errors = process.stderr
          .transform(utf8.decoder)
          .listen(stderr.write);
      final bridge = _Bridge(process);
      final native = Service();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      bridge.onNativeState = (value) {
        unawaited(
          messenger.handlePlatformMessage(
            native.methodChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('requestState', value),
            ),
            (_) {},
          ),
        );
      };
      Completer<void>? completedReplyGate;
      Completer<void>? completedReplyEntered;
      String? lastSubmittedInput;
      var syncFailure = false;
      messenger.setMockMethodCallHandler(native.methodChannel, (call) async {
        if (call.method == 'syncState' && syncFailure) return 'fixture failure';
        if (call.method == 'applyConfig') {
          lastSubmittedInput =
              (json.decode(call.arguments as String) as Map)['inputId']
                  as String;
        }
        final result = await bridge.call(call.method, call.arguments);
        if (call.method == 'applyConfig' && completedReplyGate != null) {
          final gate = completedReplyGate!;
          completedReplyGate = null;
          completedReplyEntered!.complete();
          await gate.future;
        }
        return call.method == 'invokeMethod' && result is String
            ? Uint8List.fromList(utf8.encode(result))
            : result;
      });
      final requests = _BridgeRequests(native);
      final setup = _BridgeSetup(native, requests);
      final profile = Profile.normal(label: 'Bridge source');
      final store = db.Database(NativeDatabase.memory());
      db.database = store;
      await store.profiles.put(profile.toCompanion());
      final controller = CoreController.scoped(CoreLib.scoped(native));
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(controller),
          nativeRequestStateProvider.overrideWith(
            () => NativeRequestState.scoped(native),
          ),
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesActionProvider.overrideWith(() => _BridgeProfiles(requests)),
          proxiesActionProvider.overrideWith(_BridgeProxies.new),
          providersProvider.overrideWith(_BridgeProviders.new),
          commonActionProvider.overrideWith(_BridgeCommon.new),
          setupActionProvider.overrideWith(() => setup),
          setupStateProvider(profile.id).overrideWith(
            (_) async => SetupState(
              profileId: profile.id,
              profileLastUpdateDate: null,
              overwriteType: OverwriteType.standard,
              rules: [],
              proxyGroups: [],
              addedRules: [],
              script: null,
              overrideDns: false,
              dns: const Dns(),
              dnsOverrideKeys: {},
            ),
          ),
        ],
      );
      globalState.container = container;
      container.read(initProvider.notifier).value = true;
      container.listen(configProvider, (_, _) {});
      requests.attach(container);
      await requests.ready();
      container.read(setupActionProvider.notifier);
      try {
        await controller.start();
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final buildingGate = setup.buildGate!;
        final buildingStart = setup.setRunning(true, initialize: true);
        await setup.buildEntered!.future;
        final replacementDuringBuild = setup.applyProfile(force: true);
        buildingGate.complete();
        expect(await buildingStart, isFalse);
        expect(await replacementDuringBuild, isTrue);
        final initial = await bridge.call('snapshot') as Map;
        expect(initial['starts'], 1);
        expect((initial['state'] as Map)['phase'], 'started');

        await bridge.call('holdActivation');
        final rpcStart = setup.setRunning(true);
        await bridge.call('waitHeldPhase');
        final rpcState = await bridge.call('snapshot') as Map;
        final replacementDuringRpc = setup.applyProfile(force: true);
        await bridge.call('releasePhase');
        expect(await rpcStart, isFalse);
        expect(await replacementDuringRpc, isTrue);
        final rpcReplaced = await bridge.call('snapshot') as Map;
        expect(
          (rpcReplaced['state'] as Map)['intentRevision'],
          (rpcState['state'] as Map)['intentRevision'],
        );
        expect((rpcReplaced['state'] as Map)['phase'], 'started');
        expect((rpcReplaced['fact'] as Map)['inputId'], lastSubmittedInput);

        final replyGate = Completer<void>();
        completedReplyGate = replyGate;
        completedReplyEntered = Completer<void>();
        final completedStart = setup.setRunning(true);
        await completedReplyEntered.future;
        final completedState = await bridge.call('snapshot') as Map;
        expect((completedState['state'] as Map)['phase'], 'started');
        final replacementAfterSuccess = setup.applyProfile(force: true);
        replyGate.complete();
        expect(await completedStart, isFalse);
        expect(await replacementAfterSuccess, isTrue);
        final beforeFailure = await bridge.call('snapshot') as Map;
        expect(
          (beforeFailure['state'] as Map)['intentRevision'],
          (completedState['state'] as Map)['intentRevision'],
        );
        expect((beforeFailure['state'] as Map)['phase'], 'started');
        expect((beforeFailure['fact'] as Map)['inputId'], lastSubmittedInput);
        expect(
          (beforeFailure['phases'] as List).whereType<Map>().where(
            (item) => item['first'] == 'abortConfig',
          ),
          isEmpty,
        );
        await bridge.call('holdCleanupAndFailInstall');
        var failedFinished = false;
        final failed = setup.applyProfile(force: true).then((value) {
          failedFinished = true;
          return value;
        });
        for (var i = 0; i < 100; i++) {
          final snapshot = await bridge.call('snapshot') as Map;
          if ((snapshot['state'] as Map)['phase'] == 'failed') break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(failedFinished, isFalse);
        final blocked = await bridge.call('snapshot') as Map;
        expect((blocked['state'] as Map)['phase'], 'failed');
        expect(container.read(runTimeProvider), isNull);
        final restarting = setup.setRunning(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(failedFinished, isFalse);
        await bridge.call('releaseCleanup');
        expect(await failed, isFalse);
        expect(await restarting, isTrue);
        final recovered = await bridge.call('snapshot') as Map;
        expect(recovered['starts'], (beforeFailure['starts'] as int) + 1);
        expect(recovered['stops'], (beforeFailure['stops'] as int) + 1);
        expect((recovered['state'] as Map)['phase'], 'started');
        expect((recovered['fact'] as Map)['businessActive'], isTrue);
        expect(container.read(configStateProvider).fact.businessActive, isTrue);
        requests.partialCommit = true;
        expect(await setup.setRunning(true), isFalse);
        final incomplete = await bridge.call('snapshot') as Map;
        expect((incomplete['state'] as Map)['phase'], 'failed');
        expect((incomplete['state'] as Map)['intentRunning'], isFalse);
        requests.partialCommit = false;
        expect(await setup.setRunning(true), isTrue);
        for (final failure in ['preferences', 'sync', 'input', 'providers']) {
          await setup.setRunning(false);
          final before = await bridge.call('snapshot') as Map;
          final originalPreferences = preferences.sharedPreferencesCompleter;
          Directory? backup;
          File? obstruction;
          if (failure == 'preferences') {
            preferences.sharedPreferencesCompleter = Completer()
              ..complete(null);
          } else if (failure == 'sync') {
            syncFailure = true;
          } else {
            final path = failure == 'input'
                ? '${await appPath.homeDirPath}/config-inputs'
                : '${await appPath.getProvidersRootPath()}/${profile.id}';
            backup = await Directory(path).rename('$path.saved');
            obstruction = await File(path).writeAsString('blocked directory');
          }
          try {
            expect(await setup.setRunning(true), isFalse, reason: failure);
            final failed = await bridge.call('snapshot') as Map;
            expect(
              (failed['state'] as Map)['phase'],
              'failed',
              reason: failure,
            );
            expect((failed['state'] as Map)['intentRunning'], isFalse);
            expect(failed['starts'], before['starts']);
            expect(await native.getRunTime(), isNull);
          } finally {
            preferences.sharedPreferencesCompleter = originalPreferences;
            syncFailure = false;
            if (obstruction != null) {
              await obstruction.delete();
              await backup!.rename(obstruction.path);
            }
          }
          expect(await setup.setRunning(true), isTrue, reason: failure);
        }
        await setup.setRunning(false);
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final beforeInputGate = setup.buildGate!;
        final beforeInput = setup.setRunning(true);
        await setup.buildEntered!.future;
        setup.applyProfileDebounce(force: true, isCurrent: () async => false);
        debouncer.flush(FunctionTag.applyProfile);
        beforeInputGate.complete();
        expect(await beforeInput, isFalse);
        final abandonedBeforeInput = await bridge.call('snapshot') as Map;
        expect((abandonedBeforeInput['state'] as Map)['phase'], 'failed');
        expect(
          (abandonedBeforeInput['state'] as Map)['intentRunning'],
          isFalse,
        );
        expect(await setup.setRunning(true), isTrue);
        for (final scenario in [
          'source-only',
          'queued',
          'external-source',
          'invalid-queued',
          'revoked-queued',
          'invalid-then-valid',
          'late-valid',
        ]) {
          final successorQueued =
              scenario == 'queued' ||
              scenario == 'invalid-then-valid' ||
              scenario == 'late-valid';
          var sourceCurrent = true;
          Completer<void>? queuedCheckEntered;
          Completer<void>? queuedCheckGate;
          await bridge.call('bootstrapInstall');
          requests.geoEntered = Completer<void>();
          requests.geoGate = Completer<void>();
          final abandoned = scenario == 'external-source'
              ? null
              : setup.setRunning(true);
          if (scenario == 'external-source') {
            setup.applyProfileDebounce(
              force: true,
              isCurrent: () async => sourceCurrent,
            );
          }
          await requests.geoEntered!.future;
          final preparing = await bridge.call('snapshot') as Map;
          expect((preparing['state'] as Map)['phase'], 'starting');
          if (['source-only', 'queued', 'external-source'].contains(scenario)) {
            final oldSource = await requests.captureSource(
              'profile:${profile.id}',
            );
            await container
                .read(profilesActionProvider.notifier)
                .useDefaultCustomConfig(profile.id);
            sourceCurrent = false;
            expect(await requests.configSourceCurrent(oldSource), isFalse);
            expect(
              await store.rulesDao.queryProfileCustomRules(profile.id).get(),
              hasLength(1),
            );
          } else {
            var eligible = scenario == 'revoked-queued';
            if (scenario == 'late-valid') {
              queuedCheckEntered = Completer<void>();
              queuedCheckGate = Completer<void>();
            }
            setup.applyProfileDebounce(
              force: true,
              isCurrent: () async {
                queuedCheckEntered?.complete();
                await queuedCheckGate?.future;
                return eligible;
              },
            );
            debouncer.flush(FunctionTag.applyProfile);
            eligible = false;
          }
          var successor = successorQueued && scenario != 'late-valid'
              ? setup.applyProfile(force: true)
              : null;
          await bridge.call('allowInstall');
          requests.geoGate!.complete();
          if (scenario == 'late-valid') {
            await queuedCheckEntered!.future;
            successor = setup.applyProfile(force: true);
            queuedCheckGate!.complete();
          }
          if (abandoned != null) {
            expect(await abandoned, isFalse);
          } else {
            for (var i = 0; i < 100; i++) {
              final state = await bridge.call('snapshot') as Map;
              if ((state['state'] as Map)['phase'] == 'failed') break;
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          }
          if (successor != null) expect(await successor, isTrue);
          final settled = await bridge.call('snapshot') as Map;
          expect(
            (settled['state'] as Map)['phase'],
            successorQueued ? 'started' : 'failed',
          );
          expect(
            settled['stops'],
            (preparing['stops'] as int) + (successorQueued ? 0 : 1),
          );
          if (successorQueued) {
            expect(
              (settled['state'] as Map)['intentRevision'],
              (preparing['state'] as Map)['intentRevision'],
            );
            expect((settled['fact'] as Map)['inputId'], lastSubmittedInput);
            expect((settled['fact'] as Map)['businessActive'], isTrue);
          } else {
            expect((settled['state'] as Map)['intentRunning'], isFalse);
            expect(await native.getRunTime(), isNull);
            expect(await setup.setRunning(true), isTrue);
          }
        }
        expect(stderr.toString(), isEmpty);
      } finally {
        await setup.setRunning(false);
        container.dispose();
        messenger.setMockMethodCallHandler(native.methodChannel, null);
        await bridge.close();
        await errors.cancel();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    skip: classpath == null
        ? 'Run with the compiled JVM bridge classpath.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
