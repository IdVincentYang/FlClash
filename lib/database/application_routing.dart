part of 'database.dart';

@DataClassName('RawApplicationRouting')
class ApplicationRoutingLibraries extends Table {
  IntColumn get id => integer()();
  TextColumn get settings => text()();

  @override
  Set<Column> get primaryKey => {id};
}

extension ApplicationRoutingStore on Database {
  Selectable<RawApplicationRouting> applicationRoutingLibrary() =>
      select(applicationRoutingLibraries)..where((row) => row.id.equals(1));

  Future<ApplicationRoutingSettings> readApplicationRouting() async {
    final row = await applicationRoutingLibrary().getSingleOrNull();
    return row == null
        ? const ApplicationRoutingSettings()
        : ApplicationRoutingSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(row.settings) as Map),
          );
  }

  Future<ApplicationRoutingSettings> writeApplicationRouting(
    ApplicationRoutingSettings settings,
  ) async {
    final previous = await readApplicationRouting();
    final next = settings.copyWith(revision: previous.revision + 1);
    await into(applicationRoutingLibraries).insertOnConflictUpdate(
      ApplicationRoutingLibrariesCompanion.insert(
        id: const Value(1),
        settings: jsonEncode(next),
      ),
    );
    return next;
  }

  Future<void> pruneApplicationRouting(Set<int> profiles) async {
    final previous = await readApplicationRouting();
    Map<int, ApplicationRouteTarget> keep(
      Map<int, ApplicationRouteTarget> values,
    ) => Map.fromEntries(values.entries.where((e) => profiles.contains(e.key)));
    final next = previous.copyWith(
      sharedTargets: keep(previous.sharedTargets),
      rules: previous.rules.map(
        (key, rule) =>
            MapEntry(key, rule.copyWith(targets: keep(rule.targets))),
      ),
    );
    if (next != previous) await writeApplicationRouting(next);
  }
}
