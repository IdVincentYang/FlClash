import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _LocalProfiles extends ProfilesAction {
  @override
  Future<Profile?> ensureFile(Profile profile) async => profile;
}

class _LocalProxies extends ProxiesAction {
  @override
  Future<void> updateGroups() async {}
}

class _LocalProviders extends Providers {
  @override
  Future<void> syncProviders() async {}
}

class _SnapshotSetup extends SetupAction {
  SetupState? captured;
  @override
  Future<({String yaml, String md5})> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
  }) async {
    captured = setupState;
    return (yaml: 'mode: rule\nrules: ["MATCH,REJECT"]\n', md5: 'snapshot');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profile = Profile(
    id: 501,
    label: 'source',
    autoUpdateDuration: Duration.zero,
    overwriteType: OverwriteType.custom,
  );
  late db.Database store;
  late ProviderContainer container;
  late Directory directory;
  late Feature originalFeature;
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'test',
      packageName: 'test.sources',
      version: '0',
      buildNumber: '0',
    );
  });
  setUp(() async {
    originalFeature = feature;
    feature = const Feature(customProviders: true, customProxies: true);
    directory = await Directory.systemTemp.createTemp('config-sources-');
    AppPath.supportDirectory = () async => directory;
    AppPath.temporaryDirectory = () async => directory;
    AppPath.cacheDirectory = () async => directory;
    await AppLocalizations.load(const Locale('en'));
    store = db.Database(NativeDatabase.memory());
    db.database = store;
    await store.profiles.put(profile.toCompanion());
    container = ProviderContainer();
    globalState.container = container;
    container.listen(profilesProvider, (_, _) {});
    await pumpEventQueue();
  });
  tearDown(() async {
    await dataMutations.run(() async {});
    container.dispose();
    await store.close();
    feature = originalFeature;
    await directory.delete(recursive: true);
  });
  Future<void> committed() async {
    await dataMutations.run(() async {});
    await pumpEventQueue();
  }

  test(
    'actual global and profile rule writes revoke only their configuration sources',
    () async {
      container.listen(globalRulesProvider, (_, _) {});
      container.listen(profileCustomRulesProvider(profile.id), (_, _) {});
      await pumpEventQueue();
      final global = await request.captureSource('global-rules');
      final own = await request.captureSource('profile:${profile.id}');
      container
          .read(globalRulesProvider.notifier)
          .put(const Rule(id: 1, content: 'first'));
      await committed();
      expect(await request.configSourceCurrent(global), isFalse);
      expect(await request.configSourceCurrent(own), isTrue);
      expect(await store.rulesDao.queryGlobalAddedRules().get(), hasLength(1));
      final edited = await request.captureSource('global-rules');
      container
          .read(globalRulesProvider.notifier)
          .put(const Rule(id: 1, content: 'changed'));
      await committed();
      expect(await request.configSourceCurrent(edited), isFalse);
      final deleted = await request.captureSource('global-rules');
      container.read(globalRulesProvider.notifier).delAll([1]);
      await committed();
      expect(await request.configSourceCurrent(deleted), isFalse);
      expect(await store.rulesDao.queryGlobalAddedRules().get(), isEmpty);
      container
          .read(profileCustomRulesProvider(profile.id).notifier)
          .put(const Rule(id: 2, content: 'custom'));
      await committed();
      expect(await request.configSourceCurrent(own), isFalse);
      final customEdit = await request.captureSource('profile:${profile.id}');
      container
          .read(profileCustomRulesProvider(profile.id).notifier)
          .put(const Rule(id: 2, content: 'edited'));
      await committed();
      expect(await request.configSourceCurrent(customEdit), isFalse);
      final customDelete = await request.captureSource('profile:${profile.id}');
      container.read(profileCustomRulesProvider(profile.id).notifier).delAll([
        2,
      ]);
      await committed();
      expect(await request.configSourceCurrent(customDelete), isFalse);
      expect(
        await store.rulesDao.queryProfileCustomRules(profile.id).get(),
        isEmpty,
      );
    },
  );

  test(
    'actual custom node and group changes revoke old profile snapshots',
    () async {
      container.listen(customProxiesProvider(profile.id), (_, _) {});
      container.listen(proxyGroupsProvider(profile.id), (_, _) {});
      await pumpEventQueue();
      final nodes = container.read(customProxiesProvider(profile.id).notifier);
      final groups = container.read(proxyGroupsProvider(profile.id).notifier);
      final before = await request.captureSource('profile:${profile.id}');
      nodes.put(
        CustomProxy.fromDefinition({'name': 'node', 'type': 'direct'}, id: 31),
      );
      groups.put(
        const ProxyGroup(
          id: 41,
          name: 'pick',
          type: GroupType.Selector,
          proxies: ['node'],
        ),
      );
      await committed();
      expect(await request.configSourceCurrent(before), isFalse);
      final edit = await request.captureSource('profile:${profile.id}');
      nodes.put(
        CustomProxy.fromDefinition({
          'name': 'renamed',
          'type': 'direct',
        }, id: 31),
      );
      await committed();
      expect(await request.configSourceCurrent(edit), isFalse);
      expect(
        (await store.proxyGroupsDao.query(profile.id).get()).single.proxies,
        ['renamed'],
      );
      final changedGroup = await request.captureSource('profile:${profile.id}');
      groups.put(
        const ProxyGroup(
          id: 41,
          name: 'pick',
          type: GroupType.Selector,
          proxies: ['REJECT'],
        ),
      );
      await committed();
      expect(await request.configSourceCurrent(changedGroup), isFalse);
      expect(
        (await store.proxyGroupsDao.query(profile.id).get()).single.proxies,
        ['REJECT'],
      );
      final removed = await request.captureSource('profile:${profile.id}');
      nodes.delAll([31]);
      groups.delAll([41]);
      await committed();
      expect(await request.configSourceCurrent(removed), isFalse);
      expect(await store.customProxiesDao.query(profile.id).get(), isEmpty);
      expect(await store.proxyGroupsDao.query(profile.id).get(), isEmpty);
    },
  );

  test(
    'overwrite and script choices revoke while a display-only label does not',
    () async {
      final notifier = container.read(profilesProvider.notifier);
      final label = await request.captureSource('profile:${profile.id}');
      await notifier.put(profile.copyWith(label: 'display'));
      expect(await request.configSourceCurrent(label), isTrue);
      final overwrite = await request.captureSource('profile:${profile.id}');
      await notifier.put(
        profile.copyWith(overwriteType: OverwriteType.script, scriptId: 9),
      );
      expect(await request.configSourceCurrent(overwrite), isFalse);
      final script = await request.captureSource('profile:${profile.id}');
      await notifier.put(
        profile.copyWith(overwriteType: OverwriteType.script, scriptId: 10),
      );
      expect(await request.configSourceCurrent(script), isFalse);
    },
  );

  test(
    'production setup invalidates a cached old SetupState before capturing new source tickets',
    () async {
      container.dispose();
      final core = _Core();
      final setup = _SnapshotSetup();
      when(
        () => core.getConfigState(),
      ).thenAnswer((_) async => const ConfigFact(runtimeEpoch: 'sources'));
      when(() => core.releaseConfigInput(any())).thenAnswer((_) async {});
      when(() => core.applyConfigInput(any())).thenAnswer(
        (_) async => ConfigApplyResult.fromJson({
          'status': 'installedInactive',
          'fact': {'runtimeEpoch': 'sources', 'phase': 'ready'},
        }),
      );
      container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          setupActionProvider.overrideWith(() => setup),
          profilesActionProvider.overrideWith(_LocalProfiles.new),
          proxiesActionProvider.overrideWith(_LocalProxies.new),
          providersProvider.overrideWith(_LocalProviders.new),
        ],
      );
      globalState.container = container;
      container.listen(configProvider, (_, _) {});
      container.listen(profilesProvider, (_, _) {});
      await pumpEventQueue();

      await store.customProxies.put(
        CustomProxy.fromDefinition({
          'name': 'old',
          'type': 'direct',
        }, id: 31).toCompanion(profile.id),
      );
      container.listen(setupStateProvider(profile.id), (_, _) {});
      final old = await container.read(setupStateProvider(profile.id).future);
      expect(old.customProxies, hasLength(1));
      container.listen(customProxiesProvider(profile.id), (_, _) {});
      await pumpEventQueue();
      final ticket = await request.captureSource('profile:${profile.id}');
      container.read(customProxiesProvider(profile.id).notifier).delAll([31]);
      await committed();
      expect(await request.configSourceCurrent(ticket), isFalse);
      expect(
        identical(
          await container.read(setupStateProvider(profile.id).future),
          old,
        ),
        isTrue,
      );
      expect(
        await container
            .read(setupActionProvider.notifier)
            .applyProfile(force: true),
        isTrue,
      );
      expect(setup.captured!.customProxies, isEmpty);
      expect(setup.captured!.overwriteType, OverwriteType.custom);
      verify(() => core.applyConfigInput(any())).called(1);
      final defaults = <String, dynamic>{
        'mode': 'rule',
        'proxies': [
          {'name': 'reset', 'type': 'direct'},
        ],
        'proxy-groups': [
          {
            'name': 'reset-group',
            'type': 'select',
            'proxies': ['reset'],
          },
        ],
        'rule': ['MATCH,reset-group'],
      };
      when(() => core.getConfig(any())).thenAnswer((_) async => defaults);
      final beforeReset = await request.captureSource('profile:${profile.id}');
      await container
          .read(profilesActionProvider.notifier)
          .useDefaultCustomConfig(profile.id);
      expect(await request.configSourceCurrent(beforeReset), isFalse);
      expect(
        (await store.customProxiesDao.query(profile.id).get()).single.name,
        'reset',
      );
      expect(
        (await store.proxyGroupsDao.query(profile.id).get()).single.name,
        'reset-group',
      );
      expect(
        await store.rulesDao.queryProfileCustomRules(profile.id).get(),
        hasLength(1),
      );
      expect(await setup.applyProfile(force: true), isTrue);
      expect(setup.captured!.customProxies.single.name, 'reset');
      expect(setup.captured!.proxyGroups.single.name, 'reset-group');
      final sampling = Completer<void>();
      final releaseSampling = Completer<void>();
      when(() => core.getConfig(any())).thenAnswer((_) async {
        sampling.complete();
        await releaseSampling.future;
        return defaults;
      });
      final obsoleteReset = container
          .read(profilesActionProvider.notifier)
          .useDefaultCustomConfig(profile.id);
      final rejected = expectLater(
        obsoleteReset,
        throwsA(isA<RequestUnavailable>()),
      );
      await sampling.future;
      container.read(customProxiesProvider(profile.id).notifier).delAll([
        (await store.customProxiesDao.query(profile.id).get()).single.id,
      ]);
      await committed();
      releaseSampling.complete();
      await rejected;
      expect(await store.customProxiesDao.query(profile.id).get(), isEmpty);
    },
  );
}
