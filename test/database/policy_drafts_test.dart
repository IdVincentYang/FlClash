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

  Future<PolicyDraftWriteResult> save(String? expected, String? raw) => db
      .profilePolicyDraftsDao
      .compareAndWrite(1, expectedRaw: expected, rawContent: raw);
  Future<String?> stored() async =>
      (await db.profilePolicyDraftsDao.query(1).getSingleOrNull())?.rawContent;

  test(
    'ordinary profile writes preserve exact opaque and incomplete drafts',
    () async {
      for (final raw in [
        'not JSON; synthetic secret',
        '{"draftVersion":99}',
        PolicyDraftDocument.empty().encode(),
      ]) {
        final previous = await stored();
        expect(await save(previous, raw), PolicyDraftWriteResult.saved);
        await db.profilesDao.putAll([
          draftTestProfile(1).copyWith(label: 'Renamed').toCompanion(5),
        ]);
        expect(await stored(), raw);
      }
    },
  );

  test(
    'different content conflicts and deleting a profile cascades without resurrection',
    () async {
      expect(await save(null, 'first'), PolicyDraftWriteResult.saved);
      expect(await save(null, 'stale'), PolicyDraftWriteResult.conflict);
      expect(await stored(), 'first');
      await db.deleteProfile(1);
      expect(await stored(), isNull);
      expect(await save(null, 'new'), PolicyDraftWriteResult.missingProfile);
    },
  );

  test(
    'CAS allows same raw, same-value restore, absent row and same-value recreation',
    () async {
      expect(await save(null, null), PolicyDraftWriteResult.saved);
      expect(await save(null, 'same'), PolicyDraftWriteResult.saved);
      await db.restore(
        [draftTestProfile(1)],
        [],
        [],
        [],
        [],
        policyDrafts: [
          const ProfilePolicyDraft(profileId: 1, rawContent: 'same'),
        ],
      );
      expect(await save('same', 'next'), PolicyDraftWriteResult.saved);
      expect(await save('next', null), PolicyDraftWriteResult.saved);
      expect(await save(null, 'next'), PolicyDraftWriteResult.saved);
      expect(await save('next', 'final'), PolicyDraftWriteResult.saved);
    },
  );

  test(
    'merge absent preserves, override absent clears, opaque incoming replaces',
    () async {
      await save(null, 'local');
      await db.restore([draftTestProfile(1)], [], [], [], []);
      expect(await stored(), 'local');
      await db.restore(
        [draftTestProfile(1)],
        [],
        [],
        [],
        [],
        policyDrafts: [
          const ProfilePolicyDraft(
            profileId: 1,
            rawContent: '{"draftVersion":999}',
          ),
        ],
      );
      expect(await stored(), '{"draftVersion":999}');
      await db.restore([draftTestProfile(1)], [], [], [], [], isOverride: true);
      expect(await stored(), isNull);
    },
  );

  test(
    'empty entities preserve rows even for override and still call beforeCommit',
    () async {
      await save(null, 'local');
      var called = 0;
      await db.restore(
        [],
        [],
        [],
        [],
        [],
        isOverride: true,
        beforeCommit: () async {
          called++;
        },
      );
      expect(called, 1);
      expect(await stored(), 'local');
      expect(await db.profilesDao.query().get(), hasLength(1));
    },
  );

  test(
    'orphan and duplicate drafts reject before transaction or callback',
    () async {
      await save(null, 'local');
      for (final drafts in [
        [const ProfilePolicyDraft(profileId: 2, rawContent: 'orphan')],
        [
          const ProfilePolicyDraft(profileId: 1, rawContent: 'a'),
          const ProfilePolicyDraft(profileId: 1, rawContent: 'b'),
        ],
      ]) {
        var called = false;
        await expectLater(
          db.restore(
            [draftTestProfile(1)],
            [],
            [],
            [],
            [],
            policyDrafts: drafts,
            beforeCommit: () async {
              called = true;
            },
          ),
          throwsA(isA<PolicyDraftRestoreException>()),
        );
        expect(called, isFalse);
        expect(await stored(), 'local');
      }
      await expectLater(
        db.restore(
          [],
          [],
          [],
          [],
          [],
          policyDrafts: [
            const ProfilePolicyDraft(
              profileId: 1,
              rawContent: 'target-only orphan',
            ),
          ],
        ),
        throwsA(isA<PolicyDraftRestoreException>()),
      );
    },
  );

  test('beforeCommit failure rolls profile and draft back together', () async {
    await save(null, 'local');
    await expectLater(
      db.restore(
        [draftTestProfile(1).copyWith(label: 'replaced')],
        [],
        [],
        [],
        [],
        isOverride: true,
        policyDrafts: [
          const ProfilePolicyDraft(profileId: 1, rawContent: 'incoming'),
        ],
        beforeCommit: () async => throw StateError('synthetic failure'),
      ),
      throwsStateError,
    );
    expect(await stored(), 'local');
    expect(
      (await db.profilesDao.query().get()).single.label,
      'Synthetic profile 1',
    );
  });

  for (final keepTable in [false, true]) {
    test(
      'schema11 to12 preserves profile; existing new table: $keepTable',
      () async {
        final root = await Directory.systemTemp.createTemp('policy-schema11-');
        try {
          final file = File('${root.path}/db.sqlite');
          final current = Database(NativeDatabase(file));
          await current.profilesDao.putAll([draftTestProfile(4).toCompanion()]);
          await current.close();
          final sql = sqlite3.open(file.path);
          if (!keepTable) sql.execute('DROP TABLE profile_policy_drafts');
          sql.execute('PRAGMA user_version = 11');
          sql.close();
          final upgraded = Database(NativeDatabase(file));
          try {
            expect((await upgraded.profilesDao.query().get()).single.id, 4);
            expect(
              await upgraded.profilePolicyDraftsDao.query().get(),
              isEmpty,
            );
            expect(
              (await upgraded.customSelect('PRAGMA user_version').getSingle())
                  .data
                  .values
                  .single,
              12,
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
}
