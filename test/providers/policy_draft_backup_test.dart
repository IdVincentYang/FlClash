import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import '../helpers/test_policy_drafts.dart';
import '../helpers/failing_preferences.dart';
import '../helpers/test_config_state.dart';

class _NoPublishSetup extends SetupAction {
  int applies = 0;
  @override
  void build() {}
  @override
  Future<bool> applyProfile({bool silence = false, bool force = false}) async {
    applies++;
    return true;
  }
}

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

  test(
    'override protects a previously managed noncurrent profile with a null row',
    () async {
      final target = await newDb();
      await target.profilesDao.putAll([
        draftTestProfile(1).toCompanion(),
        draftTestProfile(2).toCompanion(),
      ]);
      await target.profilePolicySelectionsDao.compareAndWrite(
        2,
        expected: null,
        selection: const ProfilePolicySelection(
          profileId: 2,
          rawContent: 'opaque selection',
        ),
      );
      final c = ProviderContainer(
        overrides: buildConfigOverrides(
          const Config(
            themeProps: defaultThemeProps,
            currentProfileId: 1,
            appSettingProps: AppSettingProps(
              restoreStrategy: RestoreStrategy.override,
            ),
          ),
        ),
      );
      containers.add(c);
      c.listen(configProvider, (_, _) {});
      await action(c).applyRestore(
        MigrationData(profiles: [draftTestProfile(1), draftTestProfile(2)]),
        RestoreOption.onlyProfiles,
      );
      final protected = await target.profilePolicySelectionsDao
          .query(2)
          .getSingle();
      expect(protected.rawContent, isNull);
      expect(
        await target.profilePolicySelectionsDao.query(1).getSingleOrNull(),
        isNull,
      );
      expect(c.read(currentProfileIdProvider), 1);
    },
  );

  for (final compensation in [
    PreferenceWrite.pass,
    PreferenceWrite.fail,
    PreferenceWrite.throwError,
  ]) {
    test(
      'restore fails after selection protection and compensates: $compensation',
      () async {
        final target = await newDb();
        await seed(target, 'original draft');
        await target.profilesDao.putAll([draftTestProfile(2).toCompanion()]);
        for (final id in [1, 2]) {
          await target.profilePolicySelectionsDao.compareAndWrite(
            id,
            expected: null,
            selection: ProfilePolicySelection(
              profileId: id,
              rawContent: 'original selection $id',
            ),
          );
          File(await appPath.getProfilePath('$id'))
            ..createSync(recursive: true)
            ..writeAsStringSync('original file $id');
        }
        const previous = Config(
          themeProps: defaultThemeProps,
          currentProfileId: 1,
          appSettingProps: AppSettingProps(
            restoreStrategy: RestoreStrategy.override,
            testUrl: 'https://previous.test',
          ),
        );
        final incoming = previous.copyWith(
          appSettingProps: previous.appSettingProps.copyWith(
            testUrl: 'https://synthetic-preference-secret.test',
          ),
        );
        final c = ProviderContainer(
          overrides: [
            ...buildConfigOverrides(previous),
            initProvider.overrideWithBuild((_, _) => true),
            setupActionProvider.overrideWith(_NoPublishSetup.new),
            configStateProvider.overrideWith(TestConfigState.new),
          ],
        );
        containers.add(c);
        c.listen(configProvider, (_, _) {});
        final staging = Directory(
          join(root.path, 'failed-selection-${next++}'),
        );
        for (final id in [1, 2]) {
          File(BackupEntries.resolve(staging.path, BackupEntries.profile(id)))
            ..createSync(recursive: true)
            ..writeAsStringSync('incoming file $id');
        }
        await preferences.isInit;
        await preferences.saveConfig(previous);
        await request.clearPartialCommit();
        final originalCompleter = preferences.sharedPreferencesCompleter;
        final actual = (await originalCompleter.future)!;
        var sawProtectedTransaction = false;
        final failing = FailingPreferences(
          actual,
          [PreferenceWrite.failAfterWrite, compensation],
          beforeWrite: (attempt) async {
            if (attempt != 0) return;
            expect(
              (await target.profilePolicySelectionsDao.query(2).getSingle())
                  .rawContent,
              isNull,
            );
            expect(
              (await target.profilePolicySelectionsDao.query(1).getSingle())
                  .rawContent,
              'incoming selection',
            );
            expect(
              (await target.profilesDao.query().get()).map((p) => p.label),
              ['incoming 1', 'incoming 2'],
            );
            for (final id in [1, 2]) {
              expect(
                await File(await appPath.getProfilePath('$id')).readAsString(),
                'incoming file $id',
              );
            }
            sawProtectedTransaction = true;
          },
        );
        preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
          ..complete(failing);
        try {
          await expectLater(
            action(c).applyRestore(
              MigrationData(
                profiles: [
                  for (final id in [1, 2])
                    draftTestProfile(id).copyWith(label: 'incoming $id'),
                ],
                policySelections: const [
                  ProfilePolicySelection(
                    profileId: 1,
                    rawContent: 'incoming selection',
                  ),
                ],
                configMap:
                    jsonDecode(jsonEncode(incoming)) as Map<String, dynamic>,
              ),
              RestoreOption.all,
              stagingDirPath: staging.path,
            ),
            throwsA(
              isA<RequestUnavailable>()
                  .having(
                    (e) => e.code,
                    'code',
                    compensation == PreferenceWrite.pass
                        ? 'preferences_save_failed'
                        : 'request_partial_commit',
                  )
                  .having(
                    (e) => e.toString().contains('synthetic-preference-secret'),
                    'contains secret',
                    isFalse,
                  ),
            ),
          );
          expect(sawProtectedTransaction, isTrue);
          expect(failing.writes, 2);
          expect((await target.profilesDao.query().get()).map((p) => p.label), [
            'Synthetic profile 1',
            'Synthetic profile 2',
          ]);
          expect(
            (await target.profilePolicyDraftsDao.query(1).getSingle())
                .rawContent,
            'original draft',
          );
          for (final id in [1, 2]) {
            expect(
              (await target.profilePolicySelectionsDao.query(id).getSingle())
                  .rawContent,
              'original selection $id',
            );
            expect(
              await File(await appPath.getProfilePath('$id')).readAsString(),
              'original file $id',
            );
          }
          expect(c.read(configProvider), previous);
          expect(
            (c.read(setupActionProvider.notifier) as _NoPublishSetup).applies,
            0,
          );
          final partial = compensation != PreferenceWrite.pass;
          expect(request.partialCommit, partial);
          expect(
            await File(
              join(await appPath.homeDirPath, 'request-recovery-required'),
            ).exists(),
            partial,
          );
          expect(
            (jsonDecode(actual.getString(configKey)!)
                as Map)['appSettingProps']['testUrl'],
            partial
                ? incoming.appSettingProps.testUrl
                : previous.appSettingProps.testUrl,
          );
        } finally {
          preferences.sharedPreferencesCompleter = originalCompleter;
          await request.clearPartialCommit();
        }
      },
    );
  }

  test(
    'config-only restore protects its surviving new target before settings publication',
    () async {
      final target = await newDb();
      await target.profilesDao.putAll([
        draftTestProfile(1).toCompanion(),
        draftTestProfile(2).toCompanion(),
      ]);
      await target.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: null,
        selection: const ProfilePolicySelection(
          profileId: 1,
          rawContent: '{"selectionVersion":99}',
        ),
      );
      final c = ProviderContainer(
        overrides: buildConfigOverrides(
          const Config(themeProps: defaultThemeProps, currentProfileId: 1),
        ),
      );
      containers.add(c);
      c.listen(configProvider, (_, _) {});
      await action(c).applyRestore(
        MigrationData(
          configMap:
              jsonDecode(
                    jsonEncode(
                      const Config(
                        themeProps: defaultThemeProps,
                        currentProfileId: 2,
                      ),
                    ),
                  )
                  as Map<String, dynamic>,
        ),
        RestoreOption.all,
      );
      expect(c.read(currentProfileIdProvider), 2);
      expect(
        (await target.profilePolicySelectionsDao.query(2).getSingle())
            .rawContent,
        isNull,
      );
      expect(
        (await target.profilePolicySelectionsDao.query(1).getSingle())
            .rawContent,
        '{"selectionVersion":99}',
      );
    },
  );

  test(
    'empty and compatible restores preserve opaque selected content; VACUUM includes it',
    () async {
      final target = await newDb();
      await target.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
      const row = ProfilePolicySelection(
        profileId: 1,
        rawContent: 'synthetic-selection-secret',
      );
      await target.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: null,
        selection: row,
      );
      final c = container();
      final a = action(c);
      await a.applyRestore(const MigrationData(), RestoreOption.onlyProfiles);
      await a.applyRestore(
        MigrationData(profiles: [draftTestProfile(1)]),
        RestoreOption.onlyProfiles,
      );
      expect(
        (await target.profilePolicySelectionsDao.query(1).getSingle())
            .sameValue(row),
        isTrue,
      );
      expect(await a.hasPolicyDrafts(), isTrue);
      await expectLater(
        archive(a, confirmed: false),
        throwsA(isA<MessageException>()),
      );
      final zip = await archive(a);
      final parsed = await restoreTask((
        archivePath: zip,
        stagingDirPath: join(root.path, 'selected-staging${next++}'),
      ));
      expect(parsed.policySelections.single.sameValue(row), isTrue);
    },
  );
}
