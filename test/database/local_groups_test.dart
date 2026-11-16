import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Future<sqlite.Database> legacySchema(int version) async {
  final raw = sqlite.sqlite3.openInMemory();
  final seed = Database(
    NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
  );
  await seed.customSelect('SELECT 1').get();
  await seed.close();
  raw.execute('DROP TABLE application_routing_libraries');
  raw.execute('DROP TABLE global_group_libraries');
  raw.execute('ALTER TABLE rules DROP COLUMN host_binding');
  if (version == 13) {
    raw.execute('ALTER TABLE profiles DROP COLUMN local_groups');
  }
  raw.execute('PRAGMA user_version = $version');
  final tables = raw
      .select("SELECT name FROM sqlite_master WHERE type='table'")
      .map((row) => row['name']);
  expect(
    tables,
    containsAll(['profiles', 'scripts', 'rules', 'profile_rule_mapping']),
  );
  expect(tables, isNot(contains('global_group_libraries')));
  expect(tables, isNot(contains('application_routing_libraries')));
  expect(
    raw.select('PRAGMA table_info(rules)').map((row) => row['name']),
    isNot(contains('host_binding')),
  );
  expect(
    raw.select('PRAGMA table_info(profiles)').map((row) => row['name']),
    version == 13 ? isNot(contains('local_groups')) : contains('local_groups'),
  );
  return raw;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'schema 13 gains an empty local group field without losing profiles',
    () async {
      final raw = await legacySchema(13);
      raw.execute(
        '''INSERT INTO profiles(id,label,url,overwrite_type,auto_update_duration_millis,auto_update,selected_map,unfold_set)
      VALUES(1,'Fixture','https://example.invalid/profile','standard',3600000,1,'{}','[]')''',
      );
      final store = Database(NativeDatabase.opened(raw));
      addTearDown(store.close);
      final profile = (await store.profilesDao.query().get()).single;
      expect(profile.label, 'Fixture');
      expect(profile.localGroups, isEmpty);
      expect(
        raw.select('PRAGMA user_version').single.values.single,
        store.schemaVersion,
      );
    },
  );

  test(
    'schema 14 migrates legacy groups globally without rewriting selections or references',
    () async {
      final raw = await legacySchema(14);
      const legacy = LocalProxyGroup(
        id: 7,
        name: 'Mine',
        nodes: ['a'],
        parents: ['Main'],
      );
      for (final id in [1, 2]) {
        raw.execute(
          '''INSERT INTO profiles(id,label,url,overwrite_type,auto_update_duration_millis,auto_update,selected_map,unfold_set,local_groups)
        VALUES(?,?,'','standard',3600000,1,?,'[]',?)''',
          [
            id,
            'Profile $id',
            jsonEncode({'Main': 'Mine'}),
            jsonEncode([
              legacy.copyWith(parents: [id == 1 ? 'Main' : 'Media']),
            ]),
          ],
        );
      }
      final store = Database(NativeDatabase.opened(raw));
      addTearDown(store.close);
      final profiles = await store.profilesDao.query().get();
      final library = await store.readGlobalGroups();
      expect(library, hasLength(1));
      expect(library.single.global, true);
      expect(library.single.entrances, isEmpty);
      expect(profiles.map((profile) => profile.localGroups.single.entrances), [
        {'Main'},
        {'Media'},
      ]);
      expect(
        profiles.every((profile) => profile.selectedMap['Main'] == 'Mine'),
        true,
      );
      await store.initializeGlobalGroups();
      expect(await store.readGlobalGroups(), library);
    },
  );

  test(
    'profile snapshots stay separate while the global library survives profile deletion',
    () async {
      final store = Database(NativeDatabase.memory());
      addTearDown(store.close);
      final first = Profile.normal(label: 'First').copyWith(
        localGroups: [
          const LocalProxyGroup(
            id: 7,
            name: 'Mine',
            nodes: ['a'],
            enabled: false,
          ),
        ],
      );
      final second = Profile.normal(label: 'Second');
      await store.profilesDao.putAll([
        first.toCompanion(),
        second.toCompanion(),
      ]);
      await store.writeGlobalGroups(first.localGroups);
      final rows = await store.profilesDao.query().get();
      expect(
        rows.firstWhere((row) => row.id == first.id).localGroups,
        first.localGroups,
      );
      expect(
        rows.firstWhere((row) => row.id == second.id).localGroups,
        isEmpty,
      );
      expect(
        Profile.fromJson(jsonDecode(jsonEncode(first)) as Map<String, dynamic>),
        first,
      );
      await store.deleteProfile(first.id);
      expect(await store.readGlobalGroups(), first.localGroups);
    },
  );

  test(
    'global-only backups restore without a profile and replace atomically',
    () async {
      final store = Database(NativeDatabase.memory());
      addTearDown(store.close);
      const group = LocalProxyGroup(id: 7, name: 'Global', nodes: ['a']);
      await store.restore([], [], [], [], [], globalGroups: [group]);
      expect((await store.readGlobalGroups()).single.name, 'Global');
      await expectLater(
        store.restore(
          [],
          [],
          [],
          [],
          [],
          globalGroups: [],
          isOverride: true,
          beforeCommit: () async => throw StateError('cancelled'),
        ),
        throwsStateError,
      );
      expect((await store.readGlobalGroups()).single.name, 'Global');
      await store.restore(
        [],
        [],
        [],
        [],
        [],
        globalGroups: [],
        isOverride: true,
      );
      expect(await store.readGlobalGroups(), isEmpty);
    },
  );
}
