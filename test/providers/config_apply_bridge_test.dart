import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
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
import '../helpers/policy_core_bridge.dart';

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
    : requests = requests,
      super.scoped(isAndroid: true, native: native, requests: requests);

  final Request requests;

  Completer<void>? buildGate;
  Completer<void>? buildEntered;
  Future<bool> Function()? heldCurrent;
  int builds = 0;
  String? providerURL;

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
    void Function(Map<String, Object?>)? onSourceUse,
    void Function(Map<String, Object?>)? onRuleLedger,
    bool allowSourceReview = true,
    Future<bool> Function()? isCurrent,
    Map<String, dynamic>? previewDocument,
    bool previewOwnRouting = false,
  }) async {
    final gate = buildGate;
    buildGate = null;
    if (gate != null) {
      heldCurrent = isCurrent;
      buildEntered?.complete();
      await gate.future;
    }
    final yaml =
        '# build ${++builds}\nmixed-port: 7890\nmode: rule\nrules: ["MATCH,DIRECT"]\n'
        '${providerURL == null ? '' : 'proxy-providers:\n  queue-fixture:\n    type: http\n    url: $providerURL\n'}';
    final profile = (await db.database.profilesDao.query().get()).getProfile(
      setupState.profileId!,
    )!;
    final accepted =
        await SourceAcceptance(
          core: ref.read(coreHandlerProvider),
          requests: requests,
          confirm: (_) async =>
              const SourceReviewDecision(automatic: true, routing: 'source'),
        ).review(
          source: await requests.captureSource('profile:${profile.id}'),
          identity: SourceAcceptance.fingerprint({
            'kind': 'profile',
            'id': profile.id,
            'url': profile.url,
            'type': profile.type.name,
          }),
          settings: const {'consumer': 'controlled JVM lifecycle fixture'},
          body: yaml,
          label: profile.realLabel,
          location: profile.url,
          kind: 'profile',
          automatic: !allowSourceReview,
          isCurrent: isCurrent,
        );
    onSourceUse?.call(accepted.use);
    await accepted.release();
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
  final executionEvents = <bool>[];
  @override
  Request get requestClient => requests;
  @override
  void setupExecutionChanged(bool busy) {
    executionEvents.add(busy);
    super.setupExecutionChanged(busy);
  }

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
  final sourceExecutable =
      Platform.environment['FLCLASH_APPLICATION_INPUT_BRIDGE'];
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
      final sourceBridge = PolicyCoreBridge(
        await Process.start(
          sourceExecutable!,
          [r'-test.run=^TestApplicationInputBridge$'],
          workingDirectory: Directory('core').absolute.path,
          environment: {
            'FLCLASH_APPLICATION_INPUT_BRIDGE_HOME': directory.path,
          },
        ),
      );
      await sourceBridge.call('sourceState');
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
      Completer<void>? pauseReplyGate;
      Completer<void>? pauseReplyEntered;
      String? lastSubmittedInput;
      var syncFailure = false;
      Completer<void>? identityReadEntered;
      final observedCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(native.methodChannel, (call) async {
        observedCalls.add(call);
        if (call.method == 'invokeMethod') {
          final input = jsonDecode(call.arguments as String) as Map;
          if (input['method'] == 'sourceAcceptance') {
            final sourceRequest = input['arguments'] as Map;
            final snapshot =
                jsonDecode(
                      await bridge.call(
                            'requestControl',
                            jsonEncode({
                              'action': 'inspect',
                              'client': 'bridge',
                              'key': sourceRequest['key'],
                            }),
                          )
                          as String,
                    )
                    as Map;
            await sourceBridge.call('sourceFrontendState', {
              'client': 'bridge',
              'dataset': snapshot['dataset'],
              'state': snapshot['state'],
            });
            final envelope = await sourceBridge.call('source', sourceRequest);
            return Uint8List.fromList(
              utf8.encode(jsonEncode({...envelope, 'id': input['id']})),
            );
          }
        }
        if (call.method == 'syncState' && syncFailure) return 'fixture failure';
        if (call.method == 'applyConfig') {
          lastSubmittedInput =
              (json.decode(call.arguments as String) as Map)['inputId']
                  as String;
        }
        final result = await bridge.call(call.method, call.arguments);
        if (call.method == 'getRequestState' && identityReadEntered != null) {
          identityReadEntered!.complete();
          identityReadEntered = null;
        }
        if ((call.method == 'preparePauseIntent' ||
                call.method == 'getRequestState') &&
            pauseReplyGate != null) {
          final gate = pauseReplyGate!;
          pauseReplyGate = null;
          pauseReplyEntered!.complete();
          await gate.future;
        }
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
      final profiles = _BridgeProfiles(requests);
      final admissionObservations = <Map<String, Object?>>[];
      Future<void> recordAdmission(Map<String, Object?> value) async {
        admissionObservations.add(value);
        final path = Platform.environment['L2_SETUP_ADMISSION_OBSERVATION'];
        if (path != null) {
          await File(path).writeAsString(jsonEncode(admissionObservations));
        }
      }

      final profile = Profile.normal(label: 'Bridge source');
      final store = db.Database(NativeDatabase.memory());
      db.database = store;
      await store.profiles.put(profile.toCompanion());
      final controller = CoreController.scoped(CoreLib.scoped(native));
      final container = ProviderContainer(
        overrides: [
          sourceConfirmationProvider.overrideWithValue(
            (_) async =>
                const SourceReviewDecision(automatic: true, routing: 'source'),
          ),
          coreHandlerProvider.overrideWithValue(controller),
          nativeRequestStateProvider.overrideWith(
            () => NativeRequestState.scoped(native),
          ),
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesActionProvider.overrideWith(() => profiles),
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
        Future<Map> waitPhase(String phase) async {
          for (var i = 0; i < 100; i++) {
            final snapshot = await bridge.call('snapshot') as Map;
            if ((snapshot['state'] as Map)['phase'] == phase) return snapshot;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          throw StateError('Native phase did not settle: $phase');
        }

        final observedDispatches = <Map<String, Object?>>[];
        for (final paused in [true, false]) {
          final before = await bridge.call('snapshot') as Map;
          final gate = Completer<void>();
          pauseReplyGate = gate;
          pauseReplyEntered = Completer<void>();
          final pending = setup.setPaused(paused);
          await pauseReplyEntered.future;
          final prepared =
              (await bridge.call('snapshot') as Map)['state'] as Map;
          final observed =
              await bridge.call('observeNetwork', {
                    'sourceEpoch': 'pause-observation',
                    'revision': paused ? 1 : 2,
                    'defaultNetworkKind': 'nonVpn',
                    'defaultNetworkId': 'synthetic physical',
                    'directNetworkId': 'synthetic physical',
                    'blockedKnown': true,
                  })
                  as Map;
          for (var i = 0; i < 100; i++) {
            if ((container.read(nativeRequestStateProvider)['revision']
                    as int) >=
                (observed['revision'] as int)) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          final delivered = container.read(nativeRequestStateProvider);
          expect(
            delivered['revision'],
            greaterThan(prepared['revision'] as int),
          );
          expect(delivered['intentRevision'], prepared['intentRevision']);
          gate.complete();
          await pending;
          Map settled = await bridge.call('snapshot') as Map;
          for (var i = 0; i < 100; i++) {
            if ((settled['state'] as Map)['phase'] ==
                (paused ? 'stopped' : 'started')) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
            settled = await bridge.call('snapshot') as Map;
          }
          final state = settled['state'] as Map;
          observedDispatches.add({
            'phase': state['phase'],
            'paused': state['paused'],
            'intentRunning': state['intentRunning'],
            'sameIntent': state['intentRevision'] == prepared['intentRevision'],
            'serviceEmpty': state['serviceId'] == '',
            'starts': (settled['starts'] as int) - (before['starts'] as int),
            'stops': (settled['stops'] as int) - (before['stops'] as int),
          });
          // Record pause first, then stage resume independently with the same native intent.
          if (paused) {
            await bridge.call('stop', prepared['intentRevision']);
            await waitPhase('stopped');
          }
        }
        expect(observedDispatches, [
          {
            'phase': 'stopped',
            'paused': true,
            'intentRunning': true,
            'sameIntent': true,
            'serviceEmpty': true,
            'starts': 0,
            'stops': 1,
          },
          {
            'phase': 'started',
            'paused': false,
            'intentRunning': true,
            'sameIntent': true,
            'serviceEmpty': false,
            'starts': 1,
            'stops': 0,
          },
        ]);

        final beforePause = await bridge.call('snapshot') as Map;
        await setup.setPaused(true);
        final paused = await waitPhase('stopped');
        expect((paused['state'] as Map)['intentRunning'], true);
        expect((paused['state'] as Map)['paused'], true);
        expect((paused['state'] as Map)['serviceId'], '');
        expect(paused['stops'], (beforePause['stops'] as int) + 1);
        expect(container.read(runTimeProvider), isNull);
        await setup.setPaused(false);
        final resumed = await waitPhase('started');
        expect(resumed['starts'], (beforePause['starts'] as int) + 1);
        await setup.setPaused(true);
        await waitPhase('stopped');
        await setup.setRunning(false);
        await waitPhase('stopped');
        await setup.setPaused(false);
        final manuallyStopped = await waitPhase('stopped');
        expect((manuallyStopped['state'] as Map)['intentRunning'], false);
        expect(manuallyStopped['starts'], resumed['starts']);
        expect(await setup.setRunning(true), true);
        final beforeLate = await waitPhase('started');
        final lateGate = Completer<void>();
        pauseReplyGate = lateGate;
        pauseReplyEntered = Completer<void>();
        final latePause = setup.setPaused(false);
        await pauseReplyEntered.future;
        await setup.setRunning(false);
        await waitPhase('stopped');
        lateGate.complete();
        await latePause;
        final afterLate = await bridge.call('snapshot') as Map;
        expect((afterLate['state'] as Map)['intentRunning'], false);
        expect((afterLate['state'] as Map)['phase'], 'stopped');
        expect(afterLate['starts'], beforeLate['starts']);

        expect(await setup.setRunning(true), true);
        final nativeGate = Completer<void>();
        pauseReplyGate = nativeGate;
        pauseReplyEntered = Completer<void>();
        final nativeOvertaken = setup.setPaused(true);
        await pauseReplyEntered.future;
        final nativeId = await bridge.call('prepareRunIntent', {
          'running': true,
          'paused': false,
          'source': 'tile',
        });
        final external =
            json.decode(
                  await bridge.call(
                        'applyConfig',
                        json.encode({
                          'inputId': lastSubmittedInput,
                          'requestId': nativeId,
                          'active': true,
                        }),
                      )
                      as String,
                )
                as Map;
        expect(external['status'], 'activated');
        await waitPhase('started');
        for (
          var i = 0;
          i < 100 && container.read(runTimeProvider) == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(container.read(runTimeProvider), isNotNull);
        nativeGate.complete();
        await nativeOvertaken;
        expect(container.read(runTimeProvider), isNotNull);
        expect(
          (await bridge.call('snapshot') as Map)['starts'],
          (afterLate['starts'] as int) + 2,
        );

        await setup.setRunning(false);
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final beforeInputGate = setup.buildGate!;
        final beforeInput = setup.setRunning(true);
        await setup.buildEntered!.future;
        setup.applyProfileDebounce(force: true, isCurrent: () async => false);
        debouncer.flush(FunctionTag.applyProfile);
        beforeInputGate.complete();
        expect(await beforeInput, isTrue);
        final abandonedBeforeInput = await bridge.call('snapshot') as Map;
        expect((abandonedBeforeInput['state'] as Map)['phase'], 'started');
        expect((abandonedBeforeInput['state'] as Map)['intentRunning'], isTrue);
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
          final originalSurvives = [
            'invalid-queued',
            'revoked-queued',
          ].contains(scenario);
          if (abandoned != null) {
            expect(await abandoned, originalSurvives);
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
            successorQueued || originalSurvives ? 'started' : 'failed',
          );
          expect(
            settled['stops'],
            (preparing['stops'] as int) +
                (successorQueued || originalSurvives ? 0 : 1),
          );
          if (successorQueued || originalSurvives) {
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
        final recoveryOrigin = Map<String, Object?>.from(
          await native.getRequestState(),
        );
        expect(
          await setup.applyProfile(
            force: true,
            allowBootstrap: true,
            expectedRun: recoveryOrigin,
          ),
          isTrue,
        );
        for (final trigger in ['recovery', 'ui']) {
          for (final replacement in ['tile', 'alwaysOn', 'stop', 'token']) {
            await setup.setRunning(false);
            final original = Map<String, Object?>.from(
              await native.getRequestState(),
            );
            final heldMutation = Completer<void>();
            final mutationEntered = Completer<void>();
            final mutation = dataMutations.run(() async {
              mutationEntered.complete();
              await heldMutation.future;
            });
            await mutationEntered.future;
            final readEntered = Completer<void>();
            identityReadEntered = readEntered;
            final buildsBefore = setup.builds;
            final permissionFile = File(
              '${directory.path}/source-acceptance/permissions.json',
            );
            final permissionsBefore = await permissionFile.readAsBytes();
            var httpReceipts = 0;
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            final receiver = server.listen((r) async {
              httpReceipts++;
              r.response.write('proxies: []');
              await r.response.close();
            });
            setup.providerURL =
                'http://127.0.0.1:${server.port}/must-not-download';
            final old = trigger == 'ui'
                ? setup.setRunning(true)
                : setup.applyProfile(
                    force: true,
                    allowBootstrap: true,
                    expectedRun: original,
                  );
            await readEntered.future;
            if (replacement == 'token') {
              final nativeNow = await native.getRequestState();
              final result =
                  jsonDecode(
                        await bridge.call(
                              'applyConfig',
                              jsonEncode({
                                'inputId': lastSubmittedInput,
                                'requestId': nativeNow['intentRevision'],
                                'active': false,
                              }),
                            )
                            as String,
                      )
                      as Map;
              expect(result['status'], isNot('superseded'));
            } else {
              await bridge.call('prepareRunIntent', {
                'running': replacement != 'stop',
                'paused': false,
                'source': replacement == 'stop' ? 'ui' : replacement,
              });
            }
            final newer = await native.getRequestState();
            final afterExternal = await bridge.call('snapshot') as Map;
            final callsBeforeRelease = observedCalls.length;
            heldMutation.complete();
            await mutation;
            expect(
              await old,
              isFalse,
              reason: '$trigger overtaken by $replacement',
            );
            final late = observedCalls.skip(callsBeforeRelease).toList();
            expect(
              late.where(
                (c) => [
                  'applyConfig',
                  'failRunIntent',
                  'failConfigBuild',
                  'syncState',
                ].contains(c.method),
              ),
              isEmpty,
            );
            final controls = late
                .where((c) => c.method == 'requestControl')
                .map((c) => jsonDecode(c.arguments as String) as Map);
            expect(
              controls.where(
                (c) => ['begin', 'permit', 'grant'].contains(c['action']),
              ),
              isEmpty,
            );
            final sourceRPCs = late
                .where((c) => c.method == 'invokeMethod')
                .map((c) => jsonDecode(c.arguments as String) as Map)
                .where((c) => c['method'] == 'sourceAcceptance');
            expect(sourceRPCs, isEmpty);
            expect(setup.builds, buildsBefore);
            expect(await permissionFile.readAsBytes(), permissionsBefore);
            expect(httpReceipts, 0);
            final settled = await native.getRequestState();
            expect(settled['intentRevision'], newer['intentRevision']);
            expect(settled['configToken'], newer['configToken']);
            expect(settled['phase'], newer['phase']);
            final afterOld = await bridge.call('snapshot') as Map;
            expect(afterOld['starts'], afterExternal['starts']);
            expect(afterOld['fact'], afterExternal['fact']);
            setup.providerURL = null;
            await receiver.cancel();
            await server.close(force: true);
          }
        }
        expect(await setup.setRunning(true), isTrue);
        await setup.setRunning(false);
        final staleRecoveryOrigin = await native.getRequestState();
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final newBuildGate = setup.buildGate!;
        final newBuild = setup.setRunning(true);
        await setup.buildEntered!.future;
        final newRun = await native.getRequestState();
        final eventOffset = profiles.executionEvents.length;
        final callsOffset = observedCalls.length;
        final permissionFile = File(
          '${directory.path}/source-acceptance/permissions.json',
        );
        final permissionBefore = await permissionFile.readAsBytes();
        var lateRecoveryFinished = false;
        final lateRecovery = setup
            .applyProfile(
              force: true,
              allowBootstrap: true,
              expectedRun: staleRecoveryOrigin,
            )
            .whenComplete(() => lateRecoveryFinished = true);
        final liveCurrentWhileBlocked = await setup.heldCurrent!();
        await Future<void>.delayed(Duration.zero);
        final rejectedBeforeRelease = lateRecoveryFinished;
        final callsBeforeRelease = observedCalls.skip(callsOffset).toList();
        final permissionAfterOld = await permissionFile.readAsBytes();
        newBuildGate.complete();
        final newerSucceeded = await newBuild;
        final oldSucceeded = await lateRecovery;
        final newFact = await bridge.call('snapshot') as Map;
        final lateRecoveryCalls = observedCalls.skip(callsOffset).toList();
        await recordAdmission({
          'case':
              'late stale recovery versus already executing legitimate setup',
          'liveCurrentWhileBlocked': liveCurrentWhileBlocked,
          'oldRejectedBeforeNewRelease': rejectedBeforeRelease,
          'newSucceeded': newerSucceeded,
          'oldSucceeded': oldSucceeded,
          'newRun': newRun,
          'after': newFact,
          'executionEvents': profiles.executionEvents
              .skip(eventOffset)
              .toList(),
          'cleanupCalls': lateRecoveryCalls
              .where((c) => c.method == 'failRunIntent')
              .map((c) => c.arguments)
              .toList(),
        });
        expect(liveCurrentWhileBlocked, true);
        expect(rejectedBeforeRelease, true);
        expect(oldSucceeded, false);
        expect(newerSucceeded, true);
        expect(profiles.executionEvents.skip(eventOffset), [false]);
        expect(
          lateRecoveryCalls.where((c) => c.method == 'failRunIntent'),
          isEmpty,
        );
        expect(permissionAfterOld, permissionBefore);
        expect(
          callsBeforeRelease.where(
            (c) => [
              'applyConfig',
              'syncState',
              'failRunIntent',
              'invokeMethod',
            ].contains(c.method),
          ),
          isEmpty,
        );
        final staleControls = callsBeforeRelease
            .where((c) => c.method == 'requestControl')
            .map((c) => jsonDecode(c.arguments as String) as Map);
        expect(
          staleControls.where(
            (c) => ['begin', 'permit', 'grant'].contains(c['action']),
          ),
          isEmpty,
        );
        expect(
          (newFact['state'] as Map)['intentRevision'],
          newRun['intentRevision'],
        );
        expect((newFact['state'] as Map)['phase'], 'started');
        expect((newFact['fact'] as Map)['businessActive'], true);
        expect((newFact['fact'] as Map)['inputId'], lastSubmittedInput);

        final sameOrigin = await native.getRequestState();
        final originalRecoverySequence = setup.reserveSetupSequence();
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final sameRunGate = setup.buildGate!;
        final sameRunNewer = setup.applyProfile(
          force: true,
          allowBootstrap: true,
          expectedRun: sameOrigin,
        );
        await setup.buildEntered!.future;
        final sameRunBeforeOld = await native.getRequestState();
        final sameEventOffset = profiles.executionEvents.length;
        final sameCallOffset = observedCalls.length;
        var sameOldFinished = false;
        final sameRunOld = setup
            .applyProfile(
              force: true,
              allowBootstrap: true,
              expectedRun: sameOrigin,
              setupSequence: originalRecoverySequence,
            )
            .whenComplete(() => sameOldFinished = true);
        final sameRunCurrent = await setup.heldCurrent!();
        await Future<void>.delayed(Duration.zero);
        final sameOldRejectedBeforeRelease = sameOldFinished;
        final sameRunCallsBeforeRelease = observedCalls
            .skip(sameCallOffset)
            .toList();
        sameRunGate.complete();
        final sameNewSucceeded = await sameRunNewer;
        final sameOldSucceeded = await sameRunOld;
        final sameRunAfter = await bridge.call('snapshot') as Map;
        await recordAdmission({
          'case':
              'original recovery ordering survives late dispatch even when native identity is unchanged',
          'origin': sameOrigin,
          'beforeOld': sameRunBeforeOld,
          'liveCurrentWhileBlocked': sameRunCurrent,
          'oldRejectedBeforeNewRelease': sameOldRejectedBeforeRelease,
          'newSucceeded': sameNewSucceeded,
          'oldSucceeded': sameOldSucceeded,
          'executionEvents': profiles.executionEvents
              .skip(sameEventOffset)
              .toList(),
          'cleanupCalls': observedCalls
              .skip(sameCallOffset)
              .where((c) => c.method == 'failRunIntent')
              .map((c) => c.arguments)
              .toList(),
          'after': sameRunAfter,
        });
        for (final key in ['processEpoch', 'intentRevision', 'configToken']) {
          expect(sameRunBeforeOld[key], sameOrigin[key]);
        }
        expect(sameRunCurrent, true);
        expect(sameOldRejectedBeforeRelease, true);
        expect(sameNewSucceeded, true);
        expect(sameOldSucceeded, false);
        expect(profiles.executionEvents.skip(sameEventOffset), [false]);
        expect(
          sameRunCallsBeforeRelease.where(
            (c) => [
              'invokeMethod',
              'applyConfig',
              'syncState',
              'failRunIntent',
            ].contains(c.method),
          ),
          isEmpty,
        );
        expect(
          observedCalls
              .skip(sameCallOffset)
              .where((c) => c.method == 'failRunIntent'),
          isEmpty,
        );
        expect((sameRunAfter['state'] as Map)['phase'], 'started');
        expect((sameRunAfter['fact'] as Map)['businessActive'], true);

        await setup.setRunning(false);
        final oldUiRead = Completer<void>();
        pauseReplyGate = oldUiRead;
        pauseReplyEntered = Completer<void>();
        final oldUi = setup.setRunning(true);
        await pauseReplyEntered.future;
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final legalGate = setup.buildGate!;
        final legalSetup = setup.applyProfile(force: true);
        await setup.buildEntered!.future;
        final legalRun = await native.getRequestState();
        final uiEventOffset = profiles.executionEvents.length;
        final uiCallOffset = observedCalls.length;
        var uiFinished = false;
        final oldUiDone = oldUi.whenComplete(() => uiFinished = true);
        oldUiRead.complete();
        final legalStillCurrent = await setup.heldCurrent!();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final uiRejectedWhileBlocked = uiFinished;
        legalGate.complete();
        final legalSucceeded = await legalSetup;
        final oldUiSucceeded = await oldUiDone;
        final legalFact = await bridge.call('snapshot') as Map;
        final uiCalls = observedCalls.skip(uiCallOffset).toList();
        await recordAdmission({
          'case':
              'older UI identity reply resumes after newer legitimate setup entered',
          'liveCurrentWhileBlocked': legalStillCurrent,
          'oldRejectedBeforeNewRelease': uiRejectedWhileBlocked,
          'newSucceeded': legalSucceeded,
          'oldSucceeded': oldUiSucceeded,
          'newRun': legalRun,
          'after': legalFact,
          'executionEvents': profiles.executionEvents
              .skip(uiEventOffset)
              .toList(),
          'cleanupCalls': uiCalls
              .where((c) => c.method == 'failRunIntent')
              .map((c) => c.arguments)
              .toList(),
        });
        expect(legalStillCurrent, true);
        expect(uiRejectedWhileBlocked, true);
        expect(oldUiSucceeded, false);
        expect(legalSucceeded, true);
        expect(profiles.executionEvents.skip(uiEventOffset), [false]);
        expect(uiCalls.where((c) => c.method == 'failRunIntent'), isEmpty);
        expect(
          (legalFact['state'] as Map)['intentRevision'],
          legalRun['intentRevision'],
        );
        expect((legalFact['state'] as Map)['phase'], 'started');
        expect((legalFact['fact'] as Map)['businessActive'], true);

        final currentOrigin = await native.getRequestState();
        setup.buildGate = Completer<void>();
        setup.buildEntered = Completer<void>();
        final replacedGate = setup.buildGate!;
        final replaced = setup.applyProfile(
          force: true,
          allowBootstrap: true,
          expectedRun: currentOrigin,
        );
        await setup.buildEntered!.future;
        final latest = setup.applyProfile(
          force: true,
          allowBootstrap: true,
          expectedRun: currentOrigin,
        );
        final replacedStillCurrent = await setup.heldCurrent!();
        replacedGate.complete();
        final replacedSucceeded = await replaced;
        final latestSucceeded = await latest;
        final latestFact = await bridge.call('snapshot') as Map;
        await recordAdmission({
          'case':
              'a later legitimate same-run setup still supersedes an older admitted setup',
          'oldCurrent': replacedStillCurrent,
          'oldSucceeded': replacedSucceeded,
          'latestSucceeded': latestSucceeded,
          'after': latestFact,
        });
        expect(replacedStillCurrent, false);
        expect(replacedSucceeded, false);
        expect(latestSucceeded, true);
        expect((latestFact['state'] as Map)['phase'], 'started');
        expect((latestFact['fact'] as Map)['businessActive'], true);
        expect(stderr.toString(), isEmpty);
      } finally {
        await setup.setRunning(false);
        container.dispose();
        messenger.setMockMethodCallHandler(native.methodChannel, null);
        await bridge.close();
        await sourceBridge.close();
        await errors.cancel();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    skip: classpath == null || sourceExecutable == null
        ? 'Run with the compiled JVM classpath and the real Go source-acceptance bridge.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
