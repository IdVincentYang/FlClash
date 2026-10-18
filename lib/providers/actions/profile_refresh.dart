part of '../action.dart';

typedef _RefreshFields = (
  String,
  RequestMode,
  String?,
  bool,
  Duration,
  DateTime?,
);

_RefreshFields _refreshFields(Profile profile) => (
  profile.url,
  profile.requestMode,
  profile.requestProxy,
  profile.autoUpdate,
  profile.autoUpdateDuration,
  profile.lastUpdateDate,
);

(String, RequestMode, String?, bool, Duration) _refreshSettings(
  Profile profile,
) => (
  profile.url,
  profile.requestMode,
  profile.requestProxy,
  profile.autoUpdate,
  profile.autoUpdateDuration,
);

class _RefreshRetry {
  _RefreshRetry(this.fields);
  final _RefreshFields fields;
  Duration? attempted;
  int failures = 0;
  bool permissionBlocked = false;
}

class _ProfileRefreshJob {
  _ProfileRefreshJob({
    required this.profile,
    required this.source,
    required this.expectedSource,
    required this.automatic,
    required this.importing,
    required this.allowBootstrap,
    this.demandCurrent,
    this.ready = true,
  });
  final Profile profile;
  final RequestSource source;
  final RequestSource? expectedSource;
  bool automatic, ready;
  final bool importing, allowBootstrap;
  final Future<bool> Function()? demandCurrent;
  final registration = Completer<void>();
  final material = Completer<ProfileRefreshResult>();
  final completion = Completer<ProfileRefreshResult>();
  RequestSession? session;
  RequestSource? materialSource;
  RequestSource? savedSource;
  ConfigFailureObservation? observation;
  int? affectedProfile;
  bool dependencyUnknown = false;
  bool invalidated = false;
  bool started = false;
  bool committing = false;
  bool superseded = false;
  bool get urgent => demandCurrent != null;

  bool compatible(_ProfileRefreshJob other) =>
      (!started || session?.isActive == true) &&
      importing == other.importing &&
      allowBootstrap == other.allowBootstrap &&
      identical(demandCurrent, other.demandCurrent) &&
      _refreshFields(profile) == _refreshFields(other.profile) &&
      _sameSource(
        materialSource ?? source,
        other.materialSource ?? other.source,
      ) &&
      _sameSource(expectedSource, other.expectedSource);

  static bool _sameSource(RequestSource? a, RequestSource? b) =>
      identical(a, b) ||
      a != null &&
          b != null &&
          identical(a.owner, b.owner) &&
          a.key == b.key &&
          a.client == b.client &&
          a.dataset == b.dataset &&
          a.revision == b.revision &&
          json.encode(a.snapshot) == json.encode(b.snapshot);

  void cancel() {
    superseded = true;
    session?.close();
  }

  void complete(ProfileRefreshResult result) {
    if (!material.isCompleted) material.complete(result);
    if (!completion.isCompleted) completion.complete(result);
  }
}

mixin _ProfileRefreshQueue on _$ProfilesAction {
  CoreController get _core;
  Request get requestClient;
  DateTime get refreshNow;
  Duration get refreshElapsed;

  final _refreshJobs = <int, _ProfileRefreshJob>{};
  final _refreshSuccessors = <int, _ProfileRefreshJob>{};
  final _refreshRetries = <int, _RefreshRetry>{};
  final _refreshClock = Stopwatch()..start();
  Timer? _refreshTimer;
  _ProfileRefreshJob? _refreshWorker;
  int _refreshPosts = 0;
  bool _refreshSetupBusy = false;
  bool _refreshDisposed = false;
  bool _refreshProfilesSubscribed = false;

  Future<_ProfileRefreshJob> _enqueueRefresh(
    Profile proposed, {
    bool automatic = false,
    bool importing = false,
    bool allowBootstrap = false,
    bool sourceMustMatch = false,
    RequestSource? expectedSource,
    Future<bool> Function()? demandCurrent,
  }) async {
    final predecessor = _refreshJobs[proposed.id];
    if (predecessor != null && predecessor.started && !predecessor.committing) {
      await predecessor.registration.future;
    }
    final (current, source) = await dataMutations.run(
      () async => (
        (await database.profilesDao.query().get()).getProfile(proposed.id),
        await requestClient.captureSource('profile:${proposed.id}'),
      ),
    );
    final profile = importing ? proposed : current ?? proposed;
    final job = _ProfileRefreshJob(
      profile: profile,
      source: source,
      expectedSource: expectedSource,
      automatic: automatic,
      importing: importing,
      allowBootstrap: allowBootstrap,
      demandCurrent: demandCurrent,
    );
    if (_refreshDisposed ||
        (importing ? current != null : current == null) ||
        profile.type == ProfileType.file ||
        sourceMustMatch &&
            _refreshSettings(profile) != _refreshSettings(proposed)) {
      job.complete(
        const ProfileRefreshResult(
          application: ProfileApplicationOutcome.superseded,
        ),
      );
      return job;
    }
    return _acceptRefreshJob(job);
  }

  void _reserveEditedRefresh(Profile profile, RequestSource source) {
    _acceptRefreshJob(
      _ProfileRefreshJob(
        profile: profile,
        source: source,
        expectedSource: source,
        automatic: false,
        importing: false,
        allowBootstrap: false,
        ready: false,
      ),
    );
  }

  _ProfileRefreshJob _acceptRefreshJob(_ProfileRefreshJob job) {
    final profile = job.profile;
    final automatic = job.automatic;
    final existing = _refreshJobs[profile.id];
    if (existing == null) {
      _refreshJobs[profile.id] = job;
    } else if (!existing.committing &&
        !existing.superseded &&
        existing.compatible(job)) {
      if (!automatic && existing.automatic && existing.started) {
        existing.cancel();
        _replaceSuccessor(job);
      } else {
        if (!automatic) {
          existing.automatic = false;
          existing.ready = existing.ready || job.ready;
        }
        if (existing.urgent) unawaited(_cancelExpiredDemands());
        _pumpRefresh();
        return existing;
      }
    } else if (automatic) {
      job.complete(
        const ProfileRefreshResult(
          application: ProfileApplicationOutcome.superseded,
        ),
      );
      return job;
    } else if (!existing.started) {
      existing.cancel();
      existing.complete(
        const ProfileRefreshResult(
          application: ProfileApplicationOutcome.superseded,
        ),
      );
      _refreshJobs[profile.id] = job;
    } else {
      if (!existing.committing) existing.cancel();
      _replaceSuccessor(job);
    }
    if (job.urgent) unawaited(_cancelExpiredDemands());
    _pumpRefresh();
    return job;
  }

  void _replaceSuccessor(_ProfileRefreshJob job) {
    final previous = _refreshSuccessors[job.profile.id];
    previous?.cancel();
    previous?.complete(
      const ProfileRefreshResult(
        application: ProfileApplicationOutcome.superseded,
      ),
    );
    _refreshSuccessors[job.profile.id] = job;
  }

  Future<void> _cancelExpiredDemands() async {
    for (final job in [..._refreshJobs.values, ..._refreshSuccessors.values]) {
      if (_refreshDisposed) return;
      if (!job.urgent || job.committing) continue;
      var current = false;
      try {
        current = await job.demandCurrent!();
      } catch (_) {}
      if (current || job.committing) continue;
      job.cancel();
      if (!job.started) {
        if (identical(_refreshSuccessors[job.profile.id], job)) {
          _refreshSuccessors.remove(job.profile.id);
        }
        _completeRefresh(
          job,
          const ProfileRefreshResult(
            application: ProfileApplicationOutcome.superseded,
          ),
        );
      }
    }
  }

  void _pumpRefresh() {
    if (_refreshDisposed || _refreshWorker != null) return;
    final ordinaryBlocked = _refreshSetupBusy || _refreshPosts != 0;
    final eligible = _refreshJobs.values.where(
      (job) =>
          !job.started &&
          job.ready &&
          (!ordinaryBlocked || job.urgent) &&
          (!job.automatic || !requestClient.partialCommit),
    );
    final job =
        eligible.where((job) => job.urgent).firstOrNull ??
        eligible.where((job) => !job.automatic).firstOrNull ??
        eligible.firstOrNull;
    if (job == null) return;
    _refreshWorker = job;
    job.started = true;
    unawaited(_runRefreshMaterial(job));
  }

  Future<bool> _refreshRowCurrent(
    _ProfileRefreshJob job, {
    bool requireDue = false,
  }) async {
    if (_refreshDisposed ||
        job.superseded ||
        job.demandCurrent != null && !await job.demandCurrent!()) {
      return false;
    }
    final row = (await database.profilesDao.query().get()).getProfile(
      job.profile.id,
    );
    if (_refreshDisposed ||
        job.superseded ||
        job.demandCurrent != null && !await job.demandCurrent!()) {
      return false;
    }
    if (job.importing) return row == null;
    if (row == null ||
        job.automatic && !row.autoUpdate ||
        row.type == ProfileType.file ||
        _refreshFields(row) != _refreshFields(job.profile)) {
      return false;
    }
    return !job.automatic ||
        !requireDue ||
        await _automaticRunEligible(row) &&
            _automaticDelay(row) <= Duration.zero;
  }

  Future<void> _runRefreshMaterial(_ProfileRefreshJob job) async {
    RequestFile? staged;
    var result = const ProfileRefreshResult(
      application: ProfileApplicationOutcome.superseded,
    );
    var saved = false;
    try {
      if (!await _refreshRowCurrent(job, requireDue: true)) return;
      if (job.expectedSource != null &&
          !await requestClient.sourceCurrent(job.expectedSource!)) {
        return;
      }
      final profile = job.profile;
      final session = await requestClient.begin(
        key: 'profile:${profile.id}',
        url: profile.url,
        mode: profile.requestMode,
        proxy: profile.requestProxy,
        automatic: job.automatic,
        allowBootstrap: job.allowBootstrap,
        bootstrapIfUnconfigured:
            job.importing && profile.requestMode == RequestMode.proxy,
        label: profile.realLabel,
        expectedSource: job.expectedSource,
        queuedMaterialSource: job.expectedSource == null ? job.source : null,
        sourceIsCurrent: () => _refreshRowCurrent(job, requireDue: true),
      );
      job.session = session;
      if (job.superseded) throw const RequestUnavailable('request_cancelled');
      final materialSource = await requestClient.captureSource(
        'profile:${profile.id}',
      );
      job.materialSource = materialSource;
      job.registration.complete();
      final retry = _retryFor(profile);
      retry.attempted = refreshElapsed;
      retry.permissionBlocked = false;
      final response = await session.run(
        () => requestClient.downloadFileForUrl(profile.url),
      );
      staged = response.file;
      final validation = await _core.validateConfig(staged.staged.path);
      if (validation.isNotEmpty) {
        throw const RequestUnavailable('profile_invalid');
      }
      final incoming = staged;
      final target = await appPath.getProfilePath(profile.id.toString());
      job.committing = true;
      await session.commit(() async {
        if (!await _refreshRowCurrent(job) ||
            !await requestClient.materialSessionCurrent(
              session,
              materialSource,
            )) {
          throw const RequestUnavailable('request_cancelled');
        }
        final setup = ref.read(setupActionProvider.notifier);
        job.observation = await setup.captureConfigFailure(requestClient);
        final observed = job.observation;
        final selected = ref.read(currentProfileIdProvider);
        if (observed != null &&
            selected != observed.fact.profileId &&
            observed.fact.inputId.isNotEmpty) {
          job.dependencyUnknown = true;
        }
        if (observed != null && selected == observed.fact.profileId) {
          if (selected == profile.id) {
            job.affectedProfile = selected;
          } else if (selected != null) {
            final dependencies = await ConfigInput.acceptedDependencies(
              home: await appPath.homeDirPath,
              accepted: observed.fact,
              readFact: observed.core.getConfigState,
            );
            job.dependencyUnknown = dependencies == null;
            if (dependencies?.contains('profile:${profile.id}') == true) {
              job.affectedProfile = selected;
            }
          }
        }
        job.invalidated = true;
        await requestClient.invalidate('profile:${profile.id}');
        final row = (await database.profilesDao.query().get()).getProfile(
          profile.id,
        );
        final next = (row ?? profile).copyWith(
          label: !job.importing
              ? (row ?? profile).label
              : profile.label.takeFirstValid([
                  getFileNameForDisposition(
                    response.headers['content-disposition']?.firstOrNull,
                  ),
                  profile.id.toString(),
                ]),
          subscriptionInfo: SubscriptionInfo.fromHeaderValues(
            response.headers['subscription-userinfo'],
          ),
          lastUpdateDate: refreshNow,
        );
        await incoming.replace(
          target,
          () => ref
              .read(profilesProvider.notifier)
              .persistRefresh(next, importing: job.importing),
        );
        saved = true;
        job.savedSource = await requestClient.captureSource(
          'profile:${profile.id}',
        );
      });
      retry.failures = 0;
      result = ProfileRefreshResult(
        materialSaved: true,
        application: job.affectedProfile != null || job.dependencyUnknown
            ? ProfileApplicationOutcome.queued
            : ProfileApplicationOutcome.notRequired,
      );
      try {
        if (!_refreshDisposed) {
          await ref.read(profilesProvider.notifier).publishRefresh();
        }
      } catch (_) {
        result = const ProfileRefreshResult(
          materialSaved: true,
          application: ProfileApplicationOutcome.failed,
          failure: 'profile_publish_failed',
        );
      }
    } on RequestUnavailable catch (error) {
      final canceled = const {
        'request_cancelled',
        'bootstrap_required',
      }.contains(error.code);
      final code = switch (error.code) {
        'request_partial_commit' ||
        'profile_download_timeout' ||
        'profile_download_too_large' ||
        'profile_download_failed' ||
        'profile_invalid' => error.code,
        _ =>
          error.code.startsWith('request_') || error.code.startsWith('managed_')
              ? 'request_blocked'
              : 'profile_refresh_failed',
      };
      result = ProfileRefreshResult(
        materialSaved: saved,
        application: canceled
            ? ProfileApplicationOutcome.superseded
            : ProfileApplicationOutcome.failed,
        failure: canceled ? null : code,
      );
      _recordRefreshFailure(job, error.code, saved: saved);
    } catch (_) {
      result = ProfileRefreshResult(
        materialSaved: saved,
        application: ProfileApplicationOutcome.failed,
        failure: 'profile_refresh_failed',
      );
      _recordRefreshFailure(job, 'profile_refresh_failed', saved: saved);
    } finally {
      if (!job.registration.isCompleted) job.registration.complete();
      job.session?.close();
      try {
        await staged?.close();
      } catch (_) {
        result = ProfileRefreshResult(
          materialSaved: saved,
          application: ProfileApplicationOutcome.failed,
          failure: 'profile_cleanup_failed',
        );
      }
      final needsPost =
          job.invalidated &&
          job.observation != null &&
          !(job.urgent && result.materialSaved && result.failure == null);
      if (needsPost) _refreshPosts++;
      if (!job.material.isCompleted) job.material.complete(result);
      _refreshWorker = null;
      _pumpRefresh();
      if (needsPost) {
        unawaited(_finishRefreshPost(job, result));
      } else {
        _completeRefresh(job, result);
      }
    }
  }

  Future<void> _finishRefreshPost(
    _ProfileRefreshJob job,
    ProfileRefreshResult material,
  ) async {
    var outcome = material.application;
    var failure = material.failure;
    var cleanupAttempted = false;
    final observation = job.observation!;
    Future<void> cleanup() async {
      cleanupAttempted = true;
      await ref
          .read(setupActionProvider.notifier)
          .finishConfigFailure(observation, requests: requestClient);
    }

    try {
      if (_refreshDisposed) {
        outcome = ProfileApplicationOutcome.superseded;
        return;
      }
      if (material.materialSaved &&
          material.failure == null &&
          job.affectedProfile != null) {
        Future<bool> current() async {
          if (_refreshDisposed ||
              job.superseded ||
              ref.read(currentProfileIdProvider) != job.affectedProfile ||
              job.savedSource == null ||
              !await requestClient.configSourceCurrent(job.savedSource!)) {
            return false;
          }
          final original = observation.nativeRun;
          if (original == null) return true;
          final native = await requestClient.captureNativeRunState();
          return native != null &&
              native['processEpoch'] == original['processEpoch'] &&
              native['intentRevision'] == original['intentRevision'] &&
              native['intentRunning'] == original['intentRunning'] &&
              native['paused'] == original['paused'];
        }

        outcome = await ref
            .read(setupActionProvider.notifier)
            .applyRefreshedProfile(
              isCurrent: current,
              previous: observation.fact,
            );
      } else if (!material.materialSaved ||
          job.dependencyUnknown ||
          material.failure != null) {
        await cleanup();
        final fact = await observation.core.getConfigState();
        final previous = observation.fact;
        final replaced =
            (
              previous.runtimeEpoch,
              previous.owner,
              previous.token,
              previous.inputId,
            ) !=
            (fact.runtimeEpoch, fact.owner, fact.token, fact.inputId);
        outcome = replaced
            ? ProfileApplicationOutcome.superseded
            : ConfigInput.sameAcceptedInput(previous, fact)
            ? ProfileApplicationOutcome.retained
            : ProfileApplicationOutcome.blocked;
      } else {
        outcome = ProfileApplicationOutcome.notRequired;
      }
    } catch (_) {
      try {
        if (!cleanupAttempted && ref.mounted) {
          await cleanup();
        }
      } catch (_) {}
      if (requestClient.partialCommit) {
        failure = material.materialSaved
            ? 'profile_saved_recovery_required'
            : 'request_partial_commit';
      }
      outcome = ProfileApplicationOutcome.failed;
    } finally {
      _refreshPosts--;
      _completeRefresh(
        job,
        ProfileRefreshResult(
          materialSaved: material.materialSaved,
          application: outcome,
          failure: failure,
        ),
      );
    }
  }

  void _completeRefresh(_ProfileRefreshJob job, ProfileRefreshResult result) {
    job.complete(result);
    if (identical(_refreshJobs[job.profile.id], job)) {
      _refreshJobs.remove(job.profile.id);
      final next = _refreshSuccessors.remove(job.profile.id);
      if (next != null) _refreshJobs[job.profile.id] = next;
    }
    _pumpRefresh();
    _scheduleRefreshTimer();
  }

  _RefreshRetry _retryFor(Profile profile) {
    final retry = _refreshRetries[profile.id];
    if (retry != null &&
        (
              retry.fields.$1,
              retry.fields.$2,
              retry.fields.$3,
              retry.fields.$4,
              retry.fields.$5,
            ) ==
            (
              profile.url,
              profile.requestMode,
              profile.requestProxy,
              profile.autoUpdate,
              profile.autoUpdateDuration,
            )) {
      return retry;
    }
    return _refreshRetries[profile.id] = _RefreshRetry(_refreshFields(profile));
  }

  Duration _automaticDelay(Profile profile) {
    final period = profile.autoUpdateDuration > Duration.zero
        ? profile.autoUpdateDuration
        : const Duration(days: 1);
    final updated = profile.lastUpdateDate;
    final wallDelay = updated == null
        ? 0
        : period.inMilliseconds -
              (refreshNow.millisecondsSinceEpoch -
                  updated.millisecondsSinceEpoch);
    var delay = Duration(milliseconds: wallDelay.clamp(0, 20 * 60 * 1000));
    final retry = _retryFor(profile);
    final attempted = retry.attempted;
    if (attempted != null) {
      // Monotonic retry gaps: 1/2/4/8/16/20 minutes; l1_t06_plan.md §3.4.
      final minutes = retry.failures == 0
          ? 1
          : (1 << (retry.failures - 1).clamp(0, 5)).clamp(1, 20);
      final retryDelay =
          attempted + Duration(minutes: minutes) - refreshElapsed;
      if (retryDelay > delay) delay = retryDelay;
    }
    return delay;
  }

  void _recordRefreshFailure(
    _ProfileRefreshJob job,
    String code, {
    required bool saved,
  }) {
    final retry = _retryFor(job.profile);
    if (saved) {
      retry.failures = 0;
    } else if (code == 'request_cancelled' || code == 'bootstrap_required') {
      return;
    } else if (code.startsWith('request_') || code.startsWith('managed_')) {
      retry.permissionBlocked = true;
    } else {
      retry.failures = (retry.failures + 1).clamp(1, 6);
    }
  }

  void _scheduleRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_refreshDisposed || requestClient.partialCommit) return;
    Duration? earliest;
    for (final profile in ref.read(profilesProvider)) {
      if (!profile.autoUpdate ||
          profile.type == ProfileType.file ||
          _refreshJobs.containsKey(profile.id) ||
          _retryFor(profile).permissionBlocked) {
        continue;
      }
      final delay = _automaticDelay(profile);
      final bounded = delay <= Duration.zero
          ? const Duration(milliseconds: 1)
          : delay > const Duration(minutes: 20)
          ? const Duration(minutes: 20)
          : delay;
      if (earliest == null || bounded < earliest) earliest = bounded;
    }
    if (earliest != null) {
      _refreshTimer = Timer(
        earliest,
        () => unawaited(_wakeRefresh(reconsiderPermission: false)),
      );
    }
  }

  Future<bool> _automaticRunEligible(Profile profile) async {
    final native = await requestClient.captureNativeRunState();
    final allowed =
        native == null ||
        native['phase'] == 'started' &&
            native['intentRunning'] == true &&
            native['paused'] != true;
    if (!allowed) _retryFor(profile).permissionBlocked = true;
    return allowed;
  }

  Future<void> _wakeRefresh({bool reconsiderPermission = true}) async {
    try {
      await _collectRefreshCandidates(
        reconsiderPermission: reconsiderPermission,
      );
    } catch (_) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> _collectRefreshCandidates({
    required bool reconsiderPermission,
  }) async {
    if (_refreshDisposed ||
        requestClient.partialCommit ||
        !requestClient.isAttached) {
      return;
    }
    final profiles = await database.profilesDao.query().get();
    if (_refreshDisposed) return;
    _refreshRetries.removeWhere((id, _) => profiles.getProfile(id) == null);
    for (final job in List.of(_refreshJobs.values)) {
      final row = profiles.getProfile(job.profile.id);
      if (!job.started &&
          (row == null || _refreshFields(row) != _refreshFields(job.profile))) {
        job.cancel();
        _completeRefresh(
          job,
          const ProfileRefreshResult(
            application: ProfileApplicationOutcome.superseded,
          ),
        );
      }
    }
    for (final profile in profiles) {
      final retry = _retryFor(profile);
      if (reconsiderPermission) retry.permissionBlocked = false;
      if (!profile.autoUpdate ||
          profile.type == ProfileType.file ||
          retry.permissionBlocked ||
          _automaticDelay(profile) > Duration.zero) {
        continue;
      }
      if (await _automaticRunEligible(profile)) {
        await _enqueueRefresh(profile, automatic: true);
      }
    }
    _scheduleRefreshTimer();
  }
}
