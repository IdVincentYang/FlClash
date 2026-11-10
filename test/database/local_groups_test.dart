import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Database;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'schema 13 gains an empty local group field without losing profiles',
    () async {
      final raw = sqlite3.openInMemory();
      raw.execute('''CREATE TABLE profiles (
      id INTEGER PRIMARY KEY NOT NULL, label TEXT NOT NULL, current_group_name TEXT,
      url TEXT NOT NULL, last_update_date INTEGER, overwrite_type TEXT NOT NULL,
      script_id INTEGER, match_target TEXT, auto_update_duration_millis INTEGER NOT NULL,
      subscription_info TEXT, auto_update INTEGER NOT NULL, selected_map TEXT NOT NULL,
      unfold_set TEXT NOT NULL, request_mode TEXT NOT NULL DEFAULT 'auto', request_proxy TEXT, "order" INTEGER
    )''');
      raw.execute(
        '''INSERT INTO profiles(id,label,url,overwrite_type,auto_update_duration_millis,auto_update,selected_map,unfold_set)
      VALUES(1,'Fixture','https://example.invalid/profile','standard',3600000,1,'{}','[]')''',
      );
      raw.execute('PRAGMA user_version = 13');
      final store = Database(NativeDatabase.opened(raw));
      addTearDown(store.close);
      final profile = (await store.profilesDao.query().get()).single;
      expect(profile.label, 'Fixture');
      expect(profile.localGroups, isEmpty);
      expect(raw.select('PRAGMA user_version').single.values.single, 14);
    },
  );

  test(
    'local group definitions remain attached to their own profile',
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
    },
  );
}
