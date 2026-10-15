import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

Future<File> schema10(Directory directory) async {
  final file = File('${directory.path}/schema10.sqlite');
  final current = db.Database(NativeDatabase(file));
  await current.customSelect('SELECT 1').get();
  await current.close();
  final raw = sqlite3.open(file.path);
  try {
    raw.execute('DROP TABLE profiles');
    raw.execute('DROP TABLE scripts');
    raw.execute('''CREATE TABLE profiles (
      id INTEGER NOT NULL PRIMARY KEY, label TEXT NOT NULL, current_group_name TEXT,
      url TEXT NOT NULL, last_update_date INTEGER, overwrite_type TEXT NOT NULL,
      script_id INTEGER, match_target TEXT, auto_update_duration_millis INTEGER NOT NULL,
      subscription_info TEXT, auto_update INTEGER NOT NULL, selected_map TEXT NOT NULL,
      unfold_set TEXT NOT NULL, "order" INTEGER
    )''');
    raw.execute('''CREATE TABLE scripts (
      id INTEGER NOT NULL PRIMARY KEY, label TEXT NOT NULL, last_update_time INTEGER NOT NULL,
      url TEXT, "order" INTEGER
    )''');
    raw.execute(
      "INSERT INTO profiles(id,label,url,overwrite_type,auto_update_duration_millis,auto_update,selected_map,unfold_set) VALUES(1,'Old profile','http://127.0.0.1/sub','standard',60000,1,'{}','[]')",
    );
    raw.execute(
      "INSERT INTO scripts(id,label,last_update_time,url) VALUES(2,'Old script',1700000000,'http://127.0.0.1/script')",
    );
    raw.execute('PRAGMA user_version = 10');
    for (final table in ['profiles', 'scripts']) {
      final columns = raw
          .select('PRAGMA table_info($table)')
          .map((row) => row['name']);
      expect(columns, isNot(contains('request_mode')));
      expect(columns, isNot(contains('request_proxy')));
    }
  } finally {
    raw.close();
  }
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('request-schema10-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('real schema10 without request columns migrates rows to Auto', () async {
    final file = await schema10(directory);
    final database = db.Database(NativeDatabase(file));
    try {
      final profile = (await database.profilesDao.query().get()).single;
      final script = (await database.scriptsDao.query().get()).single;
      expect(profile.requestMode, RequestMode.auto);
      expect(profile.requestProxy, isNull);
      expect(profile.url, 'http://127.0.0.1/sub');
      expect(script.requestMode, RequestMode.auto);
      expect(script.requestProxy, isNull);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        11,
      );
    } finally {
      await database.close();
    }
  });

  test(
    'old schema10 archive and DAV JSON restore their Auto defaults',
    () async {
      final file = await schema10(directory);
      final archive = '${directory.path}/old.zip';
      final oldDAV =
          const DAVProps(
              uri: 'http://127.0.0.1/dav',
              user: 'synthetic',
              password: 'synthetic',
              fileName: 'old.zip',
            ).toJson()
            ..remove('requestMode')
            ..remove('requestProxy');
      await writeBackupArchive(
        archivePath: archive,
        configMap: {'version': 1, 'davProps': oldDAV},
        databaseSnapshotPath: file.path,
        homeDirPath: directory.path,
        entries: [],
      );
      final restored = await readBackupArchive(
        archivePath: archive,
        stagingDirPath: '${directory.path}/staging',
      );
      expect(restored.profiles.single.requestMode, RequestMode.auto);
      expect(restored.scripts.single.requestMode, RequestMode.auto);
      expect(
        Config.fromJson(restored.configMap!).davProps?.requestMode,
        RequestMode.auto,
      );
    },
  );
}
