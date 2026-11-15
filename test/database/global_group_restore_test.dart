import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = LocalProxyGroup(
  id: 8,
  name: 'Mine',
  nodes: ['node'],
  global: true,
);

ApplicationRouteTarget _target(
  int id, {
  ApplicationTargetKind kind = ApplicationTargetKind.globalGroup,
}) => ApplicationRouteTarget(name: 'Mine', kind: kind, groupId: id);

Profile _profile(int id, LocalProxyGroup group) => Profile(
  id: id,
  autoUpdateDuration: Duration.zero,
  localGroups: [
    group.copyWith(parents: ['Main'], matchedNodes: ['node']),
  ],
  selectedMap: const {'Main': 'Mine'},
);

ApplicationRoutingSettings _routing(Map<int, ApplicationRouteTarget> targets) =>
    ApplicationRoutingSettings(
      sharedTargets: targets,
      rules: {
        'shared.app': const ApplicationRouteRule(
          packageName: 'shared.app',
          enabled: true,
        ),
        'own.app': ApplicationRouteRule(
          packageName: 'own.app',
          enabled: true,
          useSharedTarget: false,
          targets: targets,
        ),
      },
    );

Rule _host(
  int id,
  Map<int, ApplicationRouteTarget> targets, {
  String? package,
  int? profileId,
}) => hostRuleTemplate('host$id.test').copyWith(
  id: id,
  ruleTarget: 'Mine',
  hostBinding: HostRuleBinding(
    packageName: package,
    profileId: profileId,
    targets: targets,
  ),
);

Database _memoryStore() {
  final store = Database(NativeDatabase.memory());
  addTearDown(store.close);
  return store;
}

Future<void> _restore(
  Database store, {
  List<Profile> profiles = const [],
  List<LocalProxyGroup>? definitions,
  ApplicationRoutingSettings? routing,
  List<Rule> hosts = const [],
  List<ProfileRuleLink>? links,
  bool replace = false,
  Future<void> Function()? beforeCommit,
}) => store.restore(
  profiles,
  [],
  hosts,
  links ?? [for (final host in hosts) ProfileRuleLink(ruleId: host.id)],
  [],
  globalGroups: definitions,
  applicationRouting: routing,
  isOverride: replace,
  beforeCommit: beforeCommit,
);

Future<Map<String, Object>> _snapshot(Database store) async => {
  'groups': await store.readGlobalGroups(),
  'profiles': await store.profilesDao.query().get(),
  'routing': await store.readApplicationRouting(),
  'rules': await store.select(store.rules).get(),
  'links': await store.select(store.profileRuleLinks).get(),
};

Future<void> _expectTargets(Database store, Map<int, int> expected) async {
  final settings = await store.readApplicationRouting();
  expect(
    settings.sharedTargets.map((k, v) => MapEntry(k, v.groupId)),
    expected,
  );
  expect(
    settings.rules['own.app']!.targets.map((k, v) => MapEntry(k, v.groupId)),
    expected,
  );
  for (final host in settings.hostRules) {
    expect(
      host.hostBinding!.targets.map((k, v) => MapEntry(k, v.groupId)),
      expected,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'equivalent imported groups remap every target and production wire',
    () async {
      final store = _memoryStore();
      await store.writeGlobalGroups([_group]);
      final imported = _group.copyWith(id: 9);
      await _restore(
        store,
        profiles: [_profile(1, imported)],
        definitions: [imported],
        routing: _routing({1: _target(9)}),
        hosts: [
          _host(123, {1: _target(9)}),
        ],
      );
      await _expectTargets(store, {1: 8});
      final profile = (await store.profilesDao.query().get()).single;
      expect(profile.localGroups.single.id, 8);
      expect(profile.selectedMap, {'Main': 'Mine'});
      final settings = await store.readApplicationRouting();
      final targets = [
        applicationTargetFor(settings, settings.rules['shared.app']!, 1),
        applicationTargetFor(settings, settings.rules['own.app']!, 1),
        hostRuleTarget(settings.hostRules.single, 1),
      ];
      for (final target in targets) {
        final resolved = resolveApplicationTarget(
          target: target,
          profile: profile,
          definitions: await store.readGlobalGroups(),
          groups: const [
            Group(
              name: 'Mine',
              type: GroupType.Selector,
              all: [Proxy(name: 'node', type: 'ss')],
            ),
          ],
          ready: true,
        );
        expect(resolved.issue, isNull);
        expect(resolved.members, 1);
      }
      final wire = compileApplicationRouting(settings, 1);
      expect((wire['rules'] as List).map((e) => e['groupId']), [8, 8]);
      expect((wire['hostRules'] as List).single['groupId'], 8);
      await _restore(
        store,
        profiles: [_profile(1, imported)],
        definitions: [imported],
        routing: _routing({1: _target(9)}),
        hosts: [
          _host(123, {1: _target(9)}),
        ],
      );
      expect(await store.readGlobalGroups(), [_group]);
      await _expectTargets(store, {1: 8});
    },
  );

  test(
    'merge remaps only imported targets and keeps Host ownership and links',
    () async {
      final store = _memoryStore();
      await store.writeGlobalGroups([_group]);
      final retained = _profile(2, _group);
      await store.profilesDao.setAll([retained]);
      final retainedProfile = (await store.profilesDao.query().get()).single;
      final before = _routing({2: _target(9)}).copyWith(
        rules: {
          ..._routing({2: _target(9)}).rules,
          'untouched.app': ApplicationRouteRule(
            packageName: 'untouched.app',
            targets: {2: _target(9)},
          ),
        },
      );
      await store.writeApplicationRouting(before);
      final retainedHost = _host(122, {
        2: _target(9),
      }, package: 'untouched.app');
      await store.rulesDao.putGlobalRule(retainedHost);
      final imported = _group.copyWith(id: 9);
      final host = _host(
        123,
        {1: _target(9)},
        package: 'own.app',
        profileId: 1,
      );
      const ordinary = Rule(
        id: 124,
        ruleAction: RuleAction.DOMAIN,
        content: 'ordinary.test',
        ruleTarget: 'Mine',
        noResolve: true,
      );
      const links = [
        ProfileRuleLink(
          ruleId: 123,
          profileId: 1,
          scene: RuleScene.added,
          order: 'a',
        ),
        ProfileRuleLink(
          ruleId: 123,
          profileId: 2,
          scene: RuleScene.disabled,
          order: 'b',
        ),
        ProfileRuleLink(
          ruleId: 124,
          profileId: 1,
          scene: RuleScene.custom,
          order: 'c',
        ),
      ];
      await _restore(
        store,
        profiles: [_profile(1, imported)],
        definitions: [imported],
        routing: _routing({1: _target(9)}),
        hosts: [host, ordinary],
        links: links,
      );
      final settings = await store.readApplicationRouting();
      expect(settings.sharedTargets, {2: _target(9), 1: _target(8)});
      expect(settings.rules['own.app']!.targets, {
        2: _target(9),
        1: _target(8),
      });
      expect(settings.rules['untouched.app'], before.rules['untouched.app']);
      expect(
        (await store.profilesDao.query().get()).firstWhere((p) => p.id == 2),
        retainedProfile,
      );
      expect(settings.hostRules.firstWhere((r) => r.id == 122), retainedHost);
      final savedHost = settings.hostRules.firstWhere((r) => r.id == 123);
      expect(
        savedHost,
        host.copyWith(
          hostBinding: host.hostBinding!.copyWith(
            targets: {1: _target(8)},
            disabledProfiles: [2],
          ),
        ),
      );
      expect(
        (await store.select(store.profileRuleLinks).get())
            .where((l) => l.ruleId == 123)
            .map((l) => l.toLink().copyWith(order: null)),
        links.where((l) => l.ruleId == 123).map((l) => l.copyWith(order: null)),
      );
      expect(
        (await store.rulesDao.queryProfileCustomRules(1).get()).map(
          (rule) => rule.copyWith(order: null),
        ),
        [ordinary],
      );
    },
  );

  test(
    'explicit identity replacement and same-name definitions keep their semantics',
    () async {
      final store = _memoryStore();
      await store.writeGlobalGroups([_group]);
      final replacement = _group.copyWith(nodes: ['replacement']);
      await _restore(
        store,
        profiles: [_profile(1, replacement)],
        definitions: [replacement],
        routing: _routing({1: _target(8)}),
        hosts: [
          _host(123, {1: _target(8)}),
        ],
      );
      expect(await store.readGlobalGroups(), [replacement]);
      await _expectTargets(store, {1: 8});
      final different = _group.copyWith(id: 9, nodes: ['other']);
      await _restore(
        store,
        profiles: [_profile(1, different)],
        definitions: [different],
        routing: _routing({1: _target(9)}),
        hosts: [
          _host(123, {1: _target(9)}),
        ],
      );
      expect(await store.readGlobalGroups(), [
        replacement,
        different.copyWith(name: 'Mine (2)'),
      ]);
      await _expectTargets(store, {1: 9});
    },
  );

  test(
    'legacy colliding ids use the target Profile for App and Host maps',
    () async {
      final store = _memoryStore();
      final first = _group.copyWith(id: 7);
      final second = first.copyWith(nodes: ['other']);
      await _restore(
        store,
        profiles: [
          _profile(1, first),
          _profile(2, second),
          const Profile(id: 3, autoUpdateDuration: Duration.zero),
        ],
        routing: _routing({1: _target(7), 2: _target(7), 3: _target(7)}),
        hosts: [
          _host(123, {
            1: _target(7),
            2: _target(7),
            3: _target(7),
          }, package: 'own.app'),
        ],
      );
      expect((await store.readGlobalGroups()).map((g) => g.id), [7, 0]);
      expect(
        (await store.profilesDao.query().get())
            .where((p) => p.id != 3)
            .map((p) => p.localGroups.single.id),
        [7, 0],
      );
      await _expectTargets(store, {1: 7, 2: 0, 3: 7});
    },
  );

  test(
    'unmapped and non-global targets do not inherit another mapping',
    () async {
      final store = _memoryStore();
      await store.writeGlobalGroups([_group]);
      final imported = _group.copyWith(id: 9);
      final targets = {
        1: _target(9, kind: ApplicationTargetKind.node),
        2: _target(9, kind: ApplicationTargetKind.group),
        3: _target(99),
      };
      await _restore(
        store,
        profiles: [for (final id in targets.keys) _profile(id, imported)],
        definitions: [imported],
        routing: _routing(targets),
        hosts: [_host(123, targets)],
      );
      final settings = await store.readApplicationRouting();
      expect(settings.sharedTargets, targets);
      expect(settings.rules['own.app']!.targets, targets);
      expect(settings.hostRules.single.hostBinding!.targets, targets);
    },
  );

  test(
    'global-only import maps incoming targets for an existing Profile',
    () async {
      final store = _memoryStore();
      await store.writeGlobalGroups([_group]);
      await store.profilesDao.setAll([_profile(1, _group)]);
      await _restore(
        store,
        definitions: [_group.copyWith(id: 9)],
        routing: _routing({1: _target(9)}),
        hosts: [
          _host(123, {1: _target(9)}),
        ],
      );
      await _expectTargets(store, {1: 8});
    },
  );

  test(
    'replace discards the old library instead of deduplicating against it',
    () async {
      final store = _memoryStore();
      await store.writeGlobalGroups([_group]);
      await store.profilesDao.setAll([_profile(2, _group)]);
      await store.writeApplicationRouting(_routing({2: _target(8)}));
      final imported = _group.copyWith(id: 9);
      await _restore(
        store,
        profiles: [_profile(1, imported)],
        definitions: [imported],
        routing: _routing({1: _target(9)}),
        hosts: [
          _host(123, {1: _target(9)}),
        ],
        replace: true,
      );
      expect(await store.readGlobalGroups(), [imported]);
      expect((await store.profilesDao.query().get()).single.id, 1);
      await _expectTargets(store, {1: 9});
    },
  );

  for (final fail in [false, true]) {
    test('file restore survives reopen; beforeCommit failure: $fail', () async {
      final directory = await Directory.systemTemp.createTemp('group-restore-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/state.sqlite');
      var store = Database(NativeDatabase(file));
      try {
        await store.writeGlobalGroups([_group]);
        await store.profilesDao.setAll([_profile(2, _group)]);
        await store.writeApplicationRouting(_routing({2: _target(8)}));
        await store.rulesDao.putGlobalRule(_host(122, {2: _target(8)}));
        final before = await _snapshot(store);
        final imported = _group.copyWith(id: 9);
        final operation = _restore(
          store,
          profiles: [_profile(1, imported)],
          definitions: [imported],
          routing: _routing({1: _target(9)}),
          hosts: [
            _host(123, {1: _target(9)}),
          ],
          beforeCommit: fail
              ? () async {
                  final current = await store.readApplicationRouting();
                  expect(current.sharedTargets[1]!.groupId, 8);
                  throw StateError('cancelled');
                }
              : null,
        );
        if (fail) {
          await expectLater(operation, throwsStateError);
          expect(await _snapshot(store), before);
        } else {
          await operation;
        }
        final committed = await _snapshot(store);
        await store.close();
        store = Database(NativeDatabase(file));
        expect(await _snapshot(store), committed);
        if (!fail) {
          final settings = await store.readApplicationRouting();
          expect(settings.sharedTargets, {2: _target(8), 1: _target(8)});
          expect(settings.rules['own.app']!.targets[1]!.groupId, 8);
          expect(
            settings.hostRules
                .firstWhere((r) => r.id == 123)
                .hostBinding!
                .targets[1]!
                .groupId,
            8,
          );
        }
      } finally {
        await store.close();
      }
    });
  }
}
