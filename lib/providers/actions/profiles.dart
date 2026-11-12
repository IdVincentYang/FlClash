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
      await ref
          .read(profilesProvider.notifier)
          .deletePersisted(id, client: requestClient);
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

  Future<SourceReviewStatus> sourceReviewStatus(Profile profile) async {
    if (!requestClient.requiresSourceAcceptance) {
      return SourceReviewStatus.ready;
    }
    final source = await requestClient.captureSource('profile:${profile.id}');
    final file = File(await appPath.getProfilePath(profile.id.toString()));
    if (!await file.exists()) {
      throw const RequestUnavailable('source_material_unavailable');
    }
    return _sourceAcceptance(_core, requestClient).subscriptionStatus(
      source: source,
      identity: _profileSourceIdentity(profile),
      settings: _profileSourceSettings(profile),
      body: await _sourceBody(file.path, preserveBom: true),
    );
  }

  Future<void> saveLocalGroups(
    Profile expected,
    List<LocalProxyGroup> groups, {
    void Function()? onSaved,
  }) async {
    if (groups.length > localProxyGroupsLimit ||
        groups.map((group) => group.id).toSet().length != groups.length ||
        groups.any(
          (group) =>
              group.id < 0 || group.nodes.length > localProxyGroupMembersLimit,
        )) {
      throw const LocalProxyGroupProblem('limit');
    }
    final setup = ref.read(setupActionProvider.notifier);
    final sequence = setup.reserveSetupSequence();
    String? candidateHash;
    _AcceptedLocalInput? acceptedLocalInput;
    String? applyFailure;
    Map<String, Object?>? expectedRun;
    ConfigFact? previousFact;
    Profile? previous;
    await requestClient.mutate(() async {
      final current = (await database.profilesDao.query().get()).getProfile(
        expected.id,
      );
      if (current == null ||
          !const ListEquality<LocalProxyGroup>().equals(
            current.localGroups,
            expected.localGroups,
          ) ||
          _profileSourceIdentity(current) != _profileSourceIdentity(expected) ||
          SourceAcceptance.fingerprint(_profileSourceSettings(current)) !=
              SourceAcceptance.fingerprint(_profileSourceSettings(expected)) ||
          ref.read(currentProfileIdProvider) != current.id) {
        throw const RequestUnavailable('request_cancelled');
      }
      previous = current;
      final showingCurrent =
          ref.read(configStateProvider).fact.profileId == current.id;
      var picks = <String, String>{
        for (final group in ref.read(groupsProvider))
          if (showingCurrent &&
              group.type == GroupType.Selector &&
              (group.now?.isNotEmpty ?? false))
            group.name: group.now!,
      };
      Future<void> persist() async {
        final latest = (await database.profilesDao.query().get()).getProfile(
          current.id,
        );
        if (latest == null ||
            !const ListEquality<LocalProxyGroup>().equals(
              latest.localGroups,
              current.localGroups,
            ) ||
            _profileSourceIdentity(latest) != _profileSourceIdentity(current) ||
            SourceAcceptance.fingerprint(_profileSourceSettings(latest)) !=
                SourceAcceptance.fingerprint(_profileSourceSettings(current))) {
          throw const RequestUnavailable('request_cancelled');
        }
        await ref
            .read(profilesProvider.notifier)
            .persist(
              latest.copyWith(
                localGroups: groups,
                selectedMap: {
                  ...current.selectedMap,
                  ...picks,
                  for (final entry in latest.selectedMap.entries)
                    if (entry.value != current.selectedMap[entry.key])
                      entry.key: entry.value,
                },
              ),
            );
      }

      if (const ListEquality<LocalProxyGroup>().equals(
        groups,
        current.localGroups,
      )) {
        return;
      }
      final state = await ref.read(setupStateProvider(current.id).future);
      final canSaveInactive = groups.every(
        (group) =>
            !group.enabled ||
            current.localGroups.any(
              (previous) => previous == group && previous.enabled,
            ),
      );
      if (state.policySelection != null) {
        if (!canSaveInactive) throw const LocalProxyGroupProblem('managed');
        await persist();
        return;
      }
      final removed = current.localGroups
          .where(
            (old) =>
                old.enabled &&
                !groups.any((group) => group.enabled && group.name == old.name),
          )
          .map((group) => group.name)
          .toSet();
      if (showingCurrent &&
          ref
              .read(groupsProvider)
              .any(
                (group) =>
                    removed.contains(group.now) ||
                    current.localGroups.any(
                      (old) =>
                          group.now == old.name &&
                          old.entrances.contains(group.name) &&
                          !groups.any(
                            (next) =>
                                next.enabled &&
                                next.name == old.name &&
                                next.entrances.contains(group.name),
                          ),
                    ),
              )) {
        throw const LocalProxyGroupProblem('inUse');
      }
      final source = await requestClient.captureSource('application-config');
      ConfigFact fact;
      try {
        fact = previousFact = await _core.getConfigState();
      } catch (_) {
        if (!canSaveInactive) rethrow;
        await persist();
        return;
      }
      if (fact.profileId != current.id ||
          !const {'ready', 'installed'}.contains(fact.phase)) {
        if (canSaveInactive) {
          await persist();
          return;
        }
        throw const LocalProxyGroupProblem('loading');
      }
      expectedRun = await requestClient.captureNativeRunState();
      if (requestClient.requiresSourceAcceptance) {
        try {
          final approved = await _sourceAcceptance(_core, requestClient)
              .approveLocalGroups(
                source: source,
                profileId: current.id,
                expected: fact,
                before: current.localGroups,
                after: groups,
              );
          picks = approved.picks;
          acceptedLocalInput = (
            document: approved.document,
            expected: fact,
            reportFailure: (message) => applyFailure = message,
          );
          candidateHash = sha256
              .convert(utf8.encode(approved.document['yaml'] as String))
              .toString();
        } on RequestUnavailable catch (error) {
          if (!canSaveInactive ||
              !const {
                'local_groups_source_unavailable',
                'local_groups_changed',
                'source_permissions_unavailable',
              }.contains(error.code) ||
              !await requestClient.configSourceCurrent(source)) {
            rethrow;
          }
          await persist();
          return;
        }
      } else {
        final composition = await setup.getProfile(
          setupState: state.copyWith(localGroups: groups),
          patchConfig: ref.read(patchClashConfigProvider),
          isCurrent: () => requestClient.configSourceCurrent(source),
        );
        candidateHash = sha256
            .convert(utf8.encode(composition.yaml))
            .toString();
      }
      if (candidateHash == fact.yamlSha256) {
        await persist();
        candidateHash = null;
        return;
      }
      await requestClient.invalidate('application-config');
      await persist();
    });
    onSaved?.call();
    if (candidateHash == null) return;
    final applied = await setup._runSetup(
      force: true,
      preferHot:
          requestClient.requiresSourceAcceptance &&
          previousFact?.businessActive == true &&
          previousFact?.isManaged == false,
      setupSequence: sequence,
      expectedRun: expectedRun,
      acceptedLocalInput: acceptedLocalInput,
      isCurrent: () async =>
          ref.mounted &&
          ref.read(currentProfileIdProvider) == expected.id &&
          const ListEquality<LocalProxyGroup>().equals(
            ref.read(profileProvider(expected.id))?.localGroups,
            groups,
          ),
    );
    if (applied == _SetupTaskResult.completed) return;
    final fact = await _core.getConfigState();
    if (fact.yamlSha256 == candidateHash &&
        fact.profileId == expected.id &&
        const {'ready', 'installed'}.contains(fact.phase)) {
      return;
    }
    if (onSaved == null &&
        fact.yamlSha256 == previousFact?.yamlSha256 &&
        fact.profileId == expected.id) {
      await requestClient.mutate(() async {
        final current = (await database.profilesDao.query().get()).getProfile(
          expected.id,
        );
        if (current != null &&
            const ListEquality<LocalProxyGroup>().equals(
              current.localGroups,
              groups,
            ) &&
            _profileSourceIdentity(current) ==
                _profileSourceIdentity(previous!)) {
          await ref
              .read(profilesProvider.notifier)
              .persist(current.copyWith(localGroups: previous!.localGroups));
        }
      });
    }
    if (applied == _SetupTaskResult.foregroundRequired) {
      throw const LocalProxyGroupProblem('foreground');
    }
    if (applied == _SetupTaskResult.superseded ||
        applied == _SetupTaskResult.staleInput) {
      throw const LocalProxyGroupProblem('changed');
    }
    if (applyFailure?.isNotEmpty == true) throw MessageException(applyFailure!);
    throw const LocalProxyGroupProblem('apply');
  }

  Future<void> manageSourcePermissions(
    Profile profile, {
    bool review = false,
  }) async {
    if (review && requestClient.requiresSourceAcceptance) {
      return presentSourceReview(
        profile,
        (confirm, current) => _manageSourcePermissions(
          profile,
          review: true,
          confirm: confirm,
          isCurrent: current,
        ),
      );
    }
    return _manageSourcePermissions(profile, review: review);
  }

  @protected
  Future<void> presentSourceReview(
    Profile profile,
    Future<void> Function(SourceConfirmation confirm, bool Function() current)
    work,
  ) => _prepareSourceReview(ref, profile.realLabel, work);

  Future<void> _manageSourcePermissions(
    Profile profile, {
    bool review = false,
    SourceConfirmation? confirm,
    bool Function()? isCurrent,
  }) async {
    if (!requestClient.requiresSourceAcceptance) return;
    final setup = ref.read(setupActionProvider.notifier);
    final setupSequence = setup.reserveSetupSequence();
    final recovery = await requestClient.materialRecoveryRequired();
    if (isCurrent != null && !isCurrent()) return;
    if (recovery) {
      final expectedRun = await _recoverSourceMaterialCommit(
        _core,
        requestClient,
      );
      if (expectedRun != null && ref.mounted) {
        await setup.applyProfile(
          force: true,
          allowBootstrap: true,
          allowSourceReview: true,
          expectedRun: expectedRun,
          setupSequence: setupSequence,
        );
      }
      return;
    }
    final acceptance = _sourceAcceptance(
      _core,
      requestClient,
      confirm: confirm ?? ref.read(sourceConfirmationProvider),
    );
    final source = await requestClient.captureSource('profile:${profile.id}');
    final expectedRun = await requestClient.captureNativeRunState();
    SourcePermissionChoice? choice;
    if (review) {
      choice = (action: SourcePermissionAction.review, permission: null);
    } else {
      final config = await requestClient.captureSource('application-config');
      final permissions = [
        ...await acceptance.permissions(source: source, kind: 'profile'),
        ...await acceptance.permissions(
          source: config,
          kind: 'config',
          entityKey: 'config:${profile.id}',
        ),
      ];
      choice = await dialogs.showCommonDialog<SourcePermissionChoice>(
        child: SourcePermissionsDialog(
          label: profile.realLabel,
          permissions: permissions,
        ),
      );
    }
    if (choice == null) return;
    if (choice.action == SourcePermissionAction.review) {
      await _reviewProfileSource(
        confirm: confirm ?? ref.read(sourceConfirmationProvider),
        core: _core,
        requests: requestClient,
        profile: profile,
        path: await appPath.getProfilePath(profile.id.toString()),
        source: source,
        forceReview: true,
        isCurrent: isCurrent == null ? null : () async => isCurrent(),
      );
      await _completeSubscriptionReview(profile);
      if (ref.mounted &&
          expectedRun != null &&
          ref.read(currentProfileIdProvider) == profile.id) {
        await setup.applyProfile(
          force: true,
          allowSourceReview: true,
          expectedRun: expectedRun,
          setupSequence: setupSequence,
        );
      }
    } else {
      await acceptance.withdraw(
        choice.permission!,
        stopUse: choice.action == SourcePermissionAction.stopUse,
      );
    }
    if (ref.mounted) {
      await ref.read(configStateProvider.notifier).refresh();
    }
  }

  @override
  Future<void> _completeSubscriptionReview(
    Profile profile, {
    SourceConfirmation? confirm,
  }) async {
    final store = SourceReviewBatchStore.forRequests(requestClient);
    if (store.isEmpty) return;
    final source = await requestClient.captureSource('profile:${profile.id}');
    final reviewed = store.configuration(source.key, source.client);
    if (reviewed == null) return;
    final application = await requestClient.captureSource('application-config');
    Future<bool> current() async =>
        ref.mounted &&
        await requestClient.configSourceCurrent(source) &&
        await requestClient.configSourceCurrent(application);
    final uses = <Map<String, Object?>>[];
    final confirmation = confirm ?? ref.read(sourceConfirmationProvider);
    final setup = ref.read(setupActionProvider.notifier);
    final state = await ref.read(setupStateProvider(profile.id).future);
    final selection = state.policySelection;
    final selected = selection == null
        ? null
        : SelectedPolicy.decode(selection.rawContent);
    final patch = setup._effectivePatchConfig(
      ref.read(patchClashConfigProvider),
    );
    late ({String yaml, String md5}) composition;
    if (selected?.usesMaterials == true) {
      final frame = await _ManagedMaterialFrame.capture(profile, state);
      try {
        final resolved = await frame.resolve(
          _core,
          state,
          selected!,
          requests: requestClient,
          confirm: confirmation,
          onSourceUse: uses.add,
          isCurrent: current,
        );
        composition = await setup._composeManagedSubscription(
          state: state,
          patch: patch,
          selected: resolved,
        );
      } finally {
        await frame.file.close();
      }
    } else {
      composition = await setup.getProfile(
        setupState: state,
        patchConfig: patch,
        allowSourceReview: true,
        isCurrent: current,
        onSourceUse: uses.add,
      );
    }
    if (!await current() ||
        sha256.convert(utf8.encode(composition.yaml)).toString() !=
            reviewed.bodyHash) {
      throw const RequestUnavailable('request_cancelled');
    }
    final acceptance = _sourceAcceptance(
      _core,
      requestClient,
      confirm: confirmation,
    );
    final root = await acceptance.review(
      source: application,
      entityKey: 'config:${profile.id}',
      identity: SourceAcceptance.fingerprint({'profile': profile.id}),
      settings: reviewed.settings,
      body: composition.yaml,
      label: profile.realLabel,
      location: profile.url,
      kind: 'config',
      uses: uses,
      isCurrent: current,
    );
    try {
      final bundle = await acceptance.completeProviders(
        root: root,
        dependencies: uses,
        source: application,
        automatic: false,
        isCurrent: current,
        reviewed: true,
      );
      await bundle.release();
    } finally {
      await root.release();
    }
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
    ProfileImportTask? importTask,
    SourceConfirmation? confirm,
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
        importTask: importTask,
        confirm: confirm,
      );
      importTask?.attach(job.cancel);
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
    SourceMaterialApproval? approval;
    try {
      approval = await _reviewProfileMaterial(
        confirm: ref.read(sourceConfirmationProvider),
        core: _core,
        requests: requestClient,
        profile: profile,
        path: staged.staged.path,
        fresh: true,
      );
      final message = await _core.validateConfig(staged.staged.path);
      if (message.isNotEmpty) throw MessageException(message);
      final path = await appPath.getProfilePath(profile.id.toString());
      Future<void> persist() async {
        if (approval != null) {
          await approval.invalidate();
        } else {
          await requestClient.invalidate('profile:${profile.id}');
        }
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
                networkResult: approval != null,
              ),
        );
      }

      if (approval != null) {
        await approval.commit(action: persist);
      } else {
        await requestClient.mutate(persist);
      }
      await _completeSubscriptionReview(profile);
    } finally {
      await approval?.release();
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

  Future<ProfileRefreshResult?> addProfileFormURL(
    String url, {
    String? label,
    RequestMode mode = RequestMode.auto,
    String? proxy,
    bool confirmed = false,
    ProfileImportTask? importTask,
    SourceReviewPresentation? reviewPresentation,
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
      if (result == null) return null;
      url = result.url;
      label = result.label;
    }
    final profile = Profile.normal(
      label: label,
      url: url,
    ).copyWith(requestMode: mode, requestProxy: proxy);
    ref.read(currentPageLabelProvider.notifier).value = PageLabel.profiles;
    if (importTask != null) {
      return updateProfile(
        profile,
        importing: true,
        importTask: importTask,
        confirm: reviewPresentation == null
            ? null
            : (review) => confirmSourceReview(
                ref,
                review,
                presentation: reviewPresentation,
                importing: true,
                loadedNodesSnapshot: importTask.usingLoadedNodes,
              ),
      );
    }
    return globalState.loadingRun(
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
