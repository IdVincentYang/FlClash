import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import '../helpers/test_policy_drafts.dart';

class _NoMutationBackup extends BackupAction {
  @override
  Request get requestClient => throw StateError('must not start a mutation');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<Database> databases;
  late List<ProviderContainer> containers;
  var next = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'version': 1});
    await AppLocalizations.load(const Locale('en'));
    root = await Directory.systemTemp.createTemp('policy-backup-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() {
    databases = [];
    containers = [];
  });
  tearDown(() async {
    for (final container in containers) {
      container.dispose();
    }
    for (final db in databases) {
      await db.close();
    }
  });

  Future<Database> newDb() async {
    final db = Database(
      NativeDatabase(File(join(root.path, 'db${next++}.sqlite'))),
    );
    databases.add(db);
    database = db;
    await db.customSelect('SELECT 1').get();
    return db;
  }

  ProviderContainer container() {
    final c = ProviderContainer();
    containers.add(c);
    c.listen(configProvider, (_, _) {});
    return c;
  }

  BackupAction action(ProviderContainer c) =>
      c.read(backupActionProvider.notifier);
  Future<void> seed(Database db, String raw) async {
    await db.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
    await db.profilePolicyDraftsDao.compareAndWrite(
      1,
      expectedRaw: null,
      rawContent: raw,
    );
    File(await appPath.getProfilePath('1'))
      ..createSync(recursive: true)
      ..writeAsStringSync('rules: [MATCH,REJECT]');
  }

  Future<String> archive(BackupAction a, {bool confirmed = true}) async {
    final path = join(root.path, 'kept${next++}.zip');
    await a.backup((source) async {
      await File(source).copy(path);
      return true;
    }, policyDraftsConfirmed: confirmed);
    return path;
  }

  test(
    'real VACUUM ZIP parse applyRestore roundtrip into a second DB preserves credentials and ordering',
    () async {
      final source = await newDb();
      final raw = completePolicyDraft(credentials: true).encode();
      await seed(source, raw);
      final zip = await archive(action(container()));
      final target = await newDb();
      expect(
        await action(
          container(),
        ).restore(RestoreOption.onlyProfiles, (_) async => zip),
        isTrue,
      );
      final stored = (await target.profilePolicyDraftsDao.query().get()).single;
      expect(stored.rawContent, raw);
      expect(source, isNot(same(target)));
      final reopened = PolicyDraftDocument.decode(stored.rawContent);
      expect(reopened.rows('domainRules').map((r) => r['id']), [
        'wide',
        'exact',
        'local',
        'blocked',
      ]);
      expect(
        reopened.policy['proxies']['nodeA']['password'],
        'synthetic-password-🙂',
      );
    },
  );

  test(
    'unknown and damaged draft text is never decoded or replaced during real restore',
    () async {
      for (final raw in [
        '{"draftVersion":999,"future":"synthetic"}',
        'not JSON',
      ]) {
        final source = await newDb();
        await seed(source, raw);
        final zip = await archive(action(container()));
        final target = await newDb();
        await action(
          container(),
        ).restore(RestoreOption.onlyProfiles, (_) async => zip);
        expect(
          (await target.profilePolicyDraftsDao.query().get()).single.rawContent,
          raw,
        );
      }
    },
  );

  test(
    'precheck followed by insertion cannot deliver without confirmation; cancel is local cleanup',
    () async {
      final db = await newDb();
      final a = action(container());
      expect(await a.hasPolicyDrafts(), isFalse);
      await seed(db, completePolicyDraft().encode());
      var delivered = 0;
      await expectLater(
        a.backup((_) async {
          delivered++;
          return true;
        }),
        throwsA(isA<MessageException>()),
      );
      expect(delivered, 0);
      expect(
        root.listSync().whereType<Directory>().where(
          (d) => basename(d.path).startsWith('backup'),
        ),
        isEmpty,
      );
      expect(
        await a.backup((_) async {
          delivered++;
          return false;
        }, policyDraftsConfirmed: true),
        isFalse,
      );
      expect(delivered, 1);
      expect(
        root.listSync().whereType<Directory>().where(
          (d) => basename(d.path).startsWith('backup'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'snapshot inspection reads frozen state after live draft deletion',
    () async {
      final db = await newDb();
      await seed(db, 'synthetic');
      final folder = Directory(join(root.path, 'frozen${next++}'))
        ..createSync();
      final file = join(folder.path, backupDatabaseName);
      await db.customStatement('VACUUM INTO ?', [file]);
      await db.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: 'synthetic',
        rawContent: null,
      );
      expect(await db.profilePolicyDraftsDao.hasAny(), isFalse);
      expect(await backupSnapshotHasPolicyDrafts(file), isTrue);
    },
  );

  test(
    'real merge preserves absent draft while override clears it for a restored profile',
    () async {
      final source = await newDb();
      await source.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
      File(await appPath.getProfilePath('1'))
        ..createSync(recursive: true)
        ..writeAsStringSync('rules: []');
      final zip = await archive(action(container()), confirmed: false);
      for (final override in [false, true]) {
        final target = await newDb();
        await seed(target, 'target');
        final c = container();
        c
            .read(appSettingProvider.notifier)
            .update(
              (s) => s.copyWith(
                restoreStrategy: override
                    ? RestoreStrategy.override
                    : RestoreStrategy.compatible,
              ),
            );
        await action(c).restore(RestoreOption.onlyProfiles, (_) async => zip);
        expect(
          (await target.profilePolicyDraftsDao.query().get()).map(
            (d) => d.rawContent,
          ),
          override ? isEmpty : ['target'],
        );
      }
    },
  );

  test(
    'Config-only and valid empty DB archives both preserve entities under both strategies',
    () async {
      for (final withDb in [false, true]) {
        final zip = join(root.path, 'empty${next++}.zip');
        final config = utf8.encode(jsonEncode({'version': 1}));
        final encoder = ZipFileEncoder()..create(zip);
        encoder.addArchiveFile(ArchiveFile.bytes(configJsonName, config));
        if (withDb) {
          final empty = await newDb();
          final snapshot = join(root.path, 'empty${next++}.sqlite');
          await empty.customStatement('VACUUM INTO ?', [snapshot]);
          await encoder.addFile(File(snapshot), backupDatabaseName);
        }
        await encoder.close();
        for (final override in [false, true]) {
          final target = await newDb();
          await seed(target, 'preserved');
          final c = container();
          c
              .read(appSettingProvider.notifier)
              .update(
                (s) => s.copyWith(
                  restoreStrategy: override
                      ? RestoreStrategy.override
                      : RestoreStrategy.compatible,
                ),
              );
          await action(c).restore(RestoreOption.all, (_) async => zip);
          expect(
            (await target.profilePolicyDraftsDao.query().get())
                .single
                .rawContent,
            'preserved',
          );
          expect(await target.profilesDao.query().get(), hasLength(1));
        }
      }
    },
  );

  test(
    'future schema and orphan draft archives are rejected by actual parser',
    () async {
      for (final future in [false, true]) {
        final source = await newDb();
        await seed(source, 'source');
        final snapshot = join(root.path, 'invalid${next++}.sqlite');
        await source.customStatement('VACUUM INTO ?', [snapshot]);
        final raw = sqlite3.open(snapshot);
        if (future) {
          raw.execute('PRAGMA user_version = 99');
        } else {
          raw.execute(
            "INSERT INTO profile_policy_drafts(profile_id,raw_content) VALUES(99,'orphan')",
          );
        }
        raw.close();
        final zip = join(root.path, 'invalid${next++}.zip');
        await writeBackupArchive(
          archivePath: zip,
          configMap: {'version': 1},
          databaseSnapshotPath: snapshot,
          homeDirPath: root.path,
          entries: [],
        );
        await expectLater(
          readBackupArchive(
            archivePath: zip,
            stagingDirPath: join(root.path, 'stage${next++}'),
          ),
          throwsA(
            isA<BackupException>().having(
              (e) => e.failure,
              'failure',
              future ? BackupFailure.newerVersion : BackupFailure.invalid,
            ),
          ),
        );
      }
    },
  );

  test(
    'v0 archive is judged after legacy conversion, so nonempty profile restore follows existing override',
    () async {
      final target = await newDb();
      await seed(target, 'local draft');
      final zip = join(root.path, 'legacy${next++}.zip');
      final encoder = ZipFileEncoder()..create(zip);
      encoder.addArchiveFile(
        ArchiveFile.bytes(
          configJsonName,
          utf8.encode(
            jsonEncode({
              'version': 0,
              'profiles': [
                {
                  'id': 'legacy',
                  'label': 'Legacy profile',
                  'autoUpdateDuration': 0,
                },
              ],
            }),
          ),
        ),
      );
      encoder.addArchiveFile(
        ArchiveFile.bytes('profiles/legacy.yaml', utf8.encode('rules: []')),
      );
      await encoder.close();
      final c = container();
      c
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(restoreStrategy: RestoreStrategy.override));
      await action(c).restore(RestoreOption.onlyProfiles, (_) async => zip);
      expect(
        (await target.profilesDao.query().get()).single.label,
        'Legacy profile',
      );
      expect(await target.profilePolicyDraftsDao.query().get(), isEmpty);
    },
  );

  test(
    'real restore SQL failure rolls draft back and never exposes secret parameters',
    () async {
      final source = await newDb();
      await seed(source, completePolicyDraft(credentials: true).encode());
      final zip = await archive(action(container()));
      final target = await newDb();
      await seed(target, 'previous draft');
      await target.customStatement(
        "CREATE TRIGGER reject_draft BEFORE INSERT ON profile_policy_drafts BEGIN SELECT RAISE(ABORT,'synthetic-restore-secret'); END",
      );
      Object? failure;
      try {
        await action(
          container(),
        ).restore(RestoreOption.onlyProfiles, (_) async => zip);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<MessageException>());
      expect(failure.toString(), contains('Could not complete restore'));
      for (final secret in [
        'synthetic-restore-secret',
        'synthetic-password',
        'synthetic-user',
      ]) {
        expect(failure.toString(), isNot(contains(secret)));
      }
      expect(
        (await target.profilePolicyDraftsDao.query().get()).single.rawContent,
        'previous draft',
      );
    },
  );

  test(
    'invalid incoming draft relations reject before accessing request mutation',
    () async {
      final target = await newDb();
      await seed(target, 'preserved');
      final c = ProviderContainer(
        overrides: [backupActionProvider.overrideWith(_NoMutationBackup.new)],
      );
      containers.add(c);
      c.listen(configProvider, (_, _) {});
      await expectLater(
        action(c).applyRestore(
          const MigrationData(
            policyDrafts: [
              ProfilePolicyDraft(profileId: 1, rawContent: 'orphan data'),
            ],
          ),
          RestoreOption.onlyProfiles,
        ),
        throwsA(isA<MessageException>()),
      );
      expect(
        (await target.profilePolicyDraftsDao.query().get()).single.rawContent,
        'preserved',
      );
    },
  );
}
