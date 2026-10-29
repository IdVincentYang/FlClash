part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction with _ProfileRefreshQueue {
  @override
  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  @protected
  Request get requestClient => request;

  @override
  @protected
  DateTime get refreshNow => DateTime.now();

  @override
  @protected
  Duration get refreshElapsed => _refreshClock.elapsed;

  @override
  void build() {
    _watchRefreshProfiles();
    ref.listen(appVisibleProvider, (previous, visible) {
      if (visible && previous != true) unawaited(autoUpdateProfiles());
    });
    ref.listen(nativeRequestStateProvider, (_, next) {
      unawaited(_cancelExpiredDemands());
      if (next['phase'] == 'started' &&
          next['intentRunning'] == true &&
          next['paused'] != true) {
        unawaited(autoUpdateProfiles());
      }
    });
    ref.onDispose(() {
      _refreshDisposed = true;
      _refreshTimer?.cancel();
      _refreshClock.stop();
      for (final job in [
        ..._refreshJobs.values,
        ..._refreshSuccessors.values,
      ]) {
        job.cancel();
        if (!job.committing) {
          job.complete(
            const ProfileRefreshResult(
              application: ProfileApplicationOutcome.superseded,
            ),
          );
        }
      }
      _refreshJobs.clear();
      _refreshSuccessors.clear();
      _refreshRetries.clear();
    });
  }

  void setupExecutionChanged(bool busy) {
    _refreshSetupBusy = busy;
    if (!busy) _pumpRefresh();
  }

  Future<void> useDefaultCustomConfig(int profileId) async {
    final source = await requestClient.captureSource('profile:$profileId');
    final raw = await _core.getConfig(profileId);
    final config = await clashConfigTask(raw);
    final rawProxies = raw['proxies'];
    if (feature.customProxies && rawProxies != null && rawProxies is! List) {
      throw const FormatException('proxies');
    }
    final proxies = feature.customProxies
        ? [
            for (final item in rawProxies ?? const [])
              if (item is Map) CustomProxy.fromDefinition(item),
          ]
        : null;
    await requestClient.mutate(() async {
      if (!await requestClient.configSourceCurrent(source)) {
        throw const RequestUnavailable('request_cancelled');
      }
      await requestClient.invalidate('profile:$profileId');
      await database.setProfileCustomData(
        profileId,
        proxies,
        config.proxyGroups,
        config.rules,
      );
    });
  }

  void updateCurrentSelectedMap(String groupName, String proxyName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.selectedMap[groupName] == proxyName) return;
    unawaited(
      ref
          .read(profilesProvider.notifier)
          .updateProfile(
            profile.id,
            (current) => current.copyWith(
              selectedMap: {...current.selectedMap, groupName: proxyName},
            ),
          ),
    );
  }

  Future<void> deleteProfile(int id) async {
    await requestClient.mutate(() async {
      await requestClient.invalidateDataset();
      await ref.read(profilesProvider.notifier).deletePersisted(id);
      await clearEffect(id);
    });
    final currentProfileId = ref.read(currentProfileIdProvider);
    if (currentProfileId == id) {
      ref.read(currentProfileIdProvider.notifier).value = null;
      await ref.read(setupActionProvider.notifier).setRunning(false);
      return;
    }
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  Future<String> validateConfigWithData(String data) async {
    return _core.validateConfigWithData(data);
  }

  void _watchRefreshProfiles() {
    if (_refreshDisposed ||
        _refreshProfilesSubscribed ||
        !requestClient.isAttached) {
      return;
    }
    _refreshProfilesSubscribed = true;
    ref.listen(profilesProvider, (_, _) => unawaited(autoUpdateProfiles()));
  }

  Future<void> autoUpdateProfiles() {
    _watchRefreshProfiles();
    return _wakeRefresh();
  }

  Profile _editedProfile(Profile? current, Profile proposed) =>
      (current ?? proposed).copyWith(
        label: proposed.label,
        url: proposed.url,
        requestMode: proposed.requestMode,
        requestProxy: proposed.requestProxy,
        autoUpdate: proposed.autoUpdate,
        autoUpdateDuration: proposed.autoUpdateDuration,
      );

  Future<void> putProfile(
    Profile profile, {
    Iterable<int> renameIn = const [],
    void Function(RequestSource)? onSourceSaved,
  }) async {
    await requestClient.mutate(() async {
      final current = (await database.profilesDao.query().get()).getProfile(
        profile.id,
      );
      final saved = await ref
          .read(profilesProvider.notifier)
          .persist(_editedProfile(current, profile), renameIn: renameIn);
      if (onSourceSaved != null) {
        final source = await requestClient.captureSource(
          'profile:${profile.id}',
        );
        _reserveEditedRefresh(saved, source);
        onSourceSaved(source);
      }
    });
  }

  Future<List<Profile>> providerUsers(Profile profile) async {
    if (!feature.customProviders) {
      return const [];
    }
    final users = await ref
        .read(clashProvidersActionProvider.notifier)
        .profilesReferencing(ProviderKind.proxy, profile.realLabel);
    return [
      for (final user in users)
        if (user.id != profile.id) user,
    ];
  }

  /// [conflicts] would move to their subscription's provider of the new name.
  Future<({List<Profile> renameIn, List<Profile> conflicts})> providerRename(
    Profile previous,
    Profile next,
  ) async {
    final label = ref.read(profilesProvider.notifier).labeled(next).realLabel;
    if (!feature.customProviders || label == previous.realLabel) {
      return (renameIn: const <Profile>[], conflicts: const <Profile>[]);
    }
    final renameIn = await providerUsers(previous);
    final conflicts = await ref
        .read(clashProvidersActionProvider.notifier)
        .profilesDefining(ProviderKind.proxy, label, renameIn);
    return (renameIn: renameIn, conflicts: conflicts);
  }

  Future<void> updateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (profile.type == ProfileType.file) continue;
      try {
        await updateProfile(profile, showLoading: true);
      } on RequestUnavailable catch (error) {
        dialogs.showNotifier(error.toString(), level: MessageLevel.error);
      }
    }
  }

  Future<ProfileRefreshResult> updateProfile(
    Profile profile, {
    bool showLoading = false,
    bool automatic = false,
    bool allowBootstrap = false,
    bool sourceEdit = false,
    bool sourceMustMatch = false,
    bool importing = false,
    RequestSource? expectedSource,
    Iterable<int> renameIn = const [],
  }) async {
    if (_refreshDisposed) {
      return const ProfileRefreshResult(
        application: ProfileApplicationOutcome.superseded,
      );
    }
    final operation = showLoading
        ? ref.read(updatingKeysProvider.notifier).start(profile.updatingKey)
        : null;
    try {
      if (sourceEdit) await putProfile(profile, renameIn: renameIn);
      final job = await _enqueueRefresh(
        profile,
        automatic: automatic,
        importing: importing,
        allowBootstrap: allowBootstrap,
        sourceMustMatch: sourceMustMatch,
        expectedSource: expectedSource,
      );
      final result = await job.completion.future;
      if (result.failure != null &&
          (!result.materialSaved ||
              result.failure == 'request_partial_commit')) {
        throw RequestUnavailable(result.failure!);
      }
      if (ref.mounted &&
          !automatic &&
          result.materialSaved &&
          !const {
            ProfileApplicationOutcome.notRequired,
            ProfileApplicationOutcome.activated,
            ProfileApplicationOutcome.installedInactive,
          }.contains(result.application)) {
        dialogs.showNotifier(
          result.failure == 'profile_saved_recovery_required'
              ? currentAppLocalizations.profileSavedRecoveryRequired
              : currentAppLocalizations.profileSavedNotApplied,
          level: MessageLevel.warning,
        );
      }
      return result;
    } finally {
      if (operation != null && ref.mounted) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(profile.updatingKey, operation);
      }
    }
  }

  Future<Profile?> ensureFile(
    Profile profile, {
    Future<bool> Function()? isCurrent,
  }) async {
    if (profile.url.isEmpty ||
        await File(
          await appPath.getProfilePath(profile.id.toString()),
        ).exists()) {
      return null;
    }
    final job = await _enqueueRefresh(
      profile,
      allowBootstrap: true,
      demandCurrent: isCurrent ?? () async => ref.mounted,
    );
    final result = await job.material.future;
    if (!result.materialSaved) {
      throw RequestUnavailable(result.failure ?? 'request_cancelled');
    }
    return (await database.profilesDao.query().get()).getProfile(profile.id);
  }

  Future<void> importFile(
    Profile profile,
    List<int> bytes, {
    Iterable<int> renameIn = const [],
  }) async {
    final staged = await RequestFile.stage(bytes);
    try {
      final message = await _core.validateConfig(staged.staged.path);
      if (message.isNotEmpty) throw MessageException(message);
      final path = await appPath.getProfilePath(profile.id.toString());
      await requestClient.mutate(() async {
        await requestClient.invalidate('profile:${profile.id}');
        final current = (await database.profilesDao.query().get()).getProfile(
          profile.id,
        );
        await staged.replace(
          path,
          () => ref
              .read(profilesProvider.notifier)
              .persist(
                _editedProfile(
                  current,
                  profile,
                ).copyWith(lastUpdateDate: DateTime.now()),
                renameIn: renameIn,
              ),
        );
      });
    } finally {
      await staged.close();
    }
  }

  Future<void> addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final bytes = await platformFile.readBytes();
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    ref.read(currentPageLabelProvider.notifier).toProfiles();
    await globalState.loadingRun(
      () => importFile(Profile.normal(label: platformFile.name), bytes),
      tag: LoadingTag.profiles,
      title: currentAppLocalizations.addProfile,
    );
  }

  Future<void> addProfileFormURL(
    String url, {
    String? label,
    RequestMode mode = RequestMode.auto,
    String? proxy,
    bool confirmed = false,
  }) async {
    if (!confirmed) {
      final result = await dialogs.showNamedUrlInput(
        title: currentAppLocalizations.importFromURL,
        url: url,
        label: label ?? '',
        requestMode: mode,
        requestProxy: proxy,
        onRequestRouteChanged: (value) {
          mode = value.$1;
          proxy = value.$2;
        },
      );
      if (result == null) return;
      url = result.url;
      label = result.label;
    }
    final profile = Profile.normal(
      label: label,
      url: url,
    ).copyWith(requestMode: mode, requestProxy: proxy);
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    await globalState.loadingRun(
      () => updateProfile(profile, importing: true),
      tag: LoadingTag.profiles,
      title: currentAppLocalizations.addProfile,
    );
  }

  Future<void> setProfileAndAutoApply(Profile profile) async {
    await putProfile(profile);
    if (profile.id == ref.read(currentProfileIdProvider)) {
      ref.read(setupActionProvider.notifier).applyProfileDebounce();
    }
  }

  Future<void> addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    unawaited(addProfileFormURL(url));
  }

  void reorder(List<Profile> profiles) {
    ref.read(profilesProvider.notifier).reorder(profiles);
  }

  Future<void> clearEffect(int profileId) async {
    final profilePath = await appPath.getProfilePath(profileId.toString());
    final profileFile = File(profilePath);
    final isExists = await profileFile.exists();
    if (isExists) {
      await profileFile.safeDelete(recursive: true);
    }
    try {
      final error = await _core.clearEffect(profileId);
      if (error.isNotEmpty) {
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    } catch (error) {
      commonPrint.log(
        'clearEffect($profileId) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }
}
