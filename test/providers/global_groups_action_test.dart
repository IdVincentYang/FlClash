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
  void ready(int id) => state = ConfigViewState(
    fact: ConfigFact(profileId: id, phase: 'ready', inputId: 'input-$id'),
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

  void ready(Profile profile, String node) {
    container.read(currentProfileIdProvider.notifier).value = profile.id;
    container.read(groupsProvider.notifier).value = [
      Group(
        name: 'Main',
        type: GroupType.Selector,
        all: [Proxy(name: node, type: 'ss')],
        now: node,
      ),
    ];
    (container.read(configStateProvider.notifier) as _Fact).ready(profile.id);
  }

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
      expect(profiles.writes.last.localGroups.single.type, GroupType.URLTest);
      container.read(initProvider.notifier).value = true;
      profiles.next = Completer<void>();
      final applied = profiles.next!.future;
      ready(a, 'A node');
      await applied.timeout(const Duration(seconds: 5));
      final binding = profiles.writes.last.localGroups.single;
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
      await action.save(
        [manual, regex],
        [manual, regex],
        profileId: a.id,
        activate: manual.id,
      );
      expect(profiles.writes.last.localGroups.single.effectiveNodes, isEmpty);
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
        activate: manual.id,
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
