import 'package:drift/native.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'dart:ui' show Locale;
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_config_state.dart';

class _Setup extends SetupAction {
  int reservations = 0;
  @override
  void build() {}
  @override
  int reserveSetupSequence() => ++reservations;
}

class _Groups extends GlobalGroupsAction {
  bool fail = false;
  int calls = 0;
  @override
  Future<void> synchronizeApplicationGroups() async {
    calls++;
    if (fail) throw StateError('unrelated group failure');
  }
}

class _Core implements CoreController {
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  bool unavailable = false;
  @override
  Future<ConfigFact> getConfigState() async {
    if (unavailable) throw StateError('Core stopped');
    return const ConfigFact(runtimeEpoch: 'test', profileId: 7, phase: 'ready');
  }

  @override
  Future<String> updateApplicationRouting(Map<String, dynamic> settings) async {
    writes.add(settings);
    return fail ? 'controlled adoption failure' : '';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Core action: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });
  late Database store;
  late ProviderContainer container;
  late _Core core;
  late _Groups groups;
  late _Setup setup;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = Database(NativeDatabase.memory());
    database = store;
    core = _Core();
    groups = _Groups();
    setup = _Setup();
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(core),
        setupActionProvider.overrideWith(() => setup),
        currentProfileIdProvider.overrideWithBuild((_, _) => 7),
        configStateProvider.overrideWith(
          () => TestConfigState(
            const ConfigFact(
              runtimeEpoch: 'test',
              profileId: 7,
              phase: 'ready',
            ),
          ),
        ),
        globalGroupsActionProvider.overrideWith(() => groups),
        runControlProvider.overrideWithValue(false),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await store.close();
  });

  test(
    'save and toggle change only the app policy, retaining the target',
    () async {
      final controller = container.read(
        applicationRoutingControllerProvider.notifier,
      );
      const target = ApplicationRouteTarget(
        name: 'Mine',
        kind: ApplicationTargetKind.group,
      );
      await controller.setPolicy(
        ['a'],
        ApplicationRouteAction.proxy,
        target: target,
        enable: true,
      );
      final saved = await store.readApplicationRouting();
      expect(saved.rules['a']?.enabled, true);
      expect(saved.rules['a']?.targets[7], target);
      expect(core.writes.single, compileApplicationRouting(saved, 7));
      await controller.setEnabled(['a'], false);
      expect(core.writes.last['rules'], isEmpty);
      expect(
        (await store.readApplicationRouting()).rules['a']?.targets[7],
        target,
      );
    },
  );

  test(
    'stale chooser cannot write a source target into a different subscription',
    () async {
      container.read(currentProfileIdProvider.notifier).value = 8;
      await expectLater(
        container
            .read(applicationRoutingControllerProvider.notifier)
            .setPolicy(
              ['a'],
              ApplicationRouteAction.proxy,
              target: const ApplicationRouteTarget(
                name: 'same name',
                kind: ApplicationTargetKind.node,
              ),
              expectedProfileId: 7,
            ),
        throwsA(anything),
      );
      expect((await store.readApplicationRouting()).rules, isEmpty);
      expect(core.writes, isEmpty);
      expect(setup.reservations, 0);
      expect(
        container.read(applicationRoutingControllerProvider).errors,
        isEmpty,
      );
    },
  );

  test(
    'an unrelated group failure cannot block a direct application policy',
    () async {
      groups.fail = true;
      await container
          .read(applicationRoutingControllerProvider.notifier)
          .setPolicy(['a'], ApplicationRouteAction.direct, enable: true);
      expect(groups.calls, 0);
      expect(core.writes.single['rules'], [
        {'package': 'a', 'target': 'DIRECT'},
      ]);
    },
  );

  test('offline preselection saves without starting Core or VPN', () async {
    core.unavailable = true;
    await container
        .read(applicationRoutingControllerProvider.notifier)
        .setPolicy(['a'], ApplicationRouteAction.direct);
    expect(core.writes, isEmpty);
    expect(
      (await store.readApplicationRouting()).rules['a']?.action,
      ApplicationRouteAction.direct,
    );
    expect(
      container.read(applicationRoutingControllerProvider).errors,
      isEmpty,
    );
  });

  test(
    'failed adoption keeps saved intent and reports an error for the affected app',
    () async {
      core.fail = true;
      await expectLater(
        container
            .read(applicationRoutingControllerProvider.notifier)
            .setPolicy(['a'], ApplicationRouteAction.reject, enable: true),
        throwsA(anything),
      );
      expect((await store.readApplicationRouting()).rules['a']?.enabled, true);
      expect(container.read(applicationRoutingControllerProvider).errors.keys, [
        'a',
      ]);
      expect(
        container.read(applicationRoutingControllerProvider).pending,
        isEmpty,
      );
    },
  );
}
