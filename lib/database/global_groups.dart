part of 'database.dart';

@DataClassName('RawGlobalGroupLibrary')
class GlobalGroupLibraries extends Table {
  IntColumn get id => integer()();
  TextColumn get groups => text().map(const LocalProxyGroupsConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

extension GlobalGroupsStore on Database {
  Selectable<RawGlobalGroupLibrary> globalGroupLibrary() =>
      select(globalGroupLibraries)..where((row) => row.id.equals(1));

  Future<List<LocalProxyGroup>> readGlobalGroups() async =>
      (await globalGroupLibrary().getSingle()).groups;

  Future<void> writeGlobalGroups(List<LocalProxyGroup> groups) =>
      into(globalGroupLibraries).insertOnConflictUpdate(
        GlobalGroupLibrariesCompanion.insert(
          id: const Value(1),
          groups: groups,
        ),
      );

  Future<void> initializeGlobalGroups() async {
    if (await globalGroupLibrary().getSingleOrNull() != null) return;
    await transaction(() async {
      final previous = await profilesDao.query().get();
      final migrated = migrateGlobalGroups(const [], previous);
      await writeGlobalGroups(migrated.groups);
      for (var index = 0; index < previous.length; index++) {
        if (previous[index] != migrated.profiles[index]) {
          await profiles.put(migrated.profiles[index].toCompanion());
        }
      }
    });
  }
}
