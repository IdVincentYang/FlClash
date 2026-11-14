import 'dart:io';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'host records share Rules storage, stream updates and prune only removed profile bindings',
    () async {
      final store = Database(NativeDatabase.memory());
      addTearDown(store.close);
      await store.profilesDao.setAll([
        const Profile(id: 1, autoUpdateDuration: Duration(hours: 1)),
        const Profile(id: 2, autoUpdateDuration: Duration(hours: 1)),
      ]);
      final updates = <ApplicationRoutingSettings>[];
      final watch = store.watchApplicationRouting().listen(updates.add);
      addTearDown(watch.cancel);
      final host = hostRuleTemplate('example.test').copyWith(
        id: 123,
        ruleTarget: 'Mine',
        hostBinding: const HostRuleBinding(
          packageName: 'a',
          targets: {
            1: ApplicationRouteTarget(
              name: 'Mine',
              kind: ApplicationTargetKind.group,
            ),
            2: ApplicationRouteTarget(
              name: 'Other',
              kind: ApplicationTargetKind.group,
            ),
          },
        ),
      );
      await store.rulesDao.putGlobalRule(host);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await store.rulesDao.queryGlobalAddedRules().get(), [host]);
      expect(await store.rulesDao.queryAddedRules(1).get(), isEmpty);
      expect(updates.last.hostRules, [host]);
      final before = await store.readApplicationRouting();
      await store.deleteProfile(1);
      final after = await store.readApplicationRouting();
      expect(after.hostRules.single.hostBinding!.targets.keys, [2]);
      expect(after.revision, greaterThan(before.revision));
      await store.rulesDao.delRules([123]);
      expect((await store.readApplicationRouting()).hostRules, isEmpty);
    },
  );

  test(
    'schema 16 upgrade preserves old rules and promotes one record in place',
    () async {
      final directory = Directory.systemTemp.createTempSync('host-migration-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/state.sqlite');
      var store = Database(NativeDatabase(file));
      await store.profilesDao.setAll([
        const Profile(id: 7, autoUpdateDuration: Duration(hours: 1)),
      ]);
      const old = Rule(id: 123, content: 'example.test', ruleTarget: 'DIRECT');
      await store.rulesDao.putGlobalRule(old);
      await store.close();
      final raw = sqlite3.open(file.path);
      raw.execute('ALTER TABLE rules DROP COLUMN host_binding');
      raw.execute('PRAGMA user_version = 16');
      raw.close();
      store = Database(NativeDatabase(file));
      final migrated = await store.readApplicationRouting();
      expect(migrated.hostRules.single.hostBinding!.legacy, true);
      expect((await store.rulesDao.queryAddedRules(7).get()).single.id, 123);
      await store.rulesDao.putGlobalRule(
        migrated.hostRules.single.copyWith(
          hostBinding: const HostRuleBinding(),
        ),
      );
      expect(await store.rulesDao.queryAddedRules(7).get(), isEmpty);
      await store.rulesDao.putDisabledLink(7, 123);
      final disabled = await store.readApplicationRouting();
      expect(disabled.revision, greaterThan(migrated.revision));
      expect(
        compileApplicationRouting(disabled, 7).containsKey('hostRules'),
        false,
      );
      await store.rulesDao.delDisabledLink(7, 123);
      await store.close();
      store = Database(NativeDatabase(file));
      addTearDown(store.close);
      final restored = await store.readApplicationRouting();
      expect(restored.hostRules.single.id, 123);
      expect(restored.hostRules.single.hostBinding!.legacy, false);
      expect(
        (compileApplicationRouting(restored, 7)['hostRules'] as List)
            .single['target'],
        'DIRECT',
      );
    },
  );

  test('source IP rules stay in the ordinary override editor', () async {
    final store = Database(NativeDatabase.memory());
    addTearDown(store.close);
    await store.rulesDao.putGlobalRule(
      const Rule(
        id: 1,
        ruleAction: RuleAction.IP_CIDR,
        content: '192.0.2.1/32',
        ruleTarget: 'DIRECT',
        src: true,
      ),
    );
    expect((await store.readApplicationRouting()).hostRules, isEmpty);
    expect(await store.rulesDao.queryAddedRules(7).get(), hasLength(1));
  });

  test(
    'app settings survive reopening and profile deletion prunes only its bindings',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'application-routing-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/state.sqlite');
      var store = Database(NativeDatabase(file));
      await store.profilesDao.setAll([
        const Profile(id: 1, autoUpdateDuration: Duration(hours: 1)),
      ]);
      await store.profilesDao.setAll([
        const Profile(id: 2, autoUpdateDuration: Duration(hours: 1)),
      ]);
      const target = ApplicationRouteTarget(
        name: 'Mine',
        kind: ApplicationTargetKind.globalGroup,
        groupId: 8,
      );
      const rule = ApplicationRouteRule(
        packageName: 'app',
        enabled: true,
        useSharedTarget: false,
        targets: {1: target, 2: target},
      );
      final saved = await store.writeApplicationRouting(
        const ApplicationRoutingSettings(
          rules: {'app': rule},
          sharedTargets: {1: target, 2: target},
        ),
      );
      expect(saved.revision, 1);
      await store.close();
      store = Database(NativeDatabase(file));
      addTearDown(store.close);
      expect(await store.readApplicationRouting(), saved);
      await store.deleteProfile(1);
      final retained = await store.readApplicationRouting();
      expect(retained.rules['app']?.enabled, true);
      expect(retained.rules['app']?.targets.keys, [2]);
      expect(retained.sharedTargets.keys, [2]);
      expect(await store.profilesDao.query().get(), hasLength(1));
    },
  );
}
