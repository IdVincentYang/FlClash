part of '../action.dart';

@Riverpod(keepAlive: true)
class ProfilesAction extends _$ProfilesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  @protected
  Request get requestClient => request;

  @override
  void build() {}

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
      final profiles = ref.read(profilesProvider);
      if (profiles.isNotEmpty) {
        final updateId = profiles.first.id;
        ref.read(currentProfileIdProvider.notifier).value = updateId;
      } else {
        ref.read(currentProfileIdProvider.notifier).value = null;
        unawaited(ref.read(setupActionProvider.notifier).setRunning(false));
      }
    }
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  Future<String> validateConfigWithData(String data) async {
    return _core.validateConfigWithData(data);
  }

  Future<void> autoUpdateProfiles() async {
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile, automatic: true);
      } catch (e) {
        commonPrint.log(compactError(e), logLevel: LogLevel.warning);
      }
    }
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
      await ref
          .read(profilesProvider.notifier)
          .persist(_editedProfile(current, profile), renameIn: renameIn);
      if (onSourceSaved != null) {
        onSourceSaved(
          await requestClient.captureSource('profile:${profile.id}'),
        );
      }
    });
    if (ref.read(currentProfileIdProvider) == null) {
      ref.read(currentProfileIdProvider.notifier).value = profile.id;
    }
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
      await updateProfile(profile, showLoading: true);
    }
  }

  Future<void> updateProfile(
    Profile profile, {
    bool showLoading = false,
    bool automatic = false,
    bool allowBootstrap = false,
    bool sourceEdit = false,
    bool sourceMustMatch = false,
    RequestSource? expectedSource,
    Iterable<int> renameIn = const [],
  }) async {
    final operation = showLoading
        ? ref.read(updatingKeysProvider.notifier).start(profile.updatingKey)
        : null;
    RequestSession? session;
    RequestFile? staged;
    try {
      if (sourceEdit) await putProfile(profile, renameIn: renameIn);
      if (expectedSource != null &&
          !await requestClient.sourceCurrent(expectedSource)) {
        return;
      }
      final previous = (await database.profilesDao.query().get()).getProfile(
        profile.id,
      );
      if (sourceMustMatch &&
          (previous == null ||
              (
                    previous.url,
                    previous.requestMode,
                    previous.requestProxy,
                    previous.autoUpdate,
                    previous.autoUpdateDuration,
                  ) !=
                  (
                    profile.url,
                    profile.requestMode,
                    profile.requestProxy,
                    profile.autoUpdate,
                    profile.autoUpdateDuration,
                  ))) {
        return;
      }
      profile = previous ?? profile;
      session = await requestClient.begin(
        key: 'profile:${profile.id}',
        url: profile.url,
        mode: profile.requestMode,
        proxy: profile.requestProxy,
        automatic: automatic,
        allowBootstrap: allowBootstrap,
        bootstrapIfUnconfigured:
            previous == null && profile.requestMode == RequestMode.proxy,
        label: profile.realLabel,
        expectedSource: expectedSource,
        sourceIsCurrent: () async {
          final current = (await database.profilesDao.query().get()).getProfile(
            profile.id,
          );
          return current == null
              ? previous == null
              : (
                      current.url,
                      current.requestMode,
                      current.requestProxy,
                      current.autoUpdate,
                    ) ==
                    (
                      profile.url,
                      profile.requestMode,
                      profile.requestProxy,
                      profile.autoUpdate,
                    );
        },
      );
      final response = await session.run(
        () => requestClient.getFileResponseForUrl(profile.url),
      );
      staged = await RequestFile.stage(response.data ?? []);
      final message = await _core.validateConfig(staged.staged.path);
      if (message.isNotEmpty) throw MessageException(message);
      final incoming = staged;
      final path = await appPath.getProfilePath(profile.id.toString());
      await session.commit(() async {
        final current =
            (await database.profilesDao.query().get()).getProfile(profile.id) ??
            profile;
        final next = current.copyWith(
          label: current.label.takeFirstValid([
            getFileNameForDisposition(
              response.headers.value('content-disposition'),
            ),
            profile.id.toString(),
          ]),
          subscriptionInfo: SubscriptionInfo.formHString(
            response.headers.value('subscription-userinfo'),
          ),
          lastUpdateDate: DateTime.now(),
        );
        await incoming.replace(
          path,
          () => ref
              .read(profilesProvider.notifier)
              .persist(next, networkResult: true),
        );
        await requestClient.invalidate('profile:${profile.id}');
      });
      if (ref.read(currentProfileIdProvider) == null) {
        ref.read(currentProfileIdProvider.notifier).value = profile.id;
      }
      final completed = session;
      Future<bool> current() async =>
          profile.id == ref.read(currentProfileIdProvider) &&
          await completed.lifecycleCurrent(sourceInvalidated: true);
      if (await current()) {
        ref
            .read(setupActionProvider.notifier)
            .applyProfileDebounce(silence: true, isCurrent: current);
      }
    } finally {
      session?.close();
      await staged?.close();
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(profile.updatingKey, operation);
      }
    }
  }

  Future<Profile?> ensureFile(Profile profile) async {
    if (profile.url.isEmpty ||
        await File(
          await appPath.getProfilePath(profile.id.toString()),
        ).exists()) {
      return null;
    }
    await updateProfile(profile, allowBootstrap: true);
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
      if (ref.read(currentProfileIdProvider) == null) {
        ref.read(currentProfileIdProvider.notifier).value = profile.id;
      }
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
      () => updateProfile(profile),
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
