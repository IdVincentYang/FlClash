import 'package:fl_clash/models/models.dart';

LocalProxyGroup globalGroupDefinition(LocalProxyGroup group) => group.copyWith(
  global: true,
  parent: null,
  parents: const [],
  matchedNodes: const [],
);

bool sameGlobalGroupDefinition(LocalProxyGroup left, LocalProxyGroup right) =>
    globalGroupDefinition(left) == globalGroupDefinition(right);

typedef GlobalGroupMigration = ({
  List<LocalProxyGroup> groups,
  List<Profile> profiles,
});

GlobalGroupMigration migrateGlobalGroups(
  List<LocalProxyGroup> existing,
  List<Profile> profiles, {
  List<Profile> previousProfiles = const [],
  List<LocalProxyGroup>? definitions,
}) {
  final result = existing.map(globalGroupDefinition).toList();
  final ids = {
    ...result.map((group) => group.id),
    for (final profile in profiles)
      ...profile.localGroups.map((group) => group.id),
  };
  var nextId = 0;
  LocalProxyGroup definition(LocalProxyGroup group) =>
      globalGroupDefinition(group).copyWith(id: 0);
  String uniqueName(String name, {int? replacing}) {
    bool occupied(String value) =>
        result.any((group) => group.id != replacing && group.name == value);
    if (!occupied(name)) return name;
    for (var suffix = 2; ; suffix++) {
      final ending = ' ($suffix)';
      var prefix = '';
      for (final rune in name.runes) {
        final value = String.fromCharCode(rune);
        if (prefix.length + value.length + ending.length > 128) break;
        prefix += value;
      }
      final candidate = '$prefix$ending';
      if (!occupied(candidate)) return candidate;
    }
  }

  LocalProxyGroup resolve(LocalProxyGroup snapshot, Profile profile) {
    var selected = result
        .where((group) => definition(group) == definition(snapshot))
        .firstOrNull;
    final previous = previousProfiles
        .where((item) => item.id == profile.id)
        .firstOrNull
        ?.localGroups
        .where((item) => definition(item) == definition(snapshot))
        .firstOrNull;
    if (selected == null && previous != null) {
      selected = result
          .where(
            (group) =>
                group.id == previous.id &&
                definition(group).copyWith(name: snapshot.name) ==
                    definition(snapshot),
          )
          .firstOrNull;
    }
    if (selected == null) {
      var id = snapshot.id;
      if (result.any((group) => group.id == id)) {
        while (ids.contains(nextId)) {
          nextId++;
        }
        id = nextId++;
        ids.add(id);
      }
      selected = globalGroupDefinition(
        snapshot,
      ).copyWith(id: id, name: uniqueName(snapshot.name));
      result.add(selected);
    }
    return selected;
  }

  final importedIds = <int, int>{};
  for (final group in definitions ?? const <LocalProxyGroup>[]) {
    final index = result.indexWhere((value) => value.id == group.id);
    if (index >= 0) {
      result[index] = globalGroupDefinition(
        group,
      ).copyWith(name: uniqueName(group.name, replacing: group.id));
      importedIds[group.id] = group.id;
    } else {
      final name = uniqueName(group.name);
      final existing = result
          .where((value) => definition(value) == definition(group))
          .firstOrNull;
      final added =
          existing ?? globalGroupDefinition(group).copyWith(name: name);
      if (existing == null) result.add(added);
      importedIds[group.id] = added.id;
    }
  }
  final migrated = <Profile>[
    for (final profile in profiles)
      profile.copyWith(
        localGroups: [
          for (final snapshot in profile.localGroups)
            if (definitions == null || importedIds.containsKey(snapshot.id))
              snapshot.copyWith(
                id: definitions == null
                    ? resolve(snapshot, profile).id
                    : importedIds[snapshot.id]!,
              ),
        ],
      ),
  ];
  return (groups: result, profiles: migrated);
}
