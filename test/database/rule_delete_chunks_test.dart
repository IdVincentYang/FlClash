import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Database store;
  setUp(() {
    store = Database(NativeDatabase.memory());
  });
  tearDown(() => store.close());

  Future<List<int>> seed({required bool deletedHost}) async {
    await store.profiles.put(
      const Profile(id: 1, autoUpdateDuration: Duration.zero).toCompanion(),
    );
    final rules = List.generate(
      2100,
      (i) => Rule(
        id: i + 1,
        ruleAction: RuleAction.DOMAIN,
        content: 'node$i.test',
        ruleTarget: 'DIRECT',
        hostBinding: deletedHost && i == 1800 ? const HostRuleBinding() : null,
      ),
    );
    await store.batch(
      (batch) => store.rulesDao.setCustomRulesWithBatch(1, batch, rules),
    );
    await store.rulesDao.putGlobalRule(
      const Rule(
        id: 9000,
        ruleAction: RuleAction.DOMAIN,
        content: 'untouched.test',
        ruleTarget: 'DIRECT',
        hostBinding: HostRuleBinding(),
      ),
    );
    return rules.map((rule) => rule.id).toList();
  }

  for (final deletedHost in [false, true]) {
    test('chunked deletion stamps only a deleted Host: $deletedHost', () async {
      final ids = await seed(deletedHost: deletedHost);
      final before = await store.readApplicationRouting();
      await store.rulesDao.delRules([...ids, 8000]);
      final after = await store.readApplicationRouting();
      expect((await store.select(store.rules).get()).map((row) => row.id), [
        9000,
      ]);
      expect(after.hostRules.map((row) => row.id), [9000]);
      expect(after.revision, before.revision + (deletedHost ? 1 : 0));
      expect(await store.rulesDao.profileCustomRulesCount(1).getSingle(), 0);
      expect((await store.profilesDao.query().get()).single.id, 1);
      await store.rulesDao.delRules([8000]);
      await store.rulesDao.delRules([]);
      expect(await store.readApplicationRouting(), after);
    });
  }

  for (final failure in ['delete', 'revision']) {
    test('$failure failure rolls back all chunks and routing metadata', () async {
      final ids = await seed(deletedHost: true);
      final before = await store.readApplicationRouting();
      await store.customStatement(
        failure == 'delete'
            ? "CREATE TRIGGER fail_delete BEFORE DELETE ON rules WHEN OLD.id = 1000 BEGIN SELECT RAISE(ABORT, 'synthetic deletion failure'); END"
            : "CREATE TRIGGER fail_revision BEFORE UPDATE ON application_routing_libraries BEGIN SELECT RAISE(ABORT, 'synthetic revision failure'); END",
      );
      await expectLater(
        store.rulesDao.delRules(ids),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.message,
            'message',
            contains('synthetic'),
          ),
        ),
      );
      expect((await store.select(store.rules).get()), hasLength(2101));
      expect(await store.rulesDao.profileCustomRulesCount(1).getSingle(), 2100);
      expect(await store.readApplicationRouting(), before);
    });
  }
}
