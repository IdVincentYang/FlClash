import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

import '../helpers/test_profiles.dart';
import '../helpers/test_policy_drafts.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _Native extends Mock implements Service {}

// checkAndUpdateAndCopy checks the file system before it refreshes, so its
// failure tests need appPath to resolve to a real, writable directory.
class _FakePathProvider extends PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

class _ListenerHandoffFailureSetupAction extends SetupAction {
  final List<bool> coreRunningCalls = [];

  @override
  Future<bool> setCoreRunning(bool running) async {
    coreRunningCalls.add(running);
    if (running) {
      throw StateError('listener handoff failed');
    }
    return true;
  }
}

class _MessageFailureSetupAction extends SetupAction {
  final List<bool> coreRunningCalls = [];

  @override
  Future<bool> setCoreRunning(bool running) async {
    coreRunningCalls.add(running);
    return true;
  }
}

class TestCommonAction extends CommonAction {
  int trafficUpdates = 0;

  @override
  Future<void> updateTraffic() async {
    trafficUpdates++;
  }
}

class TestSetupAction extends SetupAction {
  final List<bool> coreRunningCalls = [];
  final List<Completer<void>> pendingCoreCalls = [];
  bool requestedRunning = false;

  @override
  Future<bool> setRunning(
    bool running, {
    bool initialize = false,
    int? preparedRequestId,
    String source = 'ui',
    bool? paused,
  }) {
    requestedRunning = running;
    return super.setRunning(
      running,
      initialize: initialize,
      preparedRequestId: preparedRequestId,
      source: source,
      paused: paused,
    );
  }

  int trafficResets = 0;
  int applyProfileCalls = 0;
  bool blockCoreCalls = false;
  Error? coreRunningError;
  int authorizeCalls = 0;
  AuthorizeCode authorizeResult = AuthorizeCode.none;

  @override
  Future<AuthorizeCode> authorizeCore() async {
    authorizeCalls++;
    return authorizeResult;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    coreRunningCalls.add(running);
    if (blockCoreCalls) {
      final gate = Completer<void>();
      pendingCoreCalls.add(gate);
      await gate.future;
    }
    final error = coreRunningError;
    if (error != null) {
      throw error;
    }
    return true;
  }

  @override
  void resetCoreTraffic() => trafficResets++;

  @override
  Future<bool> applyProfile({bool silence = false, bool force = false}) async {
    applyProfileCalls++;
    if (requestedRunning &&
        !ref.read(safeModeProvider) &&
        !ref.read(suspendProvider)) {
      return setCoreRunning(true);
    }
    return true;
  }
}

_MockCoreHandlerInterface _newCore() {
  final core = _MockCoreHandlerInterface();
  when(
    () => core.getConfigState(),
  ).thenAnswer((_) async => const ConfigFact(runtimeEpoch: 'fixture'));
  when(() => core.releaseConfigInput(any())).thenAnswer((_) async {});
  return core;
}

ConfigApplyResult _appliedResult([String status = 'installedInactive']) =>
    ConfigApplyResult.fromJson({
      'status': status,
      'message': status == 'blocked' ? 'configuration rejected' : '',
      'fact': {
        'runtimeEpoch': 'fixture',
        'version': 1,
        'owner': 1,
        'token': 1,
        'phase': status == 'blocked' ? 'failed' : 'ready',
        'businessActive': false,
      },
    });

Future<String> _submittedYaml(Object? arguments) async {
  final input = Map<String, Object?>.from(arguments as Map);
  final home = await appPath.homeDirPath;
  final manifest =
      jsonDecode(
            await File(
              '$home/config-inputs/${input['inputId']}.json',
            ).readAsString(),
          )
          as Map;
  return File(
    '$home/config-inputs/${manifest['yamlSha256']}.yaml',
  ).readAsString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('en'));
    registerFallbackValue(const SetupParams(selectedMap: {}, testUrl: ''));
    registerFallbackValue(
      const SharedState(
        stopTip: '',
        startTip: '',
        localNetworkTip: '',
        currentProfileName: '',
        stopText: '',
        onlyStatisticsProxy: false,
      ),
    );
    registerFallbackValue(
      const UpdateParams(
        tun: Tun(),
        mixedPort: 7890,
        allowLan: false,
        findProcessMode: FindProcessMode.off,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        ipv6: false,
        tcpConcurrent: false,
        externalController: ExternalControllerStatus.close,
        unifiedDelay: false,
      ),
    );
  });

  late db.Database testDatabase;
  late TestSetupAction action;
  late ProviderContainer container;

  setUp(() {
    testDatabase = db.Database(NativeDatabase.memory());
    db.database = testDatabase;
    action = TestSetupAction();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        setupActionProvider.overrideWith(() => action),
        commonActionProvider.overrideWith(TestCommonAction.new),
      ],
    );
    container.listen(configProvider, (_, _) {});
    globalState.container = container;
    globalState.needInitStatus = true;
    container.read(setupActionProvider.notifier);
  });

  tearDown(() async {
    action.blockCoreCalls = false;
    action.coreRunningError = null;
    for (final gate in action.pendingCoreCalls) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    await container.read(setupActionProvider.notifier).setRunning(false);
    container.dispose();
    await testDatabase.close();
    globalState.needInitStatus = true;
  });

  void markInitialized() {
    container.read(initProvider.notifier).value = true;
  }

  group('setRunning gating', () {
    test('ignores a start request before initialization completes', () async {
      await container.read(setupActionProvider.notifier).setRunning(true);

      expect(action.coreRunningCalls, isEmpty);
      expect(container.read(runTimeProvider), isNull);
    });

    test('an initialize request bypasses the init gate', () async {
      await container
          .read(setupActionProvider.notifier)
          .setRunning(true, initialize: true);

      expect(action.coreRunningCalls, [true]);
      expect(action.applyProfileCalls, 1);
      expect(globalState.needInitStatus, isFalse);
    });

    test('safe mode runs the profile but never touches the listener', () async {
      final scopedAction = TestSetupAction();
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(() => scopedAction),
          commonActionProvider.overrideWith(TestCommonAction.new),
          safeModeProvider.overrideWithValue(true),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);
      globalState.container = scoped;
      scoped.read(setupActionProvider.notifier);

      await scoped
          .read(setupActionProvider.notifier)
          .setRunning(true, initialize: true);

      expect(scopedAction.coreRunningCalls, isEmpty);
      expect(scopedAction.applyProfileCalls, 1);
      expect(scoped.read(isStartProvider), isFalse);

      await scoped.read(setupActionProvider.notifier).setRunning(false);

      expect(scopedAction.coreRunningCalls, isEmpty);
      expect(scoped.read(isStartProvider), isFalse);
    });

    test('starts the core once initialization is done', () async {
      markInitialized();

      await container.read(setupActionProvider.notifier).setRunning(true);

      expect(action.coreRunningCalls, [true]);
      expect(container.read(runTimeProvider), isNotNull);
    });

    test('a stop request is never gated on initialization', () async {
      await container.read(setupActionProvider.notifier).setRunning(false);

      expect(action.coreRunningCalls, [false]);
    });
  });

  group('run failures', () {
    test('a start the core rejects stops reporting a run time', () async {
      markInitialized();
      action.coreRunningError = StateError('start failed');

      expect(
        await container.read(setupActionProvider.notifier).setRunning(true),
        isFalse,
      );

      expect(container.read(runTimeProvider), isNull);
    });

    test(
      'a stop the core rejects keeps the run time it started with',
      () async {
        markInitialized();
        await container.read(setupActionProvider.notifier).setRunning(true);
        action.coreRunningError = StateError('stop failed');

        await expectLater(
          container.read(setupActionProvider.notifier).setRunning(false),
          throwsStateError,
        );

        expect(container.read(runTimeProvider), isNotNull);
      },
    );
  });

  group('stop cleanup', () {
    test('resets traffic counters', () async {
      markInitialized();
      await container.read(setupActionProvider.notifier).setRunning(true);
      container.read(totalTrafficProvider.notifier).value = const Traffic(
        up: 10,
        down: 20,
      );

      await container.read(setupActionProvider.notifier).setRunning(false);

      expect(action.trafficResets, 1);
      expect(container.read(trafficsProvider).list, isEmpty);
      expect(container.read(totalTrafficProvider), const Traffic());
      expect(container.read(runTimeProvider), isNull);
    });
  });

  group('run time ticker', () {
    late ProviderContainer scoped;

    // Built inside each test, on its fake clock: futures made there never
    // settle in the shared tearDown.
    SetupAction buildScoped() {
      scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(TestSetupAction.new),
          commonActionProvider.overrideWith(TestCommonAction.new),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);
      globalState.container = scoped;
      scoped
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(showTrayTitle: false));
      scoped.read(initProvider.notifier).value = true;
      return scoped.read(setupActionProvider.notifier);
    }

    int trafficUpdates() =>
        (scoped.read(commonActionProvider.notifier) as TestCommonAction)
            .trafficUpdates;

    void setVisible(bool visible) =>
        scoped.read(appVisibleProvider.notifier).value = visible;

    testWidgets('reads traffic only while the app is visible', (tester) async {
      final setup = buildScoped();
      await setup.setRunning(true);
      expect(trafficUpdates(), 1);

      await tester.pump(const Duration(seconds: 2));
      expect(trafficUpdates(), 3);

      setVisible(false);
      await tester.pump(const Duration(seconds: 5));
      expect(trafficUpdates(), 3);
      expect(scoped.read(isStartProvider), isTrue);

      setVisible(true);
      await tester.pump();
      expect(trafficUpdates(), 4);
      await tester.pump(const Duration(seconds: 1));
      expect(trafficUpdates(), 5);

      await setup.setRunning(false);
    });

    testWidgets('a start while hidden waits for the app to be shown', (
      tester,
    ) async {
      final setup = buildScoped();
      setVisible(false);
      await setup.setRunning(true);
      await tester.pump(const Duration(seconds: 3));

      expect(scoped.read(runTimeProvider), isNotNull);
      expect(trafficUpdates(), 0);

      setVisible(true);
      await tester.pump();
      expect(trafficUpdates(), 1);

      await setup.setRunning(false);
    });

    testWidgets('the macOS menu bar title keeps traffic coming while hidden', (
      tester,
    ) async {
      final setup = buildScoped();
      setVisible(false);
      await setup.setRunning(true);
      await tester.pump(const Duration(seconds: 2));
      expect(trafficUpdates(), 0);

      scoped
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(showTrayTitle: true));
      await tester.pump(const Duration(seconds: 2));

      expect(trafficUpdates(), system.isMacOS ? 3 : 0);

      await setup.setRunning(false);
    });
  });

  group('suspend', () {
    test('skips starting the core on an excluded SSID', () async {
      container.dispose();
      action = TestSetupAction();
      container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(() => action),
          commonActionProvider.overrideWith(TestCommonAction.new),
          excludeSSIDsProvider.overrideWithValue(const ['Office Wi-Fi']),
        ],
      );
      globalState.container = container;
      container.read(initProvider.notifier).value = true;
      container.read(currentSSIDProvider.notifier).value = 'Office Wi-Fi';

      await container.read(setupActionProvider.notifier).setRunning(true);

      expect(action.coreRunningCalls, isEmpty);
    });

    test('still stops the core on an excluded SSID', () async {
      container.dispose();
      action = TestSetupAction();
      container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(() => action),
          commonActionProvider.overrideWith(TestCommonAction.new),
          excludeSSIDsProvider.overrideWithValue(const ['Office Wi-Fi']),
        ],
      );
      globalState.container = container;
      container.read(currentSSIDProvider.notifier).value = 'Office Wi-Fi';

      await container.read(setupActionProvider.notifier).setRunning(false);

      expect(action.coreRunningCalls, [false]);
    });
  });

  group('latest-intent arbitration', () {
    test('a superseded stop does not run the post-stop cleanup', () async {
      markInitialized();
      final notifier = container.read(setupActionProvider.notifier);
      action.blockCoreCalls = true;

      final stopping = notifier.setRunning(false);
      await Future<void>.delayed(Duration.zero);
      final starting = notifier.setRunning(true);
      await Future<void>.delayed(Duration.zero);

      action.blockCoreCalls = false;
      for (final gate in action.pendingCoreCalls) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }
      await Future.wait([stopping, starting]);

      expect(action.coreRunningCalls, [false, true]);
      expect(action.trafficResets, 0);
      expect(container.read(runTimeProvider), isNotNull);
    });

    test('the newest request wins the local running state', () async {
      markInitialized();
      final notifier = container.read(setupActionProvider.notifier);

      await notifier.setRunning(true);
      expect(container.read(runTimeProvider), isNotNull);

      await notifier.setRunning(false);
      expect(container.read(runTimeProvider), isNull);

      await notifier.setRunning(true);
      expect(container.read(runTimeProvider), isNotNull);
      expect(action.coreRunningCalls, [true, false, true]);
    });
  });

  group('initStatus', () {
    test('is a no-op once the status has already been initialized', () async {
      globalState.needInitStatus = false;

      await container.read(setupActionProvider.notifier).initStatus();

      expect(action.coreRunningCalls, isEmpty);
      expect(action.applyProfileCalls, 0);
    });

    test('starts the core when autoRun is enabled', () async {
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        autoRun: true,
      );

      await container.read(setupActionProvider.notifier).initStatus();

      expect(action.coreRunningCalls, [true]);
      expect(globalState.needInitStatus, isFalse);
    });

    test('only applies the profile when autoRun is disabled', () async {
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        autoRun: false,
      );

      await container.read(setupActionProvider.notifier).initStatus();

      expect(action.coreRunningCalls, isEmpty);
      expect(action.applyProfileCalls, 1);
    });
  });

  group('requestAdmin', () {
    test('never asks for authorization while tun is disabled', () async {
      expect(await action.requestAdmin(false), isTrue);

      expect(action.authorizeCalls, 0);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.none,
      );
    });

    test('safe mode never asks, whatever the tun setting says', () async {
      final scopedAction = TestSetupAction();
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(() => scopedAction),
          safeModeProvider.overrideWithValue(true),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);
      scoped.read(setupActionProvider.notifier);

      expect(await scopedAction.requestAdmin(true), isTrue);
      expect(scopedAction.authorizeCalls, 0);
      expect(
        scoped.read(authorizedTunEnableProvider),
        TunAuthorizationState.none,
      );
    });

    test('does not ask again once the state left none', () async {
      container.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.authorized;

      expect(await action.requestAdmin(true), isTrue);
      expect(action.authorizeCalls, 0);
    });

    test(
      'a successful authorization hands off instead of continuing',
      () async {
        action.authorizeResult = AuthorizeCode.success;

        expect(await action.requestAdmin(true), isFalse);
        expect(action.authorizeCalls, 1);
        expect(
          container.read(authorizedTunEnableProvider),
          TunAuthorizationState.authorized,
        );
      },
    );

    test('a platform without an authorization step continues inline', () async {
      action.authorizeResult = AuthorizeCode.none;

      expect(await action.requestAdmin(true), isTrue);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.authorized,
      );
    });

    test('a failed authorization continues but stays unauthorized', () async {
      action.authorizeResult = AuthorizeCode.error;

      expect(await action.requestAdmin(true), isTrue);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.unauthorized,
      );
    });
  });

  group('updateConfig', () {
    test('safe mode pushes tun disabled even once authorized', () async {
      final core = _newCore();
      when(() => core.updateConfig(any())).thenAnswer((_) async => '');
      final scopedAction = TestSetupAction();
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(() => scopedAction),
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          safeModeProvider.overrideWithValue(true),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);
      scoped.read(setupActionProvider.notifier);
      await scoped
          .read(applicationInputActionProvider.notifier)
          .updatePatch(
            (state) => state.copyWith(tun: state.tun.copyWith(enable: true)),
          );
      scoped.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.authorized;

      await scopedAction.updateConfig();

      final params =
          verify(() => core.updateConfig(captureAny())).captured.single
              as UpdateParams;
      expect(params.tun.enable, isFalse);
      expect(scopedAction.authorizeCalls, 0);
    });

    test('safe mode closes the external controller', () async {
      final core = _newCore();
      when(() => core.updateConfig(any())).thenAnswer((_) async => '');
      final scopedAction = TestSetupAction();
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(TestProfiles.new),
          setupActionProvider.overrideWith(() => scopedAction),
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          safeModeProvider.overrideWithValue(true),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);
      scoped.read(setupActionProvider.notifier);
      await scoped
          .read(applicationInputActionProvider.notifier)
          .updatePatch(
            (state) => state.copyWith(
              externalController: ExternalControllerStatus.open,
            ),
          );

      await scopedAction.updateConfig();

      final params =
          verify(() => core.updateConfig(captureAny())).captured.single
              as UpdateParams;
      expect(params.externalController, ExternalControllerStatus.close);
      expect(
        scoped.read(patchClashConfigProvider).externalController,
        ExternalControllerStatus.open,
      );
    });
  });

  group('recoverMissingProfile', () {
    ProviderContainer buildScoped(List<Profile> profiles, int? profileId) {
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => TestProfiles(profiles)),
          currentProfileIdProvider.overrideWithBuild((_, _) => profileId),
          setupActionProvider.overrideWith(TestSetupAction.new),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);
      return scoped;
    }

    test(
      'a dangling profile id stays unavailable without an implicit fallback',
      () {
        final profile = Profile.normal(label: 'p').copyWith(id: 1);
        final scoped = buildScoped([profile], 404);

        final recovered = scoped
            .read(setupActionProvider.notifier)
            .recoverMissingProfile();

        expect(recovered, isNull);
        expect(scoped.read(currentProfileIdProvider), 404);
      },
    );

    test('no profiles keeps the stored id untouched', () {
      final scoped = buildScoped(const [], 404);

      expect(
        scoped.read(setupActionProvider.notifier).recoverMissingProfile(),
        isNull,
      );
      expect(scoped.read(currentProfileIdProvider), 404);
    });

    test('an unset id is the first-run state, not a dangling one', () {
      final profile = Profile.normal(label: 'p').copyWith(id: 1);
      final scoped = buildScoped([profile], null);

      expect(
        scoped.read(setupActionProvider.notifier).recoverMissingProfile(),
        isNull,
      );
      expect(scoped.read(currentProfileIdProvider), isNull);
    });
  });

  group('changeMode', () {
    test('records the requested mode', () async {
      await container
          .read(setupActionProvider.notifier)
          .changeMode(Mode.direct);

      expect(container.read(patchClashConfigProvider).mode, Mode.direct);
    });

    test('leaving global alone keeps the selected group', () async {
      final profile = Profile.normal(
        label: 'p',
      ).copyWith(id: 1, currentGroupName: 'Manual');
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          setupActionProvider.overrideWith(TestSetupAction.new),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);

      await scoped.read(setupActionProvider.notifier).changeMode(Mode.rule);

      expect(scoped.read(currentProfileProvider)?.currentGroupName, 'Manual');
    });

    test('global mode also selects the global group', () async {
      final profile = Profile.normal(
        label: 'p',
      ).copyWith(id: 1, currentGroupName: 'Manual');
      final scoped = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          setupActionProvider.overrideWith(TestSetupAction.new),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);

      await scoped.read(setupActionProvider.notifier).changeMode(Mode.global);

      expect(scoped.read(patchClashConfigProvider).mode, Mode.global);
      expect(
        scoped.read(currentProfileProvider)?.currentGroupName,
        GroupName.GLOBAL.name,
      );
    });
  });

  group('applyProfileDebounce', () {
    test('collapses a burst into a single apply', () async {
      final notifier = container.read(setupActionProvider.notifier);

      notifier.applyProfileDebounce(force: true);
      notifier.applyProfileDebounce(force: true);
      notifier.applyProfileDebounce(force: true);
      expect(action.applyProfileCalls, 0);

      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(action.applyProfileCalls, 1);
    });

    test('a stop cancels a pending apply', () async {
      markInitialized();
      final notifier = container.read(setupActionProvider.notifier);

      notifier.applyProfileDebounce(force: true);
      await notifier.setRunning(false);

      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(action.applyProfileCalls, 0);
    });
  });

  group('_setupConfig via the real SetupAction', () {
    late Directory tempDir;
    late String? originalLastConfigMd5;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('setup_action_test');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await AppLocalizations.load(const Locale('en'));
      originalLastConfigMd5 = globalState.lastConfigMd5;
      globalState.packageInfo = PackageInfo(
        appName: 'FlClash',
        packageName: 'com.follow.clash',
        version: '0.0.0',
        buildNumber: '0',
      );
    });

    tearDownAll(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    tearDown(() {
      globalState.lastConfigMd5 = originalLastConfigMd5;
    });

    // profileId: null routes getProfile/setupState around the database and
    // Core.getConfig, isolating the behavior under test.
    const nullProfileSetupState = SetupState(
      profileId: null,
      profileLastUpdateDate: null,
      overwriteType: OverwriteType.standard,
      rules: [],
      proxyGroups: [],
      addedRules: [],
      script: null,
      overrideDns: false,
      dns: Dns(),
      dnsOverrideKeys: {},
    );

    for (final supersede in [false, true]) {
      test(
        'managed stale input recaptures once; newer setup: $supersede',
        () async {
          final profile = draftTestProfile(71);
          await testDatabase.profilesDao.putAll([profile.toCompanion()]);
          final selection = ProfilePolicySelection(
            profileId: profile.id,
            rawContent: selectPolicyDraft(completePolicyDraft()),
          );
          final native = _Native();
          when(native.getRequestState).thenAnswer(
            (_) async => {
              'phase': 'stopped',
              'intentRevision': 1,
              'intentRunning': false,
              'processEpoch': 'fixture',
              'configToken': 0,
              'paused': false,
            },
          );
          when(() => native.syncState(any())).thenAnswer((_) async => '');
          final core = _newCore();
          when(() => core.getConfig(any())).thenAnswer((_) async => {});
          when(
            core.getProxies,
          ).thenAnswer((_) async => const ProxiesData(all: [], proxies: {}));
          when(core.getExternalProviders).thenAnswer((_) async => []);
          final entered = Completer<void>();
          final release = Completer<void>();
          var calls = 0;
          when(() => core.applyConfigInput(any())).thenAnswer((_) async {
            calls++;
            if (supersede && calls == 1) {
              entered.complete();
              await release.future;
            }
            return _appliedResult(
              supersede && calls > 1 ? 'installedInactive' : 'staleInput',
            );
          });
          when(
            () => core.failConfigBuild(any()),
          ).thenAnswer((_) async => _appliedResult('blocked'));
          final scoped = ProviderContainer(
            overrides: [
              profilesProvider.overrideWith(() => TestProfiles([profile])),
              currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
              setupStateProvider.overrideWith(
                (_, id) => nullProfileSetupState.copyWith(
                  profileId: id,
                  policySelection: selection,
                ),
              ),
              coreHandlerProvider.overrideWithValue(
                CoreController.scoped(core),
              ),
              setupActionProvider.overrideWith(
                () => SetupAction.scoped(
                  isAndroid: true,
                  native: native,
                  requests: Request(),
                ),
              ),
            ],
          );
          scoped.listen(configProvider, (_, _) {});
          addTearDown(scoped.dispose);
          final action = scoped.read(setupActionProvider.notifier);
          final first = action.applyProfile(force: true);
          Future<bool>? newer;
          if (supersede) {
            await entered.future;
            newer = action.applyProfile(force: true);
            release.complete();
          }
          expect(await first, isFalse);
          if (newer != null) expect(await newer, isTrue);
          expect(calls, 2);
          if (supersede) {
            verifyNever(() => core.failConfigBuild(any()));
          } else {
            verify(() => core.failConfigBuild(any())).called(1);
          }
        },
      );
    }

    test(
      'a refresh failure can still apply the verified cached profile',
      () async {
        final profile = Profile.normal(label: 'p', url: 'http://127.0.0.1:9/');
        await testDatabase.profilesDao.putAll([profile.toCompanion()]);
        final core = _newCore();
        when(
          () => core.applyConfigInput(any()),
        ).thenAnswer((_) async => _appliedResult());
        when(() => core.getConfig(any())).thenAnswer(
          (_) async => {
            'mode': 'rule',
            'rules': ['MATCH,DIRECT'],
          },
        );
        final scoped = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            setupStateProvider.overrideWith(
              (_, id) => nullProfileSetupState.copyWith(profileId: id),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(SetupAction.new),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);

        final succeeded = await scoped
            .read(setupActionProvider.notifier)
            .applyProfile(force: true);
        expect(succeeded, isTrue);
        verify(() => core.applyConfigInput(any())).called(1);
      },
    );

    test(
      'a build failure retains the existing input and never sends empty YAML',
      () async {
        final profile = Profile.normal(label: 'p');
        await testDatabase.profilesDao.putAll([profile.toCompanion()]);
        final core = _newCore();
        when(() => core.getConfig(any())).thenThrow(Exception('broken yaml'));
        String? pushedConfig;
        when(() => core.applyConfigInput(any())).thenAnswer((call) async {
          pushedConfig = await _submittedYaml(call.positionalArguments.single);
          return _appliedResult();
        });
        final scoped = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            setupStateProvider.overrideWith(
              (_, profileId) =>
                  nullProfileSetupState.copyWith(profileId: profileId),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(SetupAction.new),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);

        final succeeded = await scoped
            .read(setupActionProvider.notifier)
            .applyProfile(force: true);

        expect(succeeded, isFalse);
        expect(pushedConfig, isNull);
        verifyNever(() => core.applyConfigInput(any()));
        expect(scoped.read(currentProfileIdProvider), profile.id);
      },
    );

    test(
      'a config write failure reports setup as failed without calling core',
      () async {
        final home = await appPath.homeDirPath;
        final blockedInputs = File('$home/config-inputs');
        final existingInputs = Directory(blockedInputs.path);
        if (await existingInputs.exists()) {
          await existingInputs.delete(recursive: true);
        }
        await blockedInputs.writeAsString('blocked');
        final profile = Profile.normal(label: 'write failure');
        await testDatabase.profilesDao.putAll([profile.toCompanion()]);
        final core = _newCore();
        when(() => core.getConfig(any())).thenAnswer((_) async => {});
        when(
          () => core.applyConfigInput(any()),
        ).thenAnswer((_) async => _appliedResult());
        final scoped = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWithValue(profile),
            setupStateProvider.overrideWith(
              (_, id) => nullProfileSetupState.copyWith(profileId: id),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(SetupAction.new),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);

        try {
          final succeeded = await scoped
              .read(setupActionProvider.notifier)
              .applyProfile(force: true);

          expect(succeeded, isFalse);
          verifyNever(() => core.applyConfigInput(any()));
        } finally {
          await blockedInputs.delete();
        }
      },
    );

    test(
      'safe mode writes a closed external controller into the profile',
      () async {
        final profile = Profile.normal(label: 'p');
        await testDatabase.profilesDao.putAll([profile.toCompanion()]);
        final core = _newCore();
        when(() => core.getConfig(any())).thenAnswer((_) async => {});
        String? pushedConfig;
        when(() => core.applyConfigInput(any())).thenAnswer((call) async {
          pushedConfig = await _submittedYaml(call.positionalArguments.single);
          return _appliedResult();
        });
        final scoped = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            setupStateProvider.overrideWith(
              (_, profileId) =>
                  nullProfileSetupState.copyWith(profileId: profileId),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(SetupAction.new),
            safeModeProvider.overrideWithValue(true),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);
        await scoped
            .read(applicationInputActionProvider.notifier)
            .updatePatch(
              (state) => state.copyWith(
                externalController: ExternalControllerStatus.open,
              ),
            );

        final succeeded = await scoped
            .read(setupActionProvider.notifier)
            .applyProfile(force: true);

        expect(succeeded, isTrue);
        expect(pushedConfig, contains('external-controller: ""'));
        expect(pushedConfig, isNot(contains('9090')));
      },
    );

    test('a custom overwrite injects only the providers it names', () async {
      final profile = Profile.normal(label: 'p');
      await testDatabase.profilesDao.putAll([profile.toCompanion()]);
      final core = _newCore();
      when(() => core.getConfig(any())).thenAnswer(
        (_) async => {
          'proxy-providers': {
            'bundled': {'type': 'http', 'url': 'https://example.com/b.yaml'},
          },
        },
      );
      const appProxy = ClashProvider(
        id: 11,
        kind: ProviderKind.proxy,
        label: 'appProxies',
        url: 'https://example.com/p.yaml',
      );
      const appRule = ClashProvider(
        id: 12,
        kind: ProviderKind.rule,
        label: 'appRules',
        url: 'https://example.com/r.yaml',
        behavior: RuleProviderBehavior.domain,
        format: RuleProviderFormat.mrs,
      );
      const unusedProxy = ClashProvider(
        id: 13,
        kind: ProviderKind.proxy,
        label: 'unused',
        url: 'https://example.com/u.yaml',
      );
      const localRule = ClashProvider(
        id: 14,
        kind: ProviderKind.rule,
        label: 'localRules',
        behavior: RuleProviderBehavior.classical,
        format: RuleProviderFormat.yaml,
      );
      final setupState = nullProfileSetupState.copyWith(
        profileId: profile.id,
        overwriteType: OverwriteType.custom,
        proxyGroups: [
          const ProxyGroup(
            id: 1,
            name: 'g',
            type: GroupType.Selector,
            use: ['appProxies', 'sub'],
          ),
        ],
        rules: [
          Rule.parse('RULE-SET,appRules,DIRECT', id: 2),
          Rule.parse('RULE-SET,localRules,DIRECT', id: 3),
        ],
        clashProviders: const [appProxy, appRule, unusedProxy, localRule],
        profileProviders: const {'sub': 42},
      );
      final scoped = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          setupActionProvider.overrideWith(SetupAction.new),
        ],
      );
      scoped.listen(configProvider, (_, _) {});
      addTearDown(scoped.dispose);

      final res = await scoped
          .read(setupActionProvider.notifier)
          .getProfile(
            setupState: setupState,
            patchConfig: const PatchClashConfig(),
          );
      final config = loadYaml(res.yaml) as YamlMap;
      final proxyProviders = config['proxy-providers'] as YamlMap;

      expect(
        proxyProviders['appProxies']['path'],
        await appPath.getProviderCachePath(
          ProviderKind.proxy,
          appProxy.fileName,
        ),
      );
      expect(proxyProviders['sub']['type'], 'file');
      expect(proxyProviders['sub']['path'], await appPath.getProfilePath('42'));
      expect(proxyProviders.containsKey('unused'), isFalse);
      expect(
        proxyProviders['bundled']['path'],
        startsWith(
          await appPath.getProviderDirPath(
            profile.id,
            proxiesProviderDirectoryName,
          ),
        ),
      );
      expect(config['rule-providers']['appRules']['behavior'], 'domain');
      expect(config['rule-providers']['appRules']['format'], 'mrs');
      expect(
        config['rule-providers']['appRules']['path'],
        await appPath.getProviderCachePath(ProviderKind.rule, appRule.fileName),
      );
      final local = config['rule-providers']['localRules'] as YamlMap;
      expect(local['type'], 'file');
      expect(local.containsKey('url'), isFalse);
      expect(
        local['path'],
        await appPath.getProviderCachePath(
          ProviderKind.rule,
          localRule.fileName,
        ),
      );
    });

    test(
      'a missing selected profile is rejected before a Core apply',
      () async {
        final core = _newCore();
        when(
          () => core.applyConfigInput(any()),
        ).thenThrow(StateError('rejected'));
        final scoped = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWithValue(null),
            setupStateProvider.overrideWith(
              (_, id) => nullProfileSetupState.copyWith(profileId: id),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(SetupAction.new),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);

        final succeeded = await scoped
            .read(setupActionProvider.notifier)
            .applyProfile(force: true);

        expect(succeeded, isFalse);
        verifyNever(() => core.applyConfigInput(any()));
      },
    );

    test(
      'a blocked activation during initialize never publishes running',
      () async {
        final profile = Profile.normal(label: 'p');
        await testDatabase.profilesDao.putAll([profile.toCompanion()]);
        final core = _newCore();
        when(() => core.getConfig(any())).thenAnswer(
          (_) async => {
            'rules': ['MATCH,DIRECT'],
          },
        );
        when(
          () => core.applyConfigInput(any()),
        ).thenAnswer((_) async => _appliedResult('blocked'));
        final scoped = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            setupStateProvider.overrideWith(
              (_, id) => nullProfileSetupState.copyWith(profileId: id),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(
              _ListenerHandoffFailureSetupAction.new,
            ),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);
        final handoffAction =
            scoped.read(setupActionProvider.notifier)
                as _ListenerHandoffFailureSetupAction;

        await handoffAction.setRunning(true, initialize: true);

        expect(handoffAction.coreRunningCalls, isEmpty);
        expect(scoped.read(runTimeProvider), isNull);
        verify(() => core.applyConfigInput(any())).called(1);
      },
    );

    test(
      'a rejected activation during initialize leaves runtime stopped',
      () async {
        final profile = Profile.normal(label: 'p');
        await testDatabase.profilesDao.putAll([profile.toCompanion()]);
        final core = _newCore();
        when(() => core.getConfig(any())).thenAnswer(
          (_) async => {
            'rules': ['MATCH,DIRECT'],
          },
        );
        when(
          () => core.applyConfigInput(any()),
        ).thenAnswer((_) async => _appliedResult('blocked'));
        final scoped = ProviderContainer(
          overrides: [
            profilesProvider.overrideWith(() => TestProfiles([profile])),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            setupStateProvider.overrideWith(
              (_, id) => nullProfileSetupState.copyWith(profileId: id),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(_MessageFailureSetupAction.new),
          ],
        );
        scoped.listen(configProvider, (_, _) {});
        addTearDown(scoped.dispose);
        final messageAction =
            scoped.read(setupActionProvider.notifier)
                as _MessageFailureSetupAction;

        await messageAction.setRunning(true, initialize: true);

        expect(messageAction.coreRunningCalls, isEmpty);
        expect(scoped.read(runTimeProvider), isNull);
        verify(() => core.applyConfigInput(any())).called(1);
      },
    );
  });
}
