import 'dart:io';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import '../helpers/test_policy_drafts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  setUp(() async {
    db = Database(NativeDatabase.memory());
    await db.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
  });
  tearDown(() => db.close());

  for (final keepTable in [false, true]) {
    test(
      'schema12 to13 preserves unknown rows; existing table: $keepTable',
      () async {
        final root = await Directory.systemTemp.createTemp('policy-schema12-');
        try {
          final file = File('${root.path}/db.sqlite');
          final current = Database(NativeDatabase(file));
          await current.profilesDao.putAll([draftTestProfile(4).toCompanion()]);
          await current.profilePolicySelectionsDao.compareAndWrite(
            4,
            expected: null,
            selection: const ProfilePolicySelection(
              profileId: 4,
              rawContent: '{"selectionVersion":99}',
            ),
          );
          await current.close();
          final sql = sqlite3.open(file.path);
          if (!keepTable) sql.execute('DROP TABLE profile_policy_selections');
          sql.execute('PRAGMA user_version = 12');
          sql.close();
          final upgraded = Database(NativeDatabase(file));
          try {
            expect((await upgraded.profilesDao.query().get()).single.id, 4);
            final rows = await upgraded.profilePolicySelectionsDao
                .query()
                .get();
            expect(rows, hasLength(keepTable ? 1 : 0));
            if (keepTable) {
              expect(rows.single.rawContent, '{"selectionVersion":99}');
            }
            expect(
              (await upgraded.customSelect('PRAGMA user_version').getSingle())
                  .data
                  .values
                  .single,
              13,
            );
          } finally {
            await upgraded.close();
          }
        } finally {
          await root.delete(recursive: true);
        }
      },
    );
  }

  Future<ProfilePolicySelection?> load() =>
      db.profilePolicySelectionsDao.query(1).getSingleOrNull();

  test(
    'CAS distinguishes absent row from present null; same pair is allowed',
    () async {
      const blocked = ProfilePolicySelection(profileId: 1);
      final dao = db.profilePolicySelectionsDao;
      expect(
        await dao.compareAndWrite(1, expected: null, selection: blocked),
        PolicyDraftWriteResult.saved,
      );
      var revoked = 0;
      expect(
        await dao.compareAndWrite(
          1,
          expected: null,
          selection: const ProfilePolicySelection(
            profileId: 1,
            rawContent: 'stale',
          ),
          beforeWrite: () async => revoked++,
        ),
        PolicyDraftWriteResult.conflict,
      );
      expect(revoked, 0);
      expect((await load())!.rawContent, isNull);
      expect(
        await dao.compareAndWrite(
          1,
          expected: blocked,
          selection: blocked,
          beforeWrite: () async => revoked++,
        ),
        PolicyDraftWriteResult.saved,
      );
      expect(revoked, 0);
      expect(
        await dao.compareAndWrite(
          1,
          expected: blocked,
          selection: null,
          beforeWrite: () async => revoked++,
        ),
        PolicyDraftWriteResult.saved,
      );
      expect(revoked, 1);
      expect(await load(), isNull);
    },
  );

  test(
    'failed invalidation preserves exact selection; profile deletion cascades',
    () async {
      const original = ProfilePolicySelection(
        profileId: 1,
        rawContent: 'unknown synthetic',
      );
      final dao = db.profilePolicySelectionsDao;
      await dao.compareAndWrite(1, expected: null, selection: original);
      await expectLater(
        dao.compareAndWrite(
          1,
          expected: original,
          selection: null,
          beforeWrite: () async => throw StateError('synthetic failure'),
        ),
        throwsStateError,
      );
      expect((await load())!.sameValue(original), isTrue);
      await db.deleteProfile(1);
      expect(await load(), isNull);
      expect(
        await dao.compareAndWrite(1, expected: null, selection: original),
        PolicyDraftWriteResult.missingProfile,
      );
    },
  );

  test('local protection only inserts null for live missing rows', () async {
    const unknown = ProfilePolicySelection(
      profileId: 1,
      rawContent: '{"selectionVersion":99}',
    );
    await db.profilePolicySelectionsDao.compareAndWrite(
      1,
      expected: null,
      selection: unknown,
    );
    await db.profilesDao.putAll([draftTestProfile(2).toCompanion()]);
    await db.profilePolicySelectionsDao.requireSelections({1, 2, 3});
    expect((await load())!.sameValue(unknown), isTrue);
    expect(
      (await db.profilePolicySelectionsDao.query(2).getSingle()).rawContent,
      isNull,
    );
    expect(
      await db.profilePolicySelectionsDao.query(3).getSingleOrNull(),
      isNull,
    );
  });
}
