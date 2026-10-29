import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/config_input.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/profile_refresh.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/policy_core_bridge.dart';
import '../helpers/test_profiles.dart';

class _Native extends Mock implements Service {}

class _Shared extends Fake implements SharedState {}

class _StoredProfiles extends TestProfiles {
  _StoredProfiles(this.requests);
  final Request requests;
  @override
  Future<Profile> persist(
    Profile profile, {
    Iterable<int> renameIn = const [],
    bool networkResult = false,
  }) async {
    // Replace the global edit owner with the scoped Request in this fixture.
    if (!networkResult) await requests.invalidate('profile:${profile.id}');
    return super.persist(
      profile,
      renameIn: renameIn,
      networkResult: networkResult,
    );
  }

  int? failProfile;
  bool failPublication = false;
  Completer<void>? commitEntered, commitGate;
  @override
  Future<Profile> persistRefresh(
    Profile profile, {
    required bool importing,
  }) async {
    final gate = commitGate;
    commitGate = null;
    if (gate != null) {
      commitEntered?.complete();
      await gate.future;
    }
    if (profile.id == failProfile) throw StateError('synthetic DB failure');
    return super.persistRefresh(profile, importing: importing);
  }

  @override
  Future<void> publishRefresh() {
    if (failPublication) throw StateError('synthetic publication failure');
    return super.publishRefresh();
  }
}

class _Profiles extends ProfilesAction {
  _Profiles(this.client);
  final Request client;
  Completer<void>? materialDemandEntered;
  @override
  Request get requestClient => client;
  @override
  Future<Profile?> ensureFile(
    Profile profile, {
    Future<bool> Function()? isCurrent,
  }) {
    final entered = materialDemandEntered;
    if (profile.id == 1 && entered != null && !entered.isCompleted) {
      entered.complete();
    }
    return super.ensureFile(profile, isCurrent: isCurrent);
  }
}

class _BridgeCore extends CoreHandlerInterface {
  _BridgeCore(this.bridge);
  final PolicyCoreBridge bridge;
  final calls = <CoreMethod>[];
  Completer<void>? registerEntered, registerGate;
  Completer<void>? failureEntered, failureGate;
  Completer<void>? projectionEntered, projectionGate;
  Completer<void>? readEntered, readGate;
  String? nativeAfterActivation;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<T?> invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async {
    calls.add(method);
    if (method == CoreMethod.getConfig && readGate != null) {
      final gate = readGate!;
      readGate = null;
      readEntered?.complete();
      await gate.future;
    }

    if (method == CoreMethod.failConfigBuild && failureGate != null) {
      final gate = failureGate!;
      failureGate = null;
      failureEntered?.complete();
      await gate.future;
    }
    if (method == CoreMethod.registerConfigInput && registerGate != null) {
      registerEntered?.complete();
      await registerGate!.future;
      registerGate = null;
    }
    if (method == CoreMethod.getTraffic ||
        method == CoreMethod.getTotalTraffic) {
      return {'up': 0, 'down': 0} as T;
    }
    final operation = switch (method) {
      CoreMethod.getConfigState => 'fact',
      CoreMethod.registerConfigInput => 'register',
      CoreMethod.prepareConfig => 'prepare',
      CoreMethod.installConfig => 'install',
      CoreMethod.activateConfig => 'activate',
      CoreMethod.failConfigBuild => 'fail',
      CoreMethod.validateConfig => 'refreshValidate',
      CoreMethod.getConfig => 'refreshRead',
      CoreMethod.releaseConfigInput => 'refreshRelease',
      CoreMethod.getProxies => 'refreshGroups',
      CoreMethod.getExternalProviders => 'refreshProviders',
      _ => throw UnsupportedError(method.name),
    };
    final response = await bridge.call(operation, arguments);
    if (method == CoreMethod.activateConfig &&
        response['status'] == 'activated' &&
        nativeAfterActivation != null) {
      final native = await bridge.call('nativeState');
      native['revision'] = (native['revision'] as num).toInt() + 1;
      if (nativeAfterActivation == 'stop') {
        native['intentRevision'] =
            (native['intentRevision'] as num).toInt() + 1;
        native['intentRunning'] = false;
        native['phase'] = 'stopped';
        native['reason'] = 'userStop';
      }
      await bridge.call('control', {'action': 'publish', 'state': native});
    }
    if (method == CoreMethod.getProxies && projectionGate != null) {
      final gate = projectionGate!;
      projectionGate = null;
      projectionEntered?.complete();
      await gate.future;
    }
    if (response['error'] != null) {
      throw StateError('Synthetic Core request failed');
    }
    return (response.containsKey('value') ? response['value'] : response) as T?;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final executable = Platform.environment['FLCLASH_APPLICATION_INPUT_BRIDGE'];
  late Directory root;
  late Database store;
  late HttpServer server;
  late PolicyCoreBridge bridge;
  late _BridgeCore core;
  late Request client;
  late ProviderContainer container;
  var containerDisposed = false;
  late ProfilesAction profiles;
  late SetupAction setup;
  late _Native native;
  final received = <String>[];
  final holds = <String, Completer<void>>{};
  final responses = <String, String>{};
  final controls = <Map<String, Object?>>[];
  String? ackFault;
  const yaml =
      'mixed-port: 0\nmode: rule\ndns: {enable: false, nameserver: ["127.0.0.1:1"]}\nrules: ["MATCH,DIRECT"]\n';

  setUpAll(() async {
    registerFallbackValue(_Shared());
    feature = const Feature(customProviders: true);
    root = await Directory.systemTemp.createTemp('refresh-core-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
    );
  });
  tearDownAll(() {
    feature = const Feature();
    return root.delete(recursive: true);
  });
  setUp(() async {
    containerDisposed = false;
    SharedPreferences.setMockInitialValues({});
    received.clear();
    holds.clear();
    responses.clear();
    controls.clear();
    ackFault = null;
    bridge = PolicyCoreBridge(
      await Process.start(
        executable!,
        [r'-test.run=^TestApplicationInputBridge$'],
        workingDirectory: Directory('core').absolute.path,
        environment: {'FLCLASH_APPLICATION_INPUT_BRIDGE_HOME': root.path},
      ),
    );
    await bridge.call('refreshState');
    core = _BridgeCore(bridge);
    store = Database(NativeDatabase.memory());
    database = store;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.path;
      received.add(name);
      try {
        if (holds[name] case final gate?) await gate.future;
        request.response.headers.noFolding('subscription-userinfo');
        request.response.headers.add(
          'subscription-userinfo',
          'upload=bad; broken;',
        );
        request.response.headers.add(
          'subscription-userinfo',
          'upload=10; download=20; expire=999999999999999999999',
        );
        request.response.write(responses[name] ?? yaml);
        await request.response.close();
      } catch (_) {}
    });
    native = _Native();
    when(() => native.requestControl(any())).thenAnswer((call) async {
      final command = Map<String, Object?>.from(
        call.positionalArguments.first as Map,
      );
      controls.add(command);
      if (command['action'] == 'complete' && ackFault == 'before') {
        throw StateError('synthetic ack failure');
      }
      final result = await bridge.call('control', command);
      if (command['action'] == 'complete' && ackFault == 'after') {
        throw StateError('synthetic ack loss');
      }
      return result;
    });
    when(native.getRequestState).thenAnswer((_) => bridge.call('nativeState'));
    when(native.getRunTime).thenAnswer((_) async => DateTime(2026));
    when(() => native.syncState(any())).thenAnswer((_) async => '');
    client = Request.scoped(native: native, isAndroid: true);
    container = ProviderContainer(
      overrides: [
        profilesActionProvider.overrideWith(() => _Profiles(client)),
        setupActionProvider.overrideWith(
          () => SetupAction.scoped(
            isAndroid: true,
            native: native,
            requests: client,
          ),
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesProvider.overrideWith(() => _StoredProfiles(client)),
        nativeRequestStateProvider.overrideWith(
          () => NativeRequestState.scoped(native),
        ),
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(testUrl: 'http://127.0.0.1/'),
        ),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => const PatchClashConfig(
            mixedPort: 0,
            tun: Tun(enable: false),
            dns: Dns(enable: false, nameserver: ['127.0.0.1:1']),
          ),
        ),
      ],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    client.attach(container);
    await client.ready();
    profiles = container.read(profilesActionProvider.notifier);
    setup = container.read(setupActionProvider.notifier);
  });
  tearDown(() async {
    for (final gate in holds.values) {
      if (!gate.isCompleted) gate.complete();
    }
    if (!containerDisposed) container.dispose();
    await client.detach();
    await server.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await bridge.close();
    await store.close();
    await for (final entry in root.list()) {
      await entry.delete(recursive: true);
    }
  });
  Profile profile(int id, {OverwriteType type = OverwriteType.standard}) =>
      Profile(
        id: id,
        label: 'P$id',
        url: 'http://127.0.0.1:${server.port}/$id',
        requestMode: RequestMode.direct,
        autoUpdate: false,
        autoUpdateDuration: const Duration(days: 1),
        overwriteType: type,
      );
  Future<void> put(List<Profile> entries, {bool files = true}) async {
    await store.profilesDao.putAll(entries.map((p) => p.toCompanion()));
    (container.read(profilesProvider.notifier) as TestProfiles).replace(
      entries,
    );
    if (files) {
      for (final entry in entries) {
        final file = File(await appPath.getProfilePath('${entry.id}'));
        await file.parent.create(recursive: true);
        await file.writeAsString(yaml);
      }
    }
  }

  test(
    'real refresh changes its own Core Owner and completes MD5, groups and providers',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final before = await core.getConfigState();
      final groupCalls = core.calls
          .where((m) => m == CoreMethod.getProxies)
          .length;
      globalState.lastConfigMd5 = 'before-refresh';
      responses['/1'] = '$yaml# refreshed\n';
      final result = await profiles.updateProfile(a);
      final after = await core.getConfigState();
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.installedInactive);
      expect(after.owner, isNot(before.owner));
      expect(after.businessActive, false);
      expect(globalState.lastConfigMd5, isNot('before-refresh'));
      expect(
        core.calls.where((m) => m == CoreMethod.getProxies).length,
        greaterThan(groupCalls),
      );
      expect(
        core.calls.where((m) => m == CoreMethod.getExternalProviders).length,
        greaterThanOrEqualTo(2),
      );
      expect(received, ['/1']);
      expect(
        (await store.profilesDao.query().get()).single.subscriptionInfo,
        const SubscriptionInfo(upload: 10, download: 20),
      );
    },
    skip: executable == null,
  );

  test(
    'activated refresh permits its own Owner transition while preserving the run intent',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      final before = await core.getConfigState();
      expect(before.businessActive, true);
      globalState.lastConfigMd5 = 'before-active-refresh';
      core.nativeAfterActivation = 'phase';
      final result = await profiles.updateProfile(a);
      expect(result.application, ProfileApplicationOutcome.activated);
      final after = await core.getConfigState();
      expect(after.businessActive, true);
      expect(after.owner, isNot(before.owner));
      expect(globalState.lastConfigMd5, isNot('before-active-refresh'));
      expect((await bridge.call('nativeState'))['intentRevision'], 2);
      expect((await bridge.call('nativeState'))['revision'], 3);
    },
    skip: executable == null,
  );

  test(
    'a stop after activation supersedes completion projections without restoring the run intent',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      final groups = core.calls.where((m) => m == CoreMethod.getProxies).length;
      core.nativeAfterActivation = 'stop';
      globalState.lastConfigMd5 = 'stop-owned-md5';
      final result = await profiles.updateProfile(a);
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.superseded);
      expect((await core.getConfigState()).businessActive, false);
      expect((await bridge.call('nativeState'))['intentRunning'], false);
      expect(globalState.lastConfigMd5, 'stop-owned-md5');
      expect(
        core.calls.where((m) => m == CoreMethod.getProxies).length,
        groups,
      );
    },
    skip: executable == null,
  );

  for (final type in [OverwriteType.standard, OverwriteType.script]) {
    test(
      'dormant $type provider reference causes no apply or Owner transition',
      () async {
        final a = profile(1, type: type), b = profile(2);
        await put([a, b]);
        await store.batch(
          (batch) => batch.insertAll(store.proxyGroups, [
            const ProxyGroup(
              profileId: 1,
              name: 'dormant',
              id: 1,
              type: GroupType.Selector,
              use: ['P2'],
            ).toCompanion(),
          ]),
        );
        expect(await setup.applyProfile(force: true), true);
        final before = await core.getConfigState();
        final applies = core.calls
            .where((m) => m == CoreMethod.registerConfigInput)
            .length;
        final result = await profiles.updateProfile(b);
        expect(result.application, ProfileApplicationOutcome.notRequired);
        expect((await core.getConfigState()).owner, before.owner);
        expect(
          core.calls.where((m) => m == CoreMethod.registerConfigInput).length,
          applies,
        );
      },
      skip: executable == null,
    );
  }

  test('a real registered provider refresh reapplies the current input', () async {
    final a = profile(1, type: OverwriteType.custom), b = profile(2);
    await put([a, b]);
    await store.batch(
      (batch) => batch.insertAll(store.proxyGroups, [
        const ProxyGroup(
          profileId: 1,
          name: 'local',
          id: 1,
          type: GroupType.Selector,
          use: ['P2'],
        ).toCompanion(),
      ]),
    );
    final provider = File(await appPath.getProfilePath('2'));
    await provider.writeAsString(
      'proxies:\n  - {name: local-node, type: socks5, server: 127.0.0.1, port: 1}\n',
    );
    responses['/2'] =
        'proxies:\n  - {name: local-node, type: socks5, server: 127.0.0.1, port: 2}\n';
    expect(await setup.applyProfile(force: true), true);
    final before = await core.getConfigState();
    expect(
      await ConfigInput.acceptedDependencies(
        home: root.path,
        accepted: before,
        readFact: core.getConfigState,
      ),
      contains('profile:2'),
    );
    final result = await profiles.updateProfile(b);
    expect(result.materialSaved, true);
    expect(result.application, ProfileApplicationOutcome.installedInactive);
    expect((await core.getConfigState()).owner, isNot(before.owner));
  }, skip: executable == null);

  for (final failure in [false, true]) {
    test(
      'cross-ID Setup material demand progresses after provider ${failure ? 'DB failure' : 'save'}',
      () async {
        final a = profile(1, type: OverwriteType.custom), b = profile(2);
        await put([a, b]);
        await store.batch(
          (batch) => batch.insertAll(store.proxyGroups, [
            const ProxyGroup(
              id: 1,
              profileId: 1,
              name: 'local',
              type: GroupType.Selector,
              use: ['P2'],
            ).toCompanion(),
          ]),
        );
        const providerBody =
            'proxies:\n  - {name: local-node, type: socks5, server: 127.0.0.1, port: 1}\n';
        final provider = File(await appPath.getProfilePath('2'));
        await provider.writeAsString(providerBody);
        responses['/2'] = providerBody;
        expect(await setup.applyProfile(force: true), true);
        await bridge.call('refreshRunning');
        expect(
          await setup.setRunning(true, initialize: true, preparedRequestId: 2),
          true,
        );
        await File(await appPath.getProfilePath('1')).delete();
        final release = holds['/2'] = Completer<void>();
        if (failure) {
          (container.read(profilesProvider.notifier) as _StoredProfiles)
                  .failProfile =
              2;
        }
        final refresh = profiles.updateProfile(b);
        final checked = failure
            ? expectLater(refresh, throwsA(isA<RequestUnavailable>()))
            : refresh.then((result) => expect(result.materialSaved, true));
        for (var i = 0; !received.contains('/2') && i < 1000; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(received, ['/2']);
        final entered = (profiles as _Profiles).materialDemandEntered =
            Completer<void>();
        final oldSetup = setup.applyProfile(force: true);
        await entered.future.timeout(const Duration(seconds: 3));
        expect(received, ['/2']);
        release.complete();
        await checked.timeout(const Duration(seconds: 10));
        await oldSetup.timeout(const Duration(seconds: 10));
        if (failure) {
          expect(await provider.readAsString(), providerBody);
          expect(received.where((name) => name == '/2').length, 1);
        } else {
          expect(
            await setup
                .applyProfile(force: true)
                .timeout(const Duration(seconds: 10)),
            true,
          );
          expect(received, contains('/1'));
        }
      },
      skip: executable == null,
    );
  }

  test(
    'missing current material resumes its original Setup and applies exactly once',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      await File(await appPath.getProfilePath('1')).delete();
      core.calls.clear();
      globalState.lastConfigMd5 = 'before-material-repair';
      core.readEntered = Completer<void>();
      final release = core.readGate = Completer<void>();
      final original = setup.applyProfile(force: true);
      await core.readEntered!.future.timeout(const Duration(seconds: 3));
      await pumpEventQueue();
      release.complete();
      expect(await original.timeout(const Duration(seconds: 3)), true);
      expect(
        core.calls.where((call) => call == CoreMethod.registerConfigInput),
        hasLength(1),
      );
      expect(
        core.calls.where((call) => call == CoreMethod.installConfig),
        hasLength(1),
      );
      expect(received, ['/1']);
      expect(globalState.lastConfigMd5, isNot('before-material-repair'));
      expect(
        core.calls,
        containsAll([CoreMethod.getProxies, CoreMethod.getExternalProviders]),
      );
    },
    skip: executable == null,
  );

  test(
    'a newer Setup releases expired material demand before an unrelated download finishes',
    () async {
      final a = profile(1), b = profile(2);
      await put([a, b]);
      expect(await setup.applyProfile(force: true), true);
      final file = File(await appPath.getProfilePath('1'));
      await file.delete();
      final release = holds['/2'] = Completer<void>();
      final refresh = profiles
          .updateProfile(b)
          .then<Object>((value) => value, onError: (Object error) => error);
      for (var i = 0; !received.contains('/2') && i < 1000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(received, ['/2']);
      final inspected = controls
          .where(
            (call) => call['action'] == 'inspect' && call['key'] == 'profile:1',
          )
          .length;
      final entered = (profiles as _Profiles).materialDemandEntered =
          Completer<void>();
      final oldSetup = setup.applyProfile(force: true);
      await entered.future.timeout(const Duration(seconds: 3));
      for (
        var i = 0;
        controls
                    .where(
                      (call) =>
                          call['action'] == 'inspect' &&
                          call['key'] == 'profile:1',
                    )
                    .length ==
                inspected &&
            i < 1000;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await file.writeAsString(yaml);
      final newerSetup = setup.applyProfile(force: true);
      await Future.wait([
        oldSetup,
        newerSetup,
      ]).timeout(const Duration(seconds: 3));
      expect(release.isCompleted, false);
      expect(received, ['/2']);
      release.complete();
      await refresh.timeout(const Duration(seconds: 10));
    },
    skip: executable == null,
  );

  test(
    'disposal during a finite save reports durable material and superseded application',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final storeProfiles =
          container.read(profilesProvider.notifier) as _StoredProfiles;
      final release = storeProfiles.commitGate = Completer<void>();
      storeProfiles.commitEntered = Completer<void>();
      responses['/1'] = '$yaml# refreshed\n';
      final refresh = profiles.updateProfile(a);
      await storeProfiles.commitEntered!.future.timeout(
        const Duration(seconds: 3),
      );
      container.dispose();
      containerDisposed = true;
      release.complete();
      final result = await refresh.timeout(const Duration(seconds: 3));
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.superseded);
      expect(
        (await store.profilesDao.query().get()).single.lastUpdateDate,
        isNotNull,
      );
      expect(
        await File(await appPath.getProfilePath('1')).readAsString(),
        responses['/1'],
      );
    },
    skip: executable == null,
  );

  test(
    'auto=false manual successor survives while the previous saved result is applying',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final gate = core.registerGate = Completer<void>();
      core.registerEntered = Completer<void>();
      final first = profiles.updateProfile(a);
      await core.registerEntered!.future;
      final next = a.copyWith(url: 'http://127.0.0.1:${server.port}/new');
      late RequestSource expected;
      await profiles.putProfile(
        next,
        onSourceSaved: (source) => expected = source,
      );
      final second = profiles.updateProfile(
        next,
        sourceMustMatch: true,
        expectedSource: expected,
      );
      gate.complete();
      expect((await first).materialSaved, true);
      final result = await second;
      expect(result.materialSaved, true);
      expect(received, ['/1', '/new']);
      expect((await store.profilesDao.query().get()).single.url, next.url);
    },
    skip: executable == null,
  );

  test(
    'a manual request during a finite automatic commit captures the committed source and runs independently',
    () async {
      final a = profile(1).copyWith(autoUpdate: true);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final storeProfiles =
          container.read(profilesProvider.notifier) as _StoredProfiles;
      final release = storeProfiles.commitGate = Completer<void>();
      storeProfiles.commitEntered = Completer<void>();
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      unawaited(profiles.autoUpdateProfiles());
      await storeProfiles.commitEntered!.future.timeout(
        const Duration(seconds: 3),
      );
      expect(received, ['/1']);
      final manual = profiles.updateProfile(a);
      release.complete();
      final result = await manual.timeout(const Duration(seconds: 10));
      expect(result.materialSaved, true);
      expect(received, ['/1', '/1']);
      expect(result.application, ProfileApplicationOutcome.activated);
    },
    skip: executable == null,
  );

  test(
    'the latest manual successor supersedes the earlier waiter while a saved result is applying',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final gate = core.registerGate = Completer<void>();
      core.registerEntered = Completer<void>();
      final first = profiles.updateProfile(a);
      await core.registerEntered!.future;
      final next = a.copyWith(url: 'http://127.0.0.1:${server.port}/new');
      late RequestSource expected;
      await profiles.putProfile(
        next,
        onSourceSaved: (source) => expected = source,
      );
      final second = profiles.updateProfile(
        next,
        sourceMustMatch: true,
        expectedSource: expected,
      );
      final newest = next.copyWith(
        url: 'http://127.0.0.1:${server.port}/newest',
      );
      late RequestSource latestSource;
      await profiles.putProfile(
        newest,
        onSourceSaved: (source) => latestSource = source,
      );
      final third = profiles.updateProfile(
        newest,
        sourceMustMatch: true,
        expectedSource: latestSource,
      );
      gate.complete();
      expect((await first).materialSaved, true);
      final stale = await second;
      expect(stale.materialSaved, false);
      expect(stale.application, ProfileApplicationOutcome.superseded);
      expect((await third).materialSaved, true);
      expect(received, ['/1', '/newest']);
      expect((await store.profilesDao.query().get()).single.url, newest.url);
    },
    skip: executable == null,
  );

  test(
    'a newer inactive Owner survives delayed failure cleanup from an unsaved refresh',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final previous = await core.getConfigState();
      (container.read(profilesProvider.notifier) as _StoredProfiles)
              .failProfile =
          1;
      final gate = core.failureGate = Completer<void>();
      core.failureEntered = Completer<void>();
      final failed = profiles.updateProfile(a);
      final checked = expectLater(failed, throwsA(isA<RequestUnavailable>()));
      await core.failureEntered!.future.timeout(const Duration(seconds: 3));
      final fresh = await client.mutate(
        () async => ConfigInput.write(
          home: root.path,
          yaml: yaml,
          runtimeEpoch: previous.runtimeEpoch,
          profileId: 1,
          profileName: 'newer',
          selectedMap: {},
          testUrl: 'http://127.0.0.1/',
          sources: [await client.captureSource('profile:1')],
        ),
      );
      final newer = await core.applyConfigInput(fresh.toRequest());
      expect(newer.succeeded, true);
      expect(newer.fact.owner, isNot(previous.owner));
      gate.complete();
      await checked;
      final after = await core.getConfigState();
      expect(after.owner, newer.fact.owner);
      expect(after.inputId, fresh.id);
      expect(after.phase, 'ready');
      await core.releaseConfigInput(fresh.markerName);
      await fresh.releaseMarker();
    },
    skip: executable == null,
  );

  test(
    'late groups and providers do not publish over a newer accepted input',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      final gate = core.projectionGate = Completer<void>();
      core.projectionEntered = Completer<void>();
      final refresh = profiles.updateProfile(a);
      await core.projectionEntered!.future.timeout(const Duration(seconds: 3));
      final observed = await core.getConfigState();
      final fresh = await client.mutate(
        () async => ConfigInput.write(
          home: root.path,
          yaml: yaml,
          runtimeEpoch: observed.runtimeEpoch,
          profileId: 1,
          profileName: 'newer projection',
          selectedMap: {},
          testUrl: 'http://127.0.0.1/',
          sources: [await client.captureSource('profile:1')],
        ),
      );
      final newer = await core.applyConfigInput(fresh.toRequest());
      expect(newer.succeeded, true);
      container.read(groupsProvider.notifier).value = [];
      var providerWrites = 0;
      final subscription = container.listen(
        providersProvider,
        (_, _) => providerWrites++,
      );
      globalState.lastConfigMd5 = 'newer-md5';
      gate.complete();
      final result = await refresh;
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.superseded);
      expect(container.read(groupsProvider), isEmpty);
      expect(providerWrites, 0);
      expect(globalState.lastConfigMd5, 'newer-md5');
      expect((await core.getConfigState()).owner, newer.fact.owner);
      subscription.close();
      await core.releaseConfigInput(fresh.markerName);
      await fresh.releaseMarker();
    },
    skip: executable == null,
  );

  test(
    'publication failure after durable save does not roll back only the file',
    () async {
      final a = profile(1);
      await put([a]);
      expect(await setup.applyProfile(force: true), true);
      (container.read(profilesProvider.notifier) as _StoredProfiles)
              .failPublication =
          true;
      responses['/1'] = '$yaml# durable material\n';
      final result = await profiles.updateProfile(a);
      expect(result.materialSaved, true);
      expect(result.failure, 'profile_publish_failed');
      expect(
        (await store.profilesDao.query().get()).single.lastUpdateDate,
        isNotNull,
      );
      expect(
        await File(await appPath.getProfilePath('1')).readAsString(),
        responses['/1'],
      );
    },
    skip: executable == null,
  );

  test(
    'a missing accepted manifest remains unknown and receives conditional failure handling',
    () async {
      final a = profile(1), b = profile(2);
      await put([a, b]);
      expect(await setup.applyProfile(force: true), true);
      final before = await core.getConfigState();
      final count = core.calls
          .where((m) => m == CoreMethod.registerConfigInput)
          .length;
      await File('${root.path}/config-inputs/${before.inputId}.json').delete();
      final result = await profiles.updateProfile(b);
      expect(result.materialSaved, true);
      expect(result.application, isNot(ProfileApplicationOutcome.notRequired));
      expect(
        core.calls.where((m) => m == CoreMethod.registerConfigInput).length,
        count,
      );
      expect(core.calls, contains(CoreMethod.failConfigBuild));
    },
    skip: executable == null,
  );

  for (final registered in [false, true]) {
    test(
      'managed policy remains selected when ${registered ? 'registered' : 'unregistered'} subscription material refreshes',
      () async {
        final fixture = await bridge.call('refreshFixture');
        final selected = selectPolicyDraft(
          PolicyDraftDocument.decode(
            jsonEncode({'draftVersion': 1, 'policy': fixture}),
          ),
        );
        final a = profile(
              1,
              type: registered ? OverwriteType.custom : OverwriteType.standard,
            ),
            b = profile(2);
        await put([a, b]);
        await store.profilePolicySelectionsDao.compareAndWrite(
          1,
          expected: null,
          selection: ProfilePolicySelection(profileId: 1, rawContent: selected),
        );
        if (registered) {
          await store.batch(
            (batch) => batch.insertAll(store.proxyGroups, [
              const ProxyGroup(
                id: 1,
                profileId: 1,
                name: 'dormant-material',
                type: GroupType.Selector,
                use: ['P2'],
              ).toCompanion(),
            ]),
          );
          await File(await appPath.getProfilePath('2')).writeAsString(
            'proxies:\n  - {name: ignored-node, type: socks5, server: 127.0.0.1, port: 1}\n',
          );
          responses['/2'] =
              'proxies:\n  - {name: ignored-node, type: socks5, server: 127.0.0.1, port: 2}\n';
        }
        expect(await setup.applyProfile(force: true), true);
        final before = await core.getConfigState();
        expect(before.isManaged, true);
        final result = await profiles.updateProfile(b);
        final after = await core.getConfigState();
        expect(result.materialSaved, true);
        expect(after.policySha256, before.policySha256);
        expect(
          (await store.profilePolicySelectionsDao.query(1).getSingle())
              .rawContent,
          selected,
        );
        expect(after.owner, registered ? isNot(before.owner) : before.owner);
      },
      skip:
          executable == null ||
          Platform.environment['FLCLASH_MANAGED_PROFILE_COMPILER'] == null,
    );
  }

  for (final local in [false, true]) {
    for (final failure in ['before', 'after']) {
      test(
        'real Go ${local ? 'localCommit' : 'session commit'} ack loss $failure release stays in its receipt',
        () async {
          ackFault = failure;
          final work = local
              ? client.localCommit(() async {})
              : () async {
                  final session = await client.begin(
                    key: 'profile:ack',
                    url: 'http://127.0.0.1/',
                    mode: RequestMode.direct,
                  );
                  try {
                    await session.commit(() async {});
                  } finally {
                    session.close();
                  }
                }();
          await expectLater(
            work.timeout(const Duration(seconds: 3)),
            throwsA(
              isA<RequestUnavailable>().having(
                (e) => e.code,
                'code',
                'request_partial_commit',
              ),
            ),
          );
          expect(client.partialCommit, true);
          expect(
            await File('${root.path}/request-recovery-required').exists(),
            true,
          );
          expect(
            controls.where((c) => c['action'] == 'inspect' && c['id'] != null),
            isNotEmpty,
          );
          final completed = controls.lastWhere(
            (c) => c['action'] == 'complete',
          );
          await bridge.call('control', completed);
        },
        skip: executable == null,
      );
    }
  }
}
