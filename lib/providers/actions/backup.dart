part of '../action.dart';

typedef BackupDelivery = Future<bool> Function(String archivePath);

/// Returns the archive to restore, or null when the user backed out. A source
/// that downloads writes to [downloadPath], which is removed afterwards.
typedef BackupFetch = Future<String?> Function(String downloadPath);

@Riverpod(keepAlive: true)
class BackupAction extends _$BackupAction {
  @protected
  Request get requestClient => request;
  @override
  void build() {}

  Future<void> updateDAV(DAVProps? value) => requestClient.mutate(() async {
    final previous = ref.read(davSettingProvider);
    await requestClient.invalidate('dav');
    ref.read(davSettingProvider.notifier).update((_) => value);
    try {
      if (!await preferences.saveConfig(ref.read(configProvider))) {
        throw const RequestUnavailable('preferences_save_failed');
      }
    } catch (_) {
      ref.read(davSettingProvider.notifier).update((_) => previous);
      if (!await preferences.saveConfig(ref.read(configProvider))) {
        await requestClient.markPartialCommit();
      }
      rethrow;
    }
  });

  Future<bool> backup(BackupDelivery deliver) {
    return _withWorkDir((workDir) async {
      final archive = await requestClient.mutate(() => _createArchive(workDir));
      await RequestSession.current?.check();
      return deliver(archive);
    });
  }

  Future<bool> restore(RestoreOption option, BackupFetch fetch) {
    return _withWorkDir((workDir) async {
      final archivePath = await fetch(join(workDir, 'download.zip'));
      if (archivePath == null) {
        return false;
      }
      final stagingDirPath = join(workDir, 'staging');
      final MigrationData data;
      try {
        data = await restoreTask((
          archivePath: archivePath,
          stagingDirPath: stagingDirPath,
        ));
      } on BackupException catch (e) {
        throw MessageException(switch (e.failure) {
          BackupFailure.invalid => currentAppLocalizations.invalidBackupFile,
          BackupFailure.newerVersion =>
            currentAppLocalizations.backupFromNewerVersion,
        });
      }
      await applyRestore(data, option, stagingDirPath: stagingDirPath);
      return true;
    });
  }

  Future<bool> _withWorkDir(Future<bool> Function(String workDir) run) async {
    final workDir = Directory(join(await appPath.tempPath, 'backup$uniqueId'));
    await workDir.create(recursive: true);
    var retained = false;
    try {
      return await run(workDir.path);
    } on RequestUnavailable catch (error) {
      retained = error.code == 'request_partial_commit';
      rethrow;
    } finally {
      if (!retained) await workDir.safeDelete(recursive: true);
      await _discardLegacyStaging();
    }
  }

  /// Earlier versions staged restores in the home directory and never removed
  /// the downloaded archive.
  Future<void> _discardLegacyStaging() async {
    final homeDirPath = await appPath.homeDirPath;
    await File(join(homeDirPath, 'backup.zip')).safeDelete();
    await Directory(join(homeDirPath, 'restore')).safeDelete(recursive: true);
  }

  Future<String> _createArchive(String workDir) async {
    final databaseSnapshotPath = join(workDir, backupDatabaseName);
    await database.customStatement('VACUUM INTO ?', [databaseSnapshotPath]);
    final (profileIds, scriptIds, providers) = await (
      database.profilesDao.query().map((item) => item.id).get(),
      database.scriptsDao.query().map((item) => item.id).get(),
      database.clashProvidersDao.queryAll().get(),
    ).wait;
    final configMap = ref.read(configProvider).toJson();
    configMap['version'] = await preferences.getVersion();
    final archivePath = join(workDir, 'backup.zip');
    await backupTask((
      archivePath: archivePath,
      configMap: configMap,
      databaseSnapshotPath: databaseSnapshotPath,
      homeDirPath: await appPath.homeDirPath,
      entries: BackupEntries.of(
        profileIds: profileIds,
        scriptIds: scriptIds,
        providers: providers,
      ),
    ));
    return archivePath;
  }

  @visibleForTesting
  Future<void> applyRestore(
    MigrationData data,
    RestoreOption option, {
    String? stagingDirPath,
  }) {
    final session = RequestSession.current;
    Future<void> apply() =>
        _applyRestore(data, option, stagingDirPath: stagingDirPath);
    return session == null
        ? requestClient.mutate(apply)
        : session.commit(apply);
  }

  Future<void> _applyRestore(
    MigrationData data,
    RestoreOption option, {
    String? stagingDirPath,
  }) async {
    final configMap = data.configMap;
    final config = option == RestoreOption.onlyProfiles || configMap == null
        ? null
        : Config.fromJson(configMap);
    final isOverride =
        ref.read(appSettingProvider).restoreStrategy ==
        RestoreStrategy.override;
    await requestClient.invalidateDataset();
    final previousConfig = ref.read(configProvider);
    final previousProviders = await database.clashProvidersDao.queryAll().get();
    Future<void> Function()? putBack;
    var preferencesChanged = false;
    final nextConfig = config?.copyWith(
      davProps: config.davProps ?? ref.read(davSettingProvider),
    );
    try {
      await database.restore(
        data.profiles,
        data.scripts,
        data.rules,
        data.links,
        data.proxyGroups,
        clashProviders: data.clashProviders,
        customProxies: data.customProxies,
        isOverride: isOverride,
        beforeCommit: () async {
          if (stagingDirPath != null) {
            putBack = await _copyStagedFiles(data, stagingDirPath);
          }
          if (nextConfig != null) {
            preferencesChanged = true;
            if (!await preferences.saveConfig(nextConfig)) {
              throw const RequestUnavailable('preferences_save_failed');
            }
          }
        },
      );
    } catch (error, stack) {
      try {
        await putBack?.call();
        if (preferencesChanged &&
            !await preferences.saveConfig(previousConfig)) {
          throw StateError('Preferences compensation failed');
        }
      } catch (_) {
        await requestClient.markPartialCommit();
        throw const RequestUnavailable('request_partial_commit');
      }
      Error.throwWithStackTrace(error, stack);
    }
    if (nextConfig != null) writeConfig(ref, nextConfig);
    await _clearReplacedProviderCaches(previousProviders);
    await requestClient.clearPartialCommit();
  }

  /// The files go in before the rows that name them, so the returned callback
  /// is how a restore whose rows fail takes them back out.
  Future<Future<void> Function()> _copyStagedFiles(
    MigrationData data,
    String stagingDirPath,
  ) async {
    final homeDirPath = await appPath.homeDirPath;
    final replacedDirPath = join(stagingDirPath, 'replaced');
    final copied = <String, bool>{};
    Future<void> putBack() async {
      for (final MapEntry(key: entry, value: replaced) in copied.entries) {
        final target = BackupEntries.resolve(homeDirPath, entry);
        if (replaced) {
          await File(
            BackupEntries.resolve(replacedDirPath, entry),
          ).safeCopy(target);
        } else {
          await File(target).safeDelete();
        }
      }
    }

    try {
      for (final entry in BackupEntries.ofData(data)) {
        final staged = File(BackupEntries.resolve(stagingDirPath, entry));
        if (!await staged.exists()) {
          continue;
        }
        final target = File(BackupEntries.resolve(homeDirPath, entry));
        final replaced = await target.exists();
        if (replaced) {
          await target.safeCopy(BackupEntries.resolve(replacedDirPath, entry));
        }
        copied[entry] = replaced;
        await staged.safeCopy(target.path);
      }
    } catch (error, stack) {
      try {
        await putBack();
      } catch (_) {
        await requestClient.markPartialCommit();
        throw const RequestUnavailable('request_partial_commit');
      }
      Error.throwWithStackTrace(error, stack);
    }
    return putBack;
  }

  Future<void> _clearReplacedProviderCaches(
    List<ClashProvider> previousProviders,
  ) async {
    final kept = (await database.clashProvidersDao.fileNames().get()).toSet();
    for (final provider in previousProviders) {
      if (kept.contains(provider.fileName)) {
        continue;
      }
      await File(await provider.path).safeDelete();
    }
  }
}
