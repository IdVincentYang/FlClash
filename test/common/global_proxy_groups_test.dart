import 'package:fl_clash/common/global_proxy_groups.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Profile profile(int id, LocalProxyGroup group) => Profile(
  id: id,
  autoUpdateDuration: const Duration(hours: 1),
  localGroups: [group],
  selectedMap: {'Entry': group.name},
);

void main() {
  const original = LocalProxyGroup(id: 7, name: 'Mine', nodes: ['a']);
  test(
    'identical definitions migrate once while keeping per-profile references and snapshots',
    () {
      final a = original.copyWith(parents: ['Entry A'], matchedNodes: ['a']);
      final b = original.copyWith(
        id: 8,
        parents: ['Entry B'],
        matchedNodes: ['b'],
      );
      final migrated = migrateGlobalGroups([], [profile(1, a), profile(2, b)]);
      expect(migrated.groups, [globalGroupDefinition(original)]);
      expect(migrated.profiles[0].localGroups.single, a);
      expect(migrated.profiles[1].localGroups.single, b.copyWith(id: 7));
    },
  );

  test(
    'name and identity conflicts retain both definitions and do not change selections',
    () {
      final b = original.copyWith(nodes: ['b'], parents: ['Other']);
      final before = [profile(1, original), profile(2, b)];
      final migrated = migrateGlobalGroups([], before);
      expect(migrated.groups.map((group) => group.name), ['Mine', 'Mine (2)']);
      expect(migrated.groups.map((group) => group.id).toSet(), hasLength(2));
      expect(migrated.profiles.last.localGroups.single.name, 'Mine');
      expect(migrated.profiles.last.localGroups.single.parents, ['Other']);
      expect(migrated.profiles.last.selectedMap, before.last.selectedMap);
      final again = migrateGlobalGroups(
        migrated.groups,
        before,
        previousProfiles: migrated.profiles,
      );
      expect(again.groups, migrated.groups);
      expect(again.profiles, migrated.profiles);
    },
  );

  test(
    'explicit global libraries restore independently and preserve binding identities',
    () {
      final b = original.copyWith(id: 8, nodes: ['b']);
      final imported = migrateGlobalGroups(
        [globalGroupDefinition(original)],
        [profile(2, b)],
        definitions: [b],
      );
      expect(imported.groups, hasLength(2));
      expect(imported.groups.last.name, 'Mine (2)');
      expect(imported.profiles.single.localGroups.single, b);
      final again = migrateGlobalGroups(
        imported.groups,
        [profile(2, b)],
        definitions: [b],
      );
      expect(again.groups, imported.groups);
      expect(again.profiles, imported.profiles);
      expect(
        migrateGlobalGroups([], [], definitions: [original]).groups,
        hasLength(1),
      );
    },
  );
}
