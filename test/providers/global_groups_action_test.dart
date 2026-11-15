import 'dart:async';
import 'package:collection/collection.dart';

import 'package:drift/native.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Client extends Request {
  @override
  bool get isAttached => true;
  @override
  Future<void> invalidate(String key) async {}
}

class _Global extends GlobalGroupsAction {
  final client = _Client();
  @override
  Request get requestClient => client;
}

class _Core implements CoreController {
  @override
  Future<Map<String, dynamic>> sourceAcceptance(
    Map<String, Object?> input,
  ) async => {
    'matches': (input['names'] as List<String>)
        .where(RegExp(input['pattern'] as String).hasMatch)
        .toList(),
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fact extends ConfigState {
  @override
  ConfigViewState build() => const ConfigViewState();
  void ready(int id, {bool managed = false}) => state = ConfigViewState(
    fact: ConfigFact(
      profileId: id,
      phase: 'ready',
      inputId: 'input-$id',
      policyVersion: managed ? 2 : 0,
    ),
  );
}

class _Groups extends Groups {
  @override
  List<Group> build() => const [];
}

class _Profiles extends ProfilesAction {
  final writes = <Profile>[];
  bool fail = false;
  Completer<void>? next;
  @override
  void build() {}
  @override
  Future<void> saveLocalGroups(
    Profile expected,
    List<LocalProxyGroup> groups, {
    void Function()? onSaved,
    List<LocalProxyGroup>? expectedGlobalGroups,
  }) async {
    if (fail) throw StateError('apply failed');
    final current = ref.read(currentProfileProvider)!;
    if (current != expected ||
        !const ListEquality<LocalProxyGroup>().equals(
          expectedGlobalGroups,
          await database.readGlobalGroups(),
        )) {
      throw const LocalProxyGroupProblem('changed');
    }
    final saved = expected.copyWith(localGroups: groups);
    await database.profiles.put(saved.toCompanion());
    await ref.read(profilesProvider.notifier).put(saved);
    writes.add(saved);
    onSaved?.call();
    next?.complete();
    next = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database store;
  late ProviderContainer container;
  late _Global action;
  late _Profiles profiles;
  final a = Profile.normal(label: 'A');
  final b = Profile.normal(label: 'B');
  const manual = LocalProxyGroup(
    id: 1,
    name: 'Mine',
    nodes: ['A node', 'B node', 'missing'],
    global: true,
    type: GroupType.Fallback,
  );
  const regex = LocalProxyGroup(
    id: 2,
    name: 'Auto',
    regex: r'node$',
    global: true,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Database(NativeDatabase.memory());
    database = store;
    await store.profilesDao.putAll([a.toCompanion(), b.toCompanion()]);
    await store.writeGlobalGroups([manual, regex]);
    action = _Global();
    profiles = _Profiles();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([a, b])),
        currentProfileIdProvider.overrideWithBuild((_, _) => a.id),
        groupsProvider.overrideWith(_Groups.new),
        configStateProvider.overrideWith(_Fact.new),
        profilesActionProvider.overrideWith(() => profiles),
        globalGroupsActionProvider.overrideWith(() => action),
        coreHandlerProvider.overrideWithValue(_Core()),
      ],
    );
    container.listen(groupsProvider, (_, _) {});
    container.read(globalGroupsActionProvider);
  });
  tearDown(() async {
    container.dispose();
    await store.close();
  });

  void ready(Profile profile, String node, {String main = 'Main'}) {
    container.read(currentProfileIdProvider.notifier).value = profile.id;
    container.read(groupsProvider.notifier).value = [
      Group(
        name: main,
        type: GroupType.Selector,
        all: [Proxy(name: node, type: 'ss')],
        now: node,
      ),
      Group(
        name: 'Media',
        type: GroupType.Selector,
        all: [Proxy(name: node, type: 'ss')],
        now: node,
      ),
    ];
    (container.read(configStateProvider.notifier) as _Fact).ready(profile.id);
  }

  test(
    'new groups join the main selector without changing its selection',
    () async {
      ready(a, 'A node');
      await action.synchronizeApplicationGroups();
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        manual.id,
        ['Media'],
      );
      const created = LocalProxyGroup(id: 3, name: 'New', nodes: ['A node']);
      await action.save(
        [manual, regex],
        [manual, regex, created],
        profileId: a.id,
      );
      final bindings = profiles.writes.last.localGroups;
      expect(bindings.map((group) => group.id), [
        manual.id,
        regex.id,
        created.id,
      ]);
      expect(bindings.first.entrances, {'Media'});
      expect(bindings.last.entrances, {'Main'});
      expect(bindings.last.effectiveNodes, ['A node']);
      expect(container.read(groupsProvider).first.now, 'A node');
      expect(
        container.read(currentProfileProvider)!.selectedMap,
        a.selectedMap,
      );
    },
  );

  test(
    'switching back restores default references while retaining other parents',
    () async {
      ready(a, 'A node');
      await action.synchronizeApplicationGroups();
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        manual.id,
        ['Media'],
      );
      final writes = profiles.writes.length;
      await action.synchronizeApplicationGroups();
      expect(profiles.writes, hasLength(writes));
      expect(
        container.read(currentProfileProvider)!.localGroups.first.entrances,
        {'Media'},
      );
      container.read(initProvider.notifier).value = true;
      profiles.next = Completer<void>();
      var applied = profiles.next!.future;
      ready(b, 'B node', main: 'Subscription B');
      await applied.timeout(const Duration(seconds: 5));
      expect(profiles.writes.last.localGroups, hasLength(2));
      expect(
        profiles.writes.last.localGroups.every(
          (g) => g.entrances.contains('Subscription B'),
        ),
        isTrue,
      );
      expect(profiles.writes.last.localGroups.first.effectiveNodes, ['B node']);
      profiles.next = Completer<void>();
      applied = profiles.next!.future;
      ready(a, 'A node');
      await applied.timeout(const Duration(seconds: 5));
      final group = container.read(currentProfileProvider)!.localGroups.first;
      expect(group.entrances, {'Main', 'Media'});
      expect(group.parents.where((parent) => parent == 'Main'), hasLength(1));
      expect(group.effectiveNodes, ['A node']);
      expect(container.read(groupsProvider).first.now, 'A node');
    },
  );

  test('without a subscription selector groups remain independent', () async {
    ready(a, 'A node');
    container.read(groupsProvider.notifier).value = const [
      Group(
        name: 'GLOBAL',
        type: GroupType.Selector,
        all: [Proxy(name: 'A node', type: 'ss')],
      ),
      Group(
        name: 'Auto',
        type: GroupType.URLTest,
        all: [Proxy(name: 'A node', type: 'ss')],
      ),
    ];
    await action.synchronizeApplicationGroups();
    expect(profiles.writes.last.localGroups, hasLength(2));
    expect(
      profiles.writes.last.localGroups.every((g) => g.entrances.isEmpty),
      isTrue,
    );
  });

  test(
    'managed policies do not receive subscription group injections',
    () async {
      ready(a, 'A node');
      (container.read(configStateProvider.notifier) as _Fact).ready(
        a.id,
        managed: true,
      );
      await action.synchronizeApplicationGroups();
      expect(profiles.writes, isEmpty);
      expect(await store.readGlobalGroups(), [manual, regex]);
    },
  );

  test(
    'all global groups are available to app policies and the subscription entrance',
    () async {
      ready(a, 'A node');
      await store.writeApplicationRouting(
        ApplicationRoutingSettings(
          sharedTargets: {
            a.id: ApplicationRouteTarget(
              name: regex.name,
              kind: ApplicationTargetKind.globalGroup,
              groupId: regex.id,
            ),
          },
          rules: const {
            'app': ApplicationRouteRule(packageName: 'app', enabled: true),
          },
        ),
      );
      await action.synchronizeApplicationGroups();
      final binding = profiles.writes.last.localGroups.firstWhere(
        (group) => group.id == regex.id,
      );
      expect(profiles.writes.last.localGroups, hasLength(2));
      expect(binding.id, regex.id);
      expect(binding.effectiveNodes, ['A node']);
      expect(binding.entrances, {'Main'});
    },
  );

  test(
    'A to B to A shares definitions but resolves members and references per subscription',
    () async {
      ready(a, 'A node');
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        manual.id,
        ['Main'],
      );
      expect(profiles.writes.last.localGroups.single.effectiveNodes, [
        'A node',
      ]);
      ready(b, 'B node');
      expect(container.read(currentProfileProvider)!.localGroups, isEmpty);
      expect(await store.readGlobalGroups(), [manual, regex]);
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        regex.id,
        ['Media'],
      );
      expect(profiles.writes.last.localGroups.single.effectiveNodes, [
        'B node',
      ]);
      ready(a, 'A node');
      expect(
        container.read(currentProfileProvider)!.localGroups.single.entrances,
        {'Main'},
      );
      expect(
        (await store.profilesDao.query().get())
            .firstWhere((p) => p.id == b.id)
            .localGroups
            .single
            .entrances,
        {'Media'},
      );
      expect(await store.readGlobalGroups(), [manual, regex]);
    },
  );

  test(
    'global edits update active binding; bound inactive profiles catch up after switching',
    () async {
      ready(a, 'A node');
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        manual.id,
        ['Main'],
      );
      ready(b, 'B node');
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        manual.id,
        ['Media'],
      );
      final changed = manual.copyWith(type: GroupType.URLTest);
      await action.save([manual, regex], [changed, regex]);
      expect(profiles.writes.last.id, b.id);
      expect(
        profiles.writes.last.localGroups
            .firstWhere((g) => g.id == manual.id)
            .type,
        GroupType.URLTest,
      );
      container.read(initProvider.notifier).value = true;
      profiles.next = Completer<void>();
      final applied = profiles.next!.future;
      ready(a, 'A node');
      await applied.timeout(const Duration(seconds: 5));
      final binding = profiles.writes.last.localGroups.firstWhere(
        (group) => group.id == manual.id,
      );
      expect(binding.type, GroupType.URLTest);
      expect(binding.entrances, {'Main'});
      expect(binding.effectiveNodes, ['A node']);
    },
  );

  test(
    'failed adoption retains global definition; stale saves do not replace newer edits',
    () async {
      ready(a, 'A node');
      await action.saveReferences(
        container.read(currentProfileProvider)!,
        [manual, regex],
        manual.id,
        ['Main'],
      );
      profiles.fail = true;
      final changed = manual.copyWith(type: GroupType.URLTest);
      await expectLater(
        action.save([manual, regex], [changed, regex]),
        throwsStateError,
      );
      expect(await store.readGlobalGroups(), [changed, regex]);
      expect(
        container.read(currentProfileProvider)!.localGroups.single.type,
        GroupType.Fallback,
      );
      await expectLater(
        action.save([manual, regex], []),
        throwsA(
          isA<LocalProxyGroupProblem>().having(
            (e) => e.code,
            'code',
            'changed',
          ),
        ),
      );
      expect(await store.readGlobalGroups(), [changed, regex]);
    },
  );

  test(
    'missing members keep canonical selection, block new references and never substitute another node',
    () async {
      ready(a, 'other node');
      await expectLater(
        action.saveReferences(a, [manual, regex], manual.id, ['Main']),
        throwsA(
          isA<LocalProxyGroupProblem>().having(
            (e) => e.code,
            'code',
            'noMatchingNodes',
          ),
        ),
      );
      await action.save([manual, regex], [manual, regex], profileId: a.id);
      expect(
        profiles.writes.last.localGroups
            .firstWhere((group) => group.id == manual.id)
            .effectiveNodes,
        isEmpty,
      );
      expect(
        profiles.writes.last.localGroups
            .firstWhere((group) => group.id == manual.id)
            .entrances,
        {'Main'},
      );
      expect(container.read(groupsProvider).first.now, 'other node');
      expect((await store.readGlobalGroups()).first.nodes, manual.nodes);
    },
  );

  test(
    'a profile switch after global save cannot bind the new group to the later subscription',
    () async {
      ready(a, 'A node');
      await action.save(
        [manual, regex],
        [manual, regex],
        profileId: a.id,
        onSaved: () => ready(b, 'B node'),
      );
      expect(profiles.writes, isEmpty);
      expect(container.read(currentProfileProvider)!.localGroups, isEmpty);
      expect(await store.readGlobalGroups(), [manual, regex]);
    },
  );

  test(
    'deletion or disable protects selections in another subscription',
    () async {
      final using = a.copyWith(
        localGroups: [
          manual.copyWith(parents: ['Main'], matchedNodes: ['A node']),
        ],
        selectedMap: {'Main': 'Mine'},
      );
      await store.profiles.put(using.toCompanion());
      ready(b, 'B node');
      for (final replacement in [
        <LocalProxyGroup>[regex],
        [manual.copyWith(enabled: false), regex],
        [manual.copyWith(name: 'Renamed'), regex],
      ]) {
        await expectLater(
          action.save([manual, regex], replacement),
          throwsA(
            isA<LocalProxyGroupProblem>().having(
              (e) => e.code,
              'code',
              'inUseProfile',
            ),
          ),
        );
        expect(await store.readGlobalGroups(), [manual, regex]);
      }
    },
  );
}
