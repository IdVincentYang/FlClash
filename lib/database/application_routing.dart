part of 'database.dart';

@DataClassName('RawApplicationRouting')
class ApplicationRoutingLibraries extends Table {
  IntColumn get id => integer()();
  TextColumn get settings => text()();

  @override
  Set<Column> get primaryKey => {id};
}

extension ApplicationRoutingStore on Database {
  Stream<ApplicationRoutingSettings> watchApplicationRouting() => customSelect(
    'SELECT settings FROM application_routing_libraries',
    readsFrom: {applicationRoutingLibraries, rules, profileRuleLinks},
  ).watch().asyncMap((_) => readApplicationRouting());
  Selectable<RawApplicationRouting> applicationRoutingLibrary() =>
      select(applicationRoutingLibraries)..where((row) => row.id.equals(1));

  Future<ApplicationRoutingSettings> readApplicationRouting() =>
      transaction(() async {
        final row = await applicationRoutingLibrary().getSingleOrNull();
        final settings = row == null
            ? const ApplicationRoutingSettings()
            : ApplicationRoutingSettings.fromJson(
                Map<String, dynamic>.from(jsonDecode(row.settings) as Map),
              );
        return settings.copyWith(hostRules: await rulesDao.hostRules());
      });

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
    var hostsChanged = false;
    for (final rule in previous.hostRules) {
      final binding = rule.hostBinding!;
      if (binding.legacy) continue;
      if (binding.profileId != null && !profiles.contains(binding.profileId)) {
        await rulesDao.delRules([rule.id]);
        hostsChanged = true;
        continue;
      }
      final targets = keep(binding.targets);
      if (targets.length != binding.targets.length) {
        hostsChanged = true;
        await (update(rules)..where((t) => t.id.equals(rule.id))).write(
          RulesCompanion(
            hostBinding: Value(jsonEncode(binding.copyWith(targets: targets))),
          ),
        );
      }
    }
    if (next != previous || hostsChanged) await writeApplicationRouting(next);
  }
}
