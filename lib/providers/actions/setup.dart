part of '../action.dart';

typedef _AcceptedLocalInput = ({
  Map<String, dynamic> document,
  ConfigFact expected,
  void Function(String) reportFailure,
});

typedef ConfigFailureObservation = ({
  CoreController core,
  ConfigFact fact,
  Map<String, Object?>? nativeRun,
  int registeredToken,
});

enum _SetupTaskResult {
  completed,
  handoffToCoreRestart,
  foregroundRequired,
  failed,
  superseded,
  staleInput,
}

bool _sameSetupRun(
  Map<String, Object?> expected,
  Map<String, Object?> current, {
  int? token,
}) =>
    current['processEpoch'] == expected['processEpoch'] &&
    current['intentRevision'] == expected['intentRevision'] &&
    current['configToken'] == (token ?? expected['configToken']);

class _RunRequest {
  final bool running;
  final bool initialize;
  final bool paused;
  final DateTime? previousStartTime;
  final Future<int?> nativeRequest;
  final bool allowBootstrap;
  final bool allowSourceReview;
  final bool reportFailure;
  final int? setupSequence;

  const _RunRequest({
    required this.running,
    required this.initialize,
    required this.paused,
    required this.previousStartTime,
    required this.nativeRequest,
    this.allowBootstrap = false,
    this.allowSourceReview = true,
    this.reportFailure = false,
    this.setupSequence,
  });
}

class _SetupInputs {
  const _SetupInputs({
    required this.state,
    required this.profile,
    required this.patch,
    required this.network,
    required this.overrideDns,
    required this.overrideNtp,
    required this.safeMode,
    required this.testUrl,
    required this.picks,
    required this.shared,
    required this.vpn,
    required this.fact,
    required this.policy,
  });

  final SetupState state;
  final Profile profile;
  final PatchClashConfig patch;
  final NetworkProps network;
  final bool overrideDns, overrideNtp, safeMode;
  final String testUrl;
  final Map<String, String> picks;
  final SharedState shared;
  final VpnState vpn;
  final ConfigFact fact;
  final SelectedPolicy? policy;

  _SetupInputs resolved(SelectedPolicy next) {
    final selected = Map<String, String>.unmodifiable(
      next.picks(profile.selectedMap),
    );
    return _SetupInputs(
      state: state,
      profile: profile,
      patch: patch,
      network: network,
      overrideDns: overrideDns,
      overrideNtp: overrideNtp,
      safeMode: safeMode,
      testUrl: testUrl,
      picks: selected,
      shared: shared.copyWith(
        setupParams: SetupParams(selectedMap: selected, testUrl: testUrl),
      ),
      vpn: vpn,
      fact: fact,
      policy: next,
    );
  }
}

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction with _PolicyMaterialSetup {
  SetupAction() : _android = null, _native = null, _requestClient = null;

  @visibleForTesting
  SetupAction.scoped({
    required bool isAndroid,
    required Service native,
    required Request requests,
  }) : _android = isAndroid,
       _native = native,
       _requestClient = requests;

  final bool? _android;
  final Service? _native;
  final Request? _requestClient;
  bool get _isAndroid => _android ?? system.isAndroid;
  Service? get _service => _native ?? service;
  @override
  Request get _requests => _requestClient ?? request;

  @override
  CoreController get _core => ref.read(coreHandlerProvider);

  Future<ConfigFailureObservation?> captureConfigFailure(Request client) async {
    if (!client.hasNativeClient && !ref.read(initProvider)) return null;
    final core = _core;
    final nativeRun = await client.captureNativeRunState();
    final fact = await core.getConfigState();
    return (
      core: core,
      fact: fact,
      nativeRun: nativeRun,
      registeredToken:
          (nativeRun?['configToken'] as num?)?.toInt() ?? fact.token,
    );
  }

  Future<void> finishConfigFailure(
    ConfigFailureObservation observation, {
    Request? requests,
  }) async {
    late ConfigApplyResult result;
    try {
      result = await observation.core.failConfigBuild({
        'expected': observation.fact.fence,
        'expectedRun': ?observation.nativeRun,
        'registeredToken': observation.registeredToken,
      });
      if (!const {
        'retained',
        'blocked',
        'superseded',
      }.contains(result.status)) {
        throw const RequestUnavailable('request_partial_commit');
      }
    } catch (_) {
      try {
        await (requests ?? _requests).markRecoveryRequired();
      } catch (_) {}
      throw const RequestUnavailable('request_partial_commit');
    }
    if (!ref.mounted || result.status == 'superseded') return;
    ref
        .read(configStateProvider.notifier)
        .accept(result.fact, authoritative: true);
    if (ref.read(configStateProvider).fact.token == result.fact.token) {
      if (!result.fact.businessActive) _setLocalRunning(false);
      ref.read(configStateProvider.notifier).markBuildFailure();
    }
  }

  Timer? _runtimeTimer;
  final _setupScheduler = SerialTaskScheduler();
  final _listenerScheduler = SerialTaskScheduler();
  _RunRequest? _latestRunRequest;
  int _runOperation = 0;
  DateTime? _startTime;
  int _setupSequence = 0;
  int _setupGeneration = 0;

  bool get _isRunning => _startTime != null && _startTime!.isBeforeNow;

  @override
  void build() {
    ref.onDispose(_stopRuntimeTicker);
    if (_isAndroid) {
      ref.listen(nativeRequestStateProvider, (_, next) {
        if (next['phase'] != 'started') {
          _stopRuntimeTicker();
          if (next['phase'] == 'failed' || next['phase'] == 'stopped') {
            _startTime = null;
          }
          ref.read(runTimeProvider.notifier).value = null;
        } else {
          unawaited(_syncNativeRuntime(next));
        }
      });
    }

    ref.listen(appVisibleProvider, (_, _) => _syncRuntimeTicker());
    ref.listen(
      appSettingProvider.select((state) => state.showTrayTitle),
      (_, _) => _syncRuntimeTicker(),
    );
  }

  bool get _isTrafficShown =>
      ref.read(appVisibleProvider) ||
      (system.isMacOS &&
          !ref.read(safeModeProvider) &&
          ref.read(appSettingProvider).showTrayTitle);

  Future<bool> fullSetup() async {
    if (!ref.read(initProvider)) return true;
    ref.read(proxiesActionProvider.notifier).cancelDelayTests();
    ref.read(delayDataSourceProvider.notifier).value = {};
    final setupResult = applyProfile(force: true);
    ref.read(logsProvider.notifier).value = FixedList(maxLogsLength);
    ref.read(requestsProvider.notifier).value = FixedList(maxRequestsLength);
    ref.read(dnsQueriesProvider.notifier).value = FixedList(
      maxDnsQueriesLength,
    );
    ref.read(dnsQueryCountProvider.notifier).value = 0;
    ref.read(requestCountProvider.notifier).value = 0;
    try {
      return await setupResult;
    } catch (e, s) {
      commonPrint.log('fullSetup ===> ${compactError(e)}, $s');
      return false;
    }
  }

  void _setLocalRunning(bool running) {
    _stopRuntimeTicker();
    if (!running) {
      _startTime = null;
      debouncer.cancel(FunctionTag.applyProfile);
      _updateRunTime();
      return;
    }

    _startTime ??= DateTime.now();
    _updateRunTime();
    _syncRuntimeTicker();
  }

  void _syncRuntimeTicker() {
    if (_startTime == null || !_isTrafficShown) {
      _stopRuntimeTicker();
      return;
    }
    if (_runtimeTimer != null) {
      return;
    }
    _refreshRunningState();
    _runtimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRunningState(),
    );
  }

  void _stopRuntimeTicker() {
    _runtimeTimer?.cancel();
    _runtimeTimer = null;
  }

  void _refreshRunningState() {
    _updateRunTime();
    unawaited(ref.read(commonActionProvider.notifier).updateTraffic());
  }

  void _updateRunTime() {
    final startTime = _startTime;
    ref.read(runTimeProvider.notifier).value = startTime == null
        ? null
        : DateTime.now().millisecondsSinceEpoch -
              startTime.millisecondsSinceEpoch;
  }

  bool _nativeSnapshotCurrent(Map<String, Object?> snapshot) {
    if (!ref.mounted) return false;
    final current = ref.read(nativeRequestStateProvider);
    return current['processEpoch'] == snapshot['processEpoch'] &&
        current['revision'] == snapshot['revision'] &&
        current['phase'] == snapshot['phase'];
  }

  Future<void> _syncNativeRuntime(Map<String, Object?> snapshot) async {
    if (snapshot['phase'] != 'started') return;
    try {
      final startedAt = await _service?.getRunTime();
      if (!_nativeSnapshotCurrent(snapshot)) return;
      _startTime = startedAt;
      if (startedAt == null) {
        _stopRuntimeTicker();
        ref.read(runTimeProvider.notifier).value = null;
      } else {
        _setLocalRunning(true);
      }
    } catch (_) {
      if (_nativeSnapshotCurrent(snapshot)) {
        ref.read(runTimeProvider.notifier).value = null;
      }
    }
  }

  Future<void> _updateStartTime() async {
    _startTime = await _service?.getRunTime();
  }

  Future<void> initStatus({
    bool recovery = false,
    Future<bool> Function()? isCurrent,
  }) async {
    if (recovery) {
      if (isCurrent != null && !await isCurrent()) return;
      if (_isAndroid) {
        final snapshot = await _service!.getRequestState();
        if (isCurrent != null && !await isCurrent()) return;
        await _service!.initializeRequestState(
          snapshot['revision'] as int,
          recovery: true,
        );
        final latest = await _service!.getRequestState();
        if (isCurrent != null && !await isCurrent()) return;
        ref.read(nativeRequestStateProvider.notifier).onRequestState(latest);
        if (_nativeSnapshotCurrent(latest)) {
          if (latest['phase'] == 'started') {
            await _syncNativeRuntime(latest);
          } else {
            _setLocalRunning(false);
          }
        }
      }
      globalState.needInitStatus = false;
      return;
    }
    if (!globalState.needInitStatus) {
      commonPrint.log('init status cancel');
      return;
    }
    commonPrint.log('init status');
    Map<String, Object?>? native;
    if (_isAndroid) {
      final snapshot = await _service!.getRequestState();
      await _service!.initializeRequestState(snapshot['revision'] as int);
      native = await _service!.getRequestState();
      await _updateStartTime();
    }
    final shouldRun =
        native?['intentRunning'] == true ||
        _isRunning ||
        ref.read(appSettingProvider).autoRun;
    if (isCurrent != null && !await isCurrent()) return;
    if (_isAndroid &&
        native?['phase'] == 'started' &&
        native?['intentRunning'] == true) {
      try {
        final existing = await _core.getConfigState();
        if (isCurrent != null && !await isCurrent()) return;
        if (existing.businessActive &&
            existing.phase == 'ready' &&
            existing.profileId == ref.read(currentProfileIdProvider)) {
          ref
              .read(configStateProvider.notifier)
              .accept(existing, authoritative: true);
          await _syncNativeRuntime(native!);
          await ref.read(proxiesActionProvider.notifier).updateGroups();
          globalState.needInitStatus = false;
          return;
        }
      } catch (error) {
        commonPrint.log(
          'Existing configuration unavailable: ${compactError(error)}',
        );
      }
    }
    if (shouldRun) {
      await setRunning(
        true,
        initialize: true,
        source: 'bootstrap',
        preparedRequestId: native?['intentRunning'] == true
            ? native!['intentRevision'] as int
            : null,
        paused: native?['paused'] as bool?,
      );
    } else {
      await globalState.safeRun(
        () => applyProfile(force: true, allowSourceReview: false),
      );
    }
  }

  Future<bool> setRunning(
    bool running, {
    bool initialize = false,
    int? preparedRequestId,
    String source = 'ui',
    bool? paused,
  }) {
    if (running && !initialize && !ref.read(initProvider)) {
      return Future.value(true);
    }

    _runOperation++;
    final allowBootstrap =
        _isAndroid &&
        running &&
        !initialize &&
        preparedRequestId == null &&
        source == 'ui' &&
        !(paused ?? ref.read(suspendProvider));
    final request = _RunRequest(
      running: running,
      initialize: running && initialize,
      paused: _isAndroid && (paused ?? ref.read(suspendProvider)),
      previousStartTime: _startTime,
      allowBootstrap: allowBootstrap,
      allowSourceReview:
          source == 'ui' && !initialize && ref.read(appVisibleProvider),
      reportFailure: source == 'tile' || source == 'notification',
      setupSequence: allowBootstrap ? reserveSetupSequence() : null,
      nativeRequest: preparedRequestId != null
          ? Future.value(preparedRequestId)
          : _service?.prepareRunIntent(
                  running: running,
                  source: source,
                  paused: paused ?? ref.read(suspendProvider),
                ) ??
                Future.value(null),
    );
    return _queueRunRequest(request);
  }

  Future<bool> _queueRunRequest(_RunRequest request) {
    _latestRunRequest = request;
    if (!request.running || request.paused) {
      _setupGeneration = ++_setupSequence;
      unawaited(
        ref.read(profilesActionProvider.notifier)._cancelExpiredDemands(),
      );
      _setLocalRunning(false);
    }
    if (request.initialize) {
      globalState.needInitStatus = false;
    }
    return _dispatchRunRequest(request);
  }

  Future<bool> _dispatchRunRequest(_RunRequest request) async {
    final requestId = await request.nativeRequest;
    if (!_isCurrent(request)) return false;
    Future<bool> dispatch() =>
        request.running && !request.paused ? _start(request) : _stop(request);
    return requestId == null
        ? dispatch()
        : RunRequestScope.run(requestId, dispatch);
  }

  Future<void> setPaused(bool paused) async {
    final native = _service;
    if (native == null) return;
    final operation = ++_runOperation;
    _latestRunRequest = null;
    final snapshot = await native.preparePauseIntent(paused);
    if (!ref.mounted || operation != _runOperation) return;
    final requestId = snapshot['intentRevision'];
    final epoch = snapshot['processEpoch'];
    if (requestId is! int ||
        epoch is! String ||
        epoch.isEmpty ||
        snapshot['source'] != 'ssid' ||
        snapshot['paused'] != paused ||
        snapshot['intentRunning'] is! bool) {
      throw StateError('Pause request unavailable');
    }
    final observed = ref.read(nativeRequestStateProvider);
    if (observed['processEpoch'] != null && observed['processEpoch'] != epoch) {
      return;
    }
    ref.read(nativeRequestStateProvider.notifier).onRequestState(snapshot);
    if (snapshot['phase'] == 'failed' || snapshot['reason'] == 'exiting') {
      throw StateError('Pause request unavailable');
    }
    final current = ref.read(nativeRequestStateProvider);
    // Network observations can advance revision without superseding this intent.
    if (current['intentRevision'] != requestId ||
        current['intentRunning'] != snapshot['intentRunning'] ||
        current['paused'] != paused ||
        current['phase'] == 'failed' ||
        current['reason'] == 'exiting') {
      return;
    }
    await _queueRunRequest(
      _RunRequest(
        running: snapshot['intentRunning'] == true,
        initialize: false,
        paused: paused,
        previousStartTime: _startTime,
        nativeRequest: Future.value(requestId),
        allowSourceReview: false,
      ),
    );
  }

  Future<bool> _start(_RunRequest request) async {
    var applied = false;
    Map<String, Object?>? notificationRequest;
    try {
      if (_isAndroid && request.reportFailure) {
        notificationRequest = await _service!.getRequestState();
      }
      if (!_isCurrent(request)) return false;
      applied = await applyProfile(
        force: true,
        allowSourceReview: request.allowSourceReview,
        allowBootstrap: request.allowBootstrap,
        setupSequence: request.setupSequence,
      );
    } catch (_) {
      applied = false;
    }
    if (!_isCurrent(request)) return false;
    if (applied) {
      if (_isAndroid) await _updateStartTime();
      if (!_isCurrent(request)) return false;
      _setLocalRunning(
        !request.paused &&
            !ref.read(suspendProvider) &&
            !ref.read(safeModeProvider) &&
            (!_isAndroid || _startTime != null),
      );
    }
    if (!applied && notificationRequest != null) {
      try {
        final requestId = await request.nativeRequest;
        final latest = await _service!.getRequestState();
        if (_isCurrent(request) &&
            latest['processEpoch'] == notificationRequest['processEpoch'] &&
            latest['intentRevision'] == requestId &&
            latest['phase'] == 'failed') {
          await reportStartFailure(
            currentAppLocalizations.backgroundStartFailed,
          );
        }
      } catch (error) {
        commonPrint.log(
          'Unable to report quick action failure: ${compactError(error)}',
        );
      }
    }
    return applied;
  }

  @protected
  Future<void> reportStartFailure(String message) async {
    await app?.tip(message);
  }

  Future<bool> _stop(_RunRequest request) async {
    try {
      await _setCoreRunning(request);
    } catch (_) {
      _rollbackRunning(request);
      rethrow;
    }
    if (!_isCurrent(request)) {
      return true;
    }
    resetCoreTraffic();
    ref.read(trafficsProvider.notifier).clear();
    ref.read(totalTrafficProvider.notifier).value = const Traffic();
    return true;
  }

  Future<void> _setCoreRunning(_RunRequest request) {
    return _listenerScheduler.run(() async {
      if (!_isCurrent(request)) {
        return;
      }
      if (!_isAndroid && request.running && ref.read(suspendProvider)) {
        return;
      }
      if (ref.read(safeModeProvider)) {
        return;
      }
      final requestId = await request.nativeRequest;
      final running = request.running && !request.paused;
      if (requestId == null) {
        if (!await setCoreRunning(running)) {
          throw StateError('Core transition failed');
        }
      } else {
        if (!await RunRequestScope.run(
          requestId,
          () => setCoreRunning(running),
        )) {
          throw StateError('Core transition failed');
        }
      }
    });
  }

  void _rollbackRunning(_RunRequest request) {
    if (!_isCurrent(request)) {
      return;
    }
    if (_isAndroid) {
      _setLocalRunning(false);
      return;
    }
    _startTime = request.previousStartTime;
    _setLocalRunning(_startTime != null);
  }

  bool _isCurrent(_RunRequest request) => identical(_latestRunRequest, request);

  Future<void> updateConfigDebounce() async {
    debouncer.call(FunctionTag.updateConfig, updateConfig);
  }

  @protected
  Future<bool> setCoreRunning(bool running) {
    return running ? _core.startListener() : _core.stopListener();
  }

  @protected
  void resetCoreTraffic() {
    _core.resetTraffic();
  }

  @visibleForTesting
  Future<void> updateConfig() async {
    await globalState.safeRun(() async {
      final profileId = ref.read(currentProfileIdProvider);
      if (profileId != null &&
          await database.profilePolicySelectionsDao
                  .query(profileId)
                  .getSingleOrNull() !=
              null) {
        await applyProfile(force: true);
        return;
      }
      final patchConfig = ref.read(patchClashConfigProvider);
      final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
      if (!shouldContinueSetup) {
        await _restartCoreAfterAuthorization();
        return;
      }
      final networkSetting = ref.read(networkSettingProvider);
      final message = await _core.updateConfig(
        _effectivePatchConfig(patchConfig).toUpdateParams(
          routeMode: networkSetting.routeMode,
          authentication: networkSetting.authentication.credentials,
        ),
      );
      if (message == 'configuration_reapply_required' ||
          message == 'config is not applied') {
        if (!await applyProfile(force: true)) {
          throw MessageException(currentAppLocalizations.configRetained);
        }
      } else if (message.isNotEmpty) {
        throw MessageException(message);
      }
    });
  }

  void applyProfileDebounce({
    bool silence = false,
    bool force = false,
    bool allowSourceReview = false,
    Future<bool> Function()? isCurrent,
  }) {
    debouncer.call(FunctionTag.applyProfile, () async {
      if (isCurrent == null) {
        await applyProfile(
          silence: silence,
          force: force,
          allowSourceReview: allowSourceReview,
        );
      } else {
        await _runSetup(
          silence: silence,
          force: force,
          isCurrent: isCurrent,
          allowSourceReview: allowSourceReview,
        );
      }
    });
  }

  Future<void> changeMode(Mode mode) async {
    await ref
        .read(applicationInputActionProvider.notifier)
        .updatePatch((state) => state.copyWith(mode: mode));
    if (mode == Mode.global) {
      ref
          .read(proxiesActionProvider.notifier)
          .updateCurrentGroupName(GroupName.GLOBAL.name);
    }
  }

  void autoApplyProfile() {
    runAfterFrame(() => applyProfile(allowSourceReview: false));
  }

  int reserveSetupSequence() => ++_setupSequence;

  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    bool allowSourceReview = false,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
  }) async {
    if (expectedRun != null &&
        (!_isAndroid ||
            !_sameSetupRun(expectedRun, await _service!.getRequestState()))) {
      return false;
    }
    final previous = ref.read(configStateProvider).fact;
    final result = await _runSetup(
      preferHot:
          _requests.requiresSourceAcceptance &&
          previous.businessActive &&
          !previous.isManaged &&
          previous.profileId == ref.read(currentProfileIdProvider),
      force: force,
      silence: silence,
      allowSourceReview: allowSourceReview,
      allowBootstrap: allowBootstrap,
      expectedRun: expectedRun,
      setupSequence: setupSequence,
    );
    return result == _SetupTaskResult.completed;
  }

  Future<ProfileApplicationOutcome> applyRefreshedProfile({
    required Future<bool> Function() isCurrent,
    required ConfigFact previous,
    Future<bool> Function()? canSubmit,
    bool allowSourceReview = false,
  }) async {
    if (!await isCurrent()) return ProfileApplicationOutcome.superseded;
    ConfigApplyResult? accepted;
    final result = await _runSetup(
      silence: true,
      force: true,
      preferHot:
          _requests.requiresSourceAcceptance &&
          previous.businessActive &&
          !previous.isManaged,
      allowSourceReview: allowSourceReview,
      isCurrent: isCurrent,
      canSubmit: canSubmit,
      onApplied: (value) => accepted = value,
    );
    if (result == _SetupTaskResult.superseded ||
        result == _SetupTaskResult.staleInput) {
      return ProfileApplicationOutcome.superseded;
    }
    if (result == _SetupTaskResult.completed && accepted != null) {
      return const {'activated', 'applied'}.contains(accepted!.status)
          ? ProfileApplicationOutcome.activated
          : ProfileApplicationOutcome.installedInactive;
    }
    final fact = await _core.getConfigState();
    return ConfigInput.sameAcceptedInput(previous, fact)
        ? ProfileApplicationOutcome.retained
        : fact.businessActive ||
              const {'ready', 'installed'}.contains(fact.phase)
        ? ProfileApplicationOutcome.failed
        : ProfileApplicationOutcome.blocked;
  }

  Future<_SetupTaskResult> _runSetup({
    _AcceptedLocalInput? acceptedLocalInput,
    bool silence = false,
    bool force = false,
    bool allowSourceReview = false,
    bool preferHot = false,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
    Future<bool> Function()? isCurrent,
    void Function(ConfigApplyResult)? onApplied,
    Future<bool> Function()? canSubmit,
  }) async {
    final sequence = setupSequence ?? reserveSetupSequence();
    if (sequence <= _setupGeneration) return _SetupTaskResult.superseded;
    var triggerRun = expectedRun;
    if (_isAndroid && allowBootstrap && triggerRun == null) {
      final requestId = RunRequestScope.current;
      if (requestId == null) return _SetupTaskResult.superseded;
      final observed = await _service!.getRequestState();
      if (observed['intentRevision'] != requestId) {
        return _SetupTaskResult.superseded;
      }
      triggerRun = Map.unmodifiable(observed);
    }
    Future<bool> triggerCurrent() async =>
        triggerRun == null ||
        _sameSetupRun(triggerRun, await _service!.getRequestState());
    if (!await triggerCurrent() ||
        isCurrent != null && !await isCurrent() ||
        sequence <= _setupGeneration) {
      return _SetupTaskResult.superseded;
    }
    // Issuing an order ticket must not invalidate the admitted setup owner.
    final generation = _setupGeneration = sequence;
    unawaited(
      ref.read(profilesActionProvider.notifier)._cancelExpiredDemands(),
    );
    Future<void>? deferredCleanup;
    Future<bool> current() async {
      if (isCurrent != null && !await isCurrent()) return false;
      return generation == _setupGeneration;
    }

    final result = await _setupScheduler.run(() async {
      if (!await current() ||
          !await triggerCurrent() ||
          generation != _setupGeneration) {
        return _SetupTaskResult.superseded;
      }
      ref.read(profilesActionProvider.notifier).setupExecutionChanged(true);
      final progress = ref.read(proxyPreparationProvider.notifier);
      final progressSequence = progress.start();
      var progressFailed = true;
      try {
        await dataMutations.run(() async {});
        if (!await current() ||
            !await triggerCurrent() ||
            generation != _setupGeneration) {
          return _SetupTaskResult.superseded;
        }
        Future<_SetupTaskResult> run({
          bool retryAllowed = true,
          bool inline = true,
        }) => _setupConfig(
          force: force,
          acceptedLocalInput: acceptedLocalInput,
          onPreparation: (phase) => progress.phase(progressSequence, phase),
          allowSourceReview: allowSourceReview,
          preferHot: preferHot && inline,
          allowBootstrap: allowBootstrap,
          expectedRun: triggerRun,
          silence: silence,
          isCurrent: current,
          isLatestSetup: () => generation == _setupGeneration,
          onCleanupDeferred: (cleanup) => deferredCleanup = cleanup,
          onApplied: onApplied,
          canSubmit: canSubmit,
          retryAllowed: retryAllowed,
          onUpdated: (current) async {
            await ref
                .read(proxiesActionProvider.notifier)
                .updateGroups(isCurrent: current);
            await ref
                .read(providersProvider.notifier)
                .syncProviders(isCurrent: current);
          },
        );
        final first = await run();
        if (first == _SetupTaskResult.foregroundRequired &&
            acceptedLocalInput != null &&
            ref.read(appVisibleProvider) &&
            await current() &&
            await triggerCurrent()) {
          final full = await run(inline: false);
          progressFailed = full == _SetupTaskResult.failed;
          return full;
        }
        if (first != _SetupTaskResult.staleInput || !await current()) {
          progressFailed =
              first == _SetupTaskResult.failed ||
              first == _SetupTaskResult.foregroundRequired;
          return first;
        }
        final second = await run(retryAllowed: false);
        progressFailed = second == _SetupTaskResult.failed;
        return second == _SetupTaskResult.staleInput
            ? _SetupTaskResult.superseded
            : second;
      } finally {
        if (ref.mounted) {
          progress.finish(progressSequence, failed: progressFailed);
          ref
              .read(profilesActionProvider.notifier)
              .setupExecutionChanged(false);
        }
      }
    });
    await deferredCleanup;
    if (result != _SetupTaskResult.handoffToCoreRestart) {
      return result;
    }
    if (!await triggerCurrent()) return _SetupTaskResult.superseded;
    // Release the current serial task before restartCore reapplies the profile.
    final restarted = await _restartCoreAfterAuthorization();
    return restarted ? _SetupTaskResult.completed : _SetupTaskResult.failed;
  }

  Future<void> _finishPreparationAfterQueue(
    Future<void> Function() cleanup,
  ) async {
    while (true) {
      final generation = _setupGeneration;
      final finished = await _setupScheduler.run(() async {
        if (generation != _setupGeneration) return false;
        await cleanup();
        return true;
      });
      if (finished) return;
    }
  }

  Future<bool> _restartCoreAfterAuthorization() async {
    try {
      return await ref.read(coreActionProvider.notifier).restartCore();
    } catch (_) {
      ref.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.none;
      rethrow;
    }
  }

  Future<({String yaml, String md5})> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    NetworkProps? network,
    bool? dnsOverride,
    bool? ntpOverride,
    bool? safeMode,
    bool allowSourceReview = false,
    Future<bool> Function()? isCurrent,
    void Function(Map<String, Object?>)? onSourceUse,
    void Function(Map<String, Object?>)? onRuleLedger,
    Map<String, dynamic>? previewDocument,
    bool previewOwnRouting = false,
  }) async {
    final profileId = setupState.profileId;
    if (profileId == null) return (yaml: '', md5: '');
    final defaultUA = globalState.packageInfo.ua;
    final NetworkProps networkSetting =
        network ?? ref.read<NetworkProps>(networkSettingProvider);
    final bool overrideDns = dnsOverride ?? ref.read<bool>(overrideDnsProvider);
    final bool overrideNtp = ntpOverride ?? ref.read<bool>(overrideNtpProvider);
    final appendSystemDns = networkSetting.appendSystemDns;
    final routeMode = networkSetting.routeMode;
    final profile = _requests.requiresSourceAcceptance
        ? (await database.profilesDao.query().get()).getProfile(profileId)
        : null;
    final needsAcceptance =
        _requests.requiresSourceAcceptance && previewDocument == null;
    if (needsAcceptance && profile == null) {
      throw const RequestUnavailable('request_cancelled');
    }
    final path = await appPath.getProfilePath(profileId.toString());
    if (needsAcceptance && !await File(path).exists()) {
      throw const RequestUnavailable('source_review_required');
    }
    final sourceBody = needsAcceptance
        ? await _sourceBody(path, preserveBom: true)
        : null;
    final source = await _requests.captureSource('profile:$profileId');
    final acceptedSource = needsAcceptance
        ? await _reviewProfileSource(
            confirm: ref.read(sourceConfirmationProvider),
            core: _core,
            requests: _requests,
            profile: profile!,
            path: path,
            body: sourceBody,
            source: source,
            automatic: !allowSourceReview || !ref.read(appVisibleProvider),
            isCurrent: isCurrent,
          )
        : null;
    final deniedRouting = previewDocument != null
        ? previewOwnRouting
        : acceptedSource?.routing == 'own';
    if (acceptedSource != null) onSourceUse?.call(acceptedSource.use);
    if (deniedRouting && setupState.matchTarget?.trim().isNotEmpty != true) {
      throw MessageException(currentAppLocalizations.sourceOwnDefaultRequired);
    }
    final configMap =
        previewDocument ??
        (needsAcceptance
            ? await _sourceAcceptance(
                _core,
                _requests,
                confirm: ref.read(sourceConfirmationProvider),
              ).project(
                source: source,
                identity: _profileSourceIdentity(profile!),
                body: sourceBody!,
              )
            : await _core.getConfig(profileId));
    String? scriptContent;
    final List<Rule> addedRules = [];
    final List<CustomProxy> proxies = [];
    final List<ProxyGroup> proxyGroups = [];
    final List<Rule> rules = [];
    if (setupState.overwriteType == OverwriteType.script) {
      scriptContent = await setupState.script?.content;
    } else if (setupState.overwriteType == OverwriteType.standard) {
      addedRules.addAll(setupState.addedRules);
    } else {
      proxies.addAll(setupState.customProxies);
      proxyGroups.addAll(setupState.proxyGroups);
      rules.addAll(setupState.rules);
    }
    final realPatchConfig = patchConfig.copyWith(
      tun: patchConfig.tun.getRealTun(routeMode),
    );
    Map<String, dynamic> rawConfig = configMap;
    Map<String, Object?>? scriptUse;
    if (scriptContent?.isNotEmpty == true) {
      final accepted = await _reviewScriptSource(
        confirm: ref.read(sourceConfirmationProvider),
        core: _core,
        requests: _requests,
        script: setupState.script!,
        body: scriptContent!,
        automatic:
            previewDocument != null ||
            !allowSourceReview ||
            !ref.read(appVisibleProvider),
        isCurrent: isCurrent,
      );
      if (accepted != null) {
        onSourceUse?.call(accepted.use);
        scriptUse = accepted.use;
      }
      if (isCurrent != null && !await isCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
      rawConfig = _requests.requiresSourceAcceptance
          ? await handleAcceptedEvaluate(
              scriptContent,
              rawConfig,
              permit: accepted?.scriptPermit,
            )
          : await handleEvaluate(scriptContent, rawConfig);
    }
    final directory = await appPath.profilesPath;
    final injected = await _resolveInjectedProviders(
      setupState,
      proxyGroups: proxyGroups,
      rules: rules,
      allowSourceReview: allowSourceReview,
      isCurrent: isCurrent,
      onSourceUse: onSourceUse,
      preview: previewDocument != null,
    );
    try {
      final composition = await makeProfileCompositionTask(
        MakeRealProfileState(
          rules: rules,
          proxies: proxies,
          proxyGroups: proxyGroups,
          localGroups: setupState.localGroups,
          injectedProxyProviders: injected.proxies,
          injectedRuleProviders: injected.rules,
          profilesPath: directory,
          profileId: profileId,
          rawConfig: rawConfig,
          realPatchConfig: realPatchConfig,
          overrideDns: overrideDns,
          overrideNtp: overrideNtp,
          appendSystemDns: appendSystemDns,
          addedRules: addedRules,
          defaultUA: defaultUA,
          authentication: networkSetting.authentication.credentials,
          matchTarget: setupState.matchTarget,
          sourceRoutingDenied: deniedRouting,
          safeMode: safeMode ?? ref.read(safeModeProvider),
          policySelection: setupState.policySelection,
        ),
        origins: {
          'profileKey': 'profile:$profileId',
          if (acceptedSource != null)
            'profileRevision': acceptedSource.use['digest'] as String,
          if (scriptUse != null) 'scriptKey': scriptUse['key'] as String,
        },
      );
      onRuleLedger?.call(composition.ledger);
      return (yaml: composition.yaml, md5: composition.md5);
    } on FormatException catch (error) {
      final l10n = currentAppLocalizations;
      final message = switch (error.message) {
        'sourceOwnRoutingUnmatchedRequired' => l10n.sourceOwnDefaultRequired,
        'sourceOwnRoutingDefaultConflict' => l10n.sourceOwnDefaultConflict,
        'sourceOwnRoutingRematchDenied' => l10n.sourceRematchDenied,
        _ => null,
      };
      if (message == null) rethrow;
      throw MessageException(message);
    }
  }

  /// Only what the overwrite actually references is injected, so an app-level
  /// provider costs nothing in the profiles that never name it.
  Future<({Map<String, dynamic> proxies, Map<String, dynamic> rules})>
  _resolveInjectedProviders(
    SetupState setupState, {
    required List<ProxyGroup> proxyGroups,
    required List<Rule> rules,
    required bool allowSourceReview,
    Future<bool> Function()? isCurrent,
    void Function(Map<String, Object?>)? onSourceUse,
    bool preview = false,
  }) async {
    final usedProxyProviders = <String>{
      for (final proxyGroup in proxyGroups) ...?proxyGroup.use,
    };
    final usedRuleProviders = <String>{
      for (final rule in rules)
        if (rule.ruleAction == RuleAction.RULE_SET && rule.ruleProvider != null)
          rule.ruleProvider!,
    };
    if (usedProxyProviders.isEmpty && usedRuleProviders.isEmpty) {
      return (
        proxies: const <String, dynamic>{},
        rules: const <String, dynamic>{},
      );
    }
    final proxies = <String, dynamic>{};
    for (final entry in setupState.profileProviders.entries) {
      if (!usedProxyProviders.contains(entry.key)) {
        continue;
      }
      final path = await appPath.getProfilePath(entry.value.toString());
      if (_requests.requiresSourceAcceptance && !preview) {
        final profile = (await database.profilesDao.query().get()).getProfile(
          entry.value,
        );
        if (profile == null) {
          throw const RequestUnavailable('request_cancelled');
        }
        final accepted = await _reviewProfileSource(
          core: _core,
          requests: _requests,
          profile: profile,
          path: path,
          kind: 'provider-proxy',
          automatic: !allowSourceReview || !ref.read(appVisibleProvider),
          confirm: ref.read(sourceConfirmationProvider),
          isCurrent: isCurrent,
        );
        if (accepted != null) onSourceUse?.call(accepted.use);
      }
      proxies[entry.key] = {'type': 'file', 'path': path};
    }
    final ruleProviders = <String, dynamic>{};
    for (final provider in setupState.clashProviders) {
      final used = switch (provider.kind) {
        ProviderKind.proxy => usedProxyProviders,
        ProviderKind.rule => usedRuleProviders,
      };
      if (!used.contains(provider.label)) {
        continue;
      }
      if (provider.kind == ProviderKind.proxy &&
          proxies.containsKey(provider.label)) {
        commonPrint.log(
          'proxy provider ${provider.label} shadowed by the profile of that name',
          logLevel: LogLevel.warning,
        );
        continue;
      }
      final definition = provider.definition(await provider.path);
      if (_requests.requiresSourceAcceptance && !preview) {
        final key = 'clash-provider:${provider.id}';
        final source = await _requests.captureSource(key);
        final automatic = !allowSourceReview || !ref.read(appVisibleProvider);
        Future<void> review(List<int> body) async {
          final accepted =
              await _sourceAcceptance(
                _core,
                _requests,
                confirm: ref.read(sourceConfirmationProvider),
              ).review(
                source: source,
                identity: _clashProviderSourceIdentity(provider),
                settings: definition,
                body: '',
                binaryBody: body,
                label: provider.label,
                location: provider.url,
                kind: provider.kind == ProviderKind.proxy
                    ? 'provider-proxy'
                    : 'provider-rule',
                format: provider.format?.name,
                behavior: provider.behavior?.name,
                automatic: automatic,
                isCurrent: isCurrent,
              );
          try {
            onSourceUse?.call(accepted.use);
          } finally {
            await accepted.release();
          }
        }

        final reviewedBody = SourceReviewBatchStore.forRequests(_requests)
            .material(
              'profile:${setupState.profileId}',
              key,
              provider.kind == ProviderKind.proxy
                  ? 'provider-proxy'
                  : 'provider-rule',
              definition,
              source.client,
            );
        final file = File(await provider.path);
        if (await file.exists()) {
          if (await file.length() > 16 * 1024 * 1024) {
            throw const RequestUnavailable('profile_download_too_large');
          }
          await review(reviewedBody ?? await file.readAsBytes());
        } else if (provider.isRemote) {
          await _requests.withSession(
            key: key,
            url: provider.url,
            automatic: automatic,
            sourceIsCurrent: isCurrent,
            action: (session) async {
              final response = reviewedBody == null
                  ? await _requests.downloadFileForUrl(provider.url)
                  : null;
              try {
                final body =
                    reviewedBody ?? await response!.file.staged.readAsBytes();
                await review(body);
                await session.commit(() => provider.saveContent(body));
              } finally {
                await response?.file.close();
              }
            },
          );
        } else {
          throw const RequestUnavailable('profile_invalid');
        }
      }
      switch (provider.kind) {
        case ProviderKind.proxy:
          proxies[provider.label] = definition;
        case ProviderKind.rule:
          ruleProviders[provider.label] = definition;
      }
    }
    return (proxies: proxies, rules: ruleProviders);
  }

  Future<String> getProfileWithId(int profileId) async {
    try {
      final selection = await database.profilePolicySelectionsDao
          .query(profileId)
          .getSingleOrNull();
      if (selection != null &&
          SelectedPolicy.decode(selection.rawContent).usesMaterials) {
        final candidate = await capturePolicyMaterial(profileId);
        try {
          final built = await _buildMaterialProfile(
            candidate._inputs,
            candidate._frame,
            (_) {},
          );
          if (!await candidate.current()) {
            throw const PolicyDraftProblem('materialSource');
          }
          return built.yaml;
        } finally {
          await candidate.close();
        }
      }
      ref.invalidate(setupStateProvider(profileId));
      final setupState = await ref.read(setupStateProvider(profileId).future);
      final patchClashConfig = ref.read(patchClashConfigProvider);
      final res = await getProfile(
        setupState: setupState,
        patchConfig: patchClashConfig,
      );
      return res.yaml;
    } catch (e) {
      dialogs.showNotifier(e.toString(), level: MessageLevel.error);
    }
    return '';
  }

  @override
  PatchClashConfig _effectivePatchConfig(PatchClashConfig patchConfig) {
    if (ref.read(safeModeProvider)) {
      return patchConfig.copyWith(
        tun: patchConfig.tun.copyWith(enable: false),
        externalController: ExternalControllerStatus.close,
      );
    }
    final authorized =
        ref.read(authorizedTunEnableProvider) ==
        TunAuthorizationState.authorized;
    return patchConfig.copyWith(
      tun: patchConfig.tun.copyWith(
        enable: patchConfig.tun.enable && authorized,
      ),
    );
  }

  @protected
  Future<AuthorizeCode> authorizeCore() {
    return system.authorizeCore();
  }

  @visibleForTesting
  Future<bool> requestAdmin(bool enableTun) async {
    if (!enableTun || ref.read(safeModeProvider)) {
      return true;
    }
    final authorizationState = ref.read(authorizedTunEnableProvider);
    if (authorizationState != TunAuthorizationState.none) {
      return true;
    }

    final authorizationNotifier = ref.read(
      authorizedTunEnableProvider.notifier,
    );
    authorizationNotifier.value = TunAuthorizationState.unauthorized;

    final code = await authorizeCore();

    switch (code) {
      case AuthorizeCode.success:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return false;
      case AuthorizeCode.none:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return true;
      case AuthorizeCode.error:
        return true;
    }
  }

  @visibleForTesting
  Profile? recoverMissingProfile() {
    return null;
  }

  Future<_SetupTaskResult> _setupConfig({
    void Function(ProxyPreparationStage)? onPreparation,
    _AcceptedLocalInput? acceptedLocalInput,
    bool force = false,
    bool silence = false,
    bool allowSourceReview = false,
    bool preferHot = false,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    FutureOr<void> Function(Future<bool> Function())? onUpdated,
    Future<bool> Function()? isCurrent,
    void Function(ConfigApplyResult)? onApplied,
    required bool Function() isLatestSetup,
    required void Function(Future<void>) onCleanupDeferred,
    bool retryAllowed = true,
    Future<bool> Function()? canSubmit,
  }) async {
    final hot = preferHot && _requests.requiresSourceAcceptance;
    final nativeContext = _isAndroid ? await _service!.getRequestState() : null;
    if (isCurrent != null && !await isCurrent() ||
        expectedRun != null &&
            (nativeContext == null ||
                !_sameSetupRun(expectedRun, nativeContext))) {
      return _SetupTaskResult.superseded;
    }
    final canBootstrap =
        allowBootstrap &&
        allowSourceReview &&
        ref.read(appVisibleProvider) &&
        nativeContext != null &&
        [
          'stopped',
          'failed',
          'preparing',
          'starting',
        ].contains(nativeContext['phase']) &&
        nativeContext['paused'] != true &&
        ![
          'initializedIdle',
          'userStop',
          'excludedSsid',
          'exiting',
        ].contains(nativeContext['reason']);
    final failureCore = _core;
    final observedFact = await failureCore.getConfigState();
    if (acceptedLocalInput != null &&
        !ConfigInput.sameAcceptedInput(
          acceptedLocalInput.expected,
          observedFact,
        )) {
      return _SetupTaskResult.superseded;
    }
    var registeredToken =
        (nativeContext?['configToken'] as num?)?.toInt() ?? observedFact.token;
    var managedRequested = false;
    Future<bool> triggerCurrent() async =>
        expectedRun == null ||
        _sameSetupRun(
          expectedRun,
          await _service!.getRequestState(),
          token: registeredToken,
        );
    if (!await triggerCurrent()) return _SetupTaskResult.superseded;
    Future<void> finishBuildFailure() async {
      if (!await triggerCurrent() ||
          !isLatestSetup() ||
          !managedRequested && !observedFact.isManaged) {
        return;
      }
      await finishConfigFailure((
        core: failureCore,
        fact: observedFact,
        nativeRun: nativeContext,
        registeredToken: registeredToken,
      ));
    }

    Future<void> finishOrDefer(Future<void> Function() cleanup) async {
      if (isLatestSetup()) {
        await cleanup();
      } else {
        onCleanupDeferred(_finishPreparationAfterQueue(cleanup));
      }
    }

    Future<void> finishUnregisteredStart() async {
      if (nativeContext == null ||
          !['preparing', 'starting'].contains(nativeContext['phase'])) {
        return;
      }
      await finishOrDefer(() async {
        if (!await triggerCurrent()) return;
        final cleanup = await _service!.failRunIntent(
          (nativeContext['intentRevision'] as num).toInt(),
          token: (nativeContext['configToken'] as num?)?.toInt() ?? 0,
          unregistered: true,
        );
        if (cleanup['status'] == 'cleanupFailed') {
          throw StateError('Owned service cleanup failed');
        }
      });
    }

    var profile = ref.read(currentProfileProvider) ?? recoverMissingProfile();
    Future<bool> materialCurrent() async {
      if (!await triggerCurrent()) return false;
      if (isCurrent != null && !await isCurrent() ||
          profile?.id != ref.read(currentProfileIdProvider)) {
        return false;
      }
      if (nativeContext == null) return true;
      final native = await _service!.getRequestState();
      return native['processEpoch'] == nativeContext['processEpoch'] &&
          native['intentRevision'] == nativeContext['intentRevision'] &&
          native['intentRunning'] == nativeContext['intentRunning'] &&
          native['paused'] == nativeContext['paused'];
    }

    // A refresh failure is surfaced by safeRun; setup keeps the old profile.
    final nextProfile = await globalState.safeRun(
      () =>
          acceptedLocalInput != null ||
              profile == null ||
              !allowSourceReview && _requests.requiresSourceAcceptance
          ? Future<Profile?>.value(null)
          : ref
                .read(profilesActionProvider.notifier)
                .ensureFile(profile, isCurrent: materialCurrent),
    );
    if (nextProfile != null) {
      profile = nextProfile;
    }
    commonPrint.log('setup ===> ${profile?.realLabel}');
    final patchConfig = ref.read(patchClashConfigProvider);
    final shouldContinueSetup =
        hot || await requestAdmin(patchConfig.tun.enable);
    if (!shouldContinueSetup) {
      return _SetupTaskResult.handoffToCoreRestart;
    }
    final sources = <RequestSource>[];
    final sourceUses = <Map<String, Object?>>[];
    Map<String, Object?>? ruleLedger;
    _SetupInputs? captured;
    _ManagedMaterialFrame? materialFrame;
    final realProfile = await globalState.safeRun(() async {
      if (_requests.partialCommit) return null;
      final selectedProfile = profile;
      if (selectedProfile == null) {
        throw StateError('No configuration selected');
      }
      return _requests
          .mutate(() async {
            if (!await materialCurrent()) {
              throw const RequestUnavailable('request_cancelled');
            }
            ref.invalidate(setupStateProvider(selectedProfile.id));
            final setupState = await ref.read(
              setupStateProvider(selectedProfile.id).future,
            );
            final actualProfile = (await database.profilesDao.query().get())
                .getProfile(selectedProfile.id);
            if (actualProfile == null) {
              throw const RequestUnavailable('request_cancelled');
            }
            final selection = setupState.policySelection;
            managedRequested = selection != null;
            if (managedRequested && !_isAndroid) {
              throw const RequestUnavailable('managed_policy_android_required');
            }
            final policy = selection == null
                ? null
                : SelectedPolicy.decode(selection.rawContent);
            final picks = Map<String, String>.unmodifiable(
              policy == null
                  ? actualProfile.selectedMap
                  : policy.usesMaterials
                  ? <String, String>{}
                  : policy.picks(actualProfile.selectedMap),
            );
            final effective = _effectivePatchConfig(
              ref.read(patchClashConfigProvider),
            );
            final testUrl = ref.read(appSettingProvider).testUrl;
            var shared = ref
                .read(sharedStateProvider)
                .copyWith(
                  currentProfileName: actualProfile.realLabel,
                  setupParams: SetupParams(
                    selectedMap: picks,
                    testUrl: testUrl,
                  ),
                );
            if (policy != null) {
              shared = shared.copyWith(
                vpnOptions: shared.vpnOptions?.copyWith(port: policy.mixedPort),
              );
            }
            captured = _SetupInputs(
              state: setupState,
              profile: actualProfile,
              patch: effective,
              network: ref.read(networkSettingProvider),
              overrideDns: ref.read(overrideDnsProvider),
              overrideNtp: ref.read(overrideNtpProvider),
              safeMode: ref.read(safeModeProvider),
              testUrl: testUrl,
              picks: picks,
              shared: shared,
              vpn: ref.read(vpnStateProvider),
              fact: await _core.getConfigState(),
              policy: policy,
            );
            if (acceptedLocalInput != null && policy != null) {
              throw const RequestUnavailable('request_cancelled');
            }
            if (policy?.usesMaterials == true) {
              materialFrame = await _ManagedMaterialFrame.capture(
                actualProfile,
                setupState,
              );
            }
            final keys = <String>{
              'profile:${selectedProfile.id}',
              if (selection != null || _requests.requiresSourceAcceptance)
                'application-config',
            };
            if (setupState.overwriteType == OverwriteType.standard &&
                policy?.usesMaterials != true) {
              keys.add('global-rules');
            }
            if (setupState.overwriteType == OverwriteType.script &&
                setupState.script != null) {
              keys.add('script:${setupState.script!.id}');
            }
            if (setupState.overwriteType == OverwriteType.custom &&
                policy?.usesMaterials != true) {
              final proxyUses = {
                for (final group in setupState.proxyGroups) ...?group.use,
              };
              final ruleUses = {
                for (final rule in setupState.rules)
                  if (rule.ruleAction == RuleAction.RULE_SET) rule.ruleProvider,
              };
              for (final entry in setupState.profileProviders.entries) {
                if (proxyUses.contains(entry.key)) {
                  keys.add('profile:${entry.value}');
                }
              }
              for (final provider in setupState.clashProviders) {
                if ((provider.kind == ProviderKind.proxy ? proxyUses : ruleUses)
                    .contains(provider.label)) {
                  keys.add('clash-provider:${provider.id}');
                }
              }
            }
            if (acceptedLocalInput != null) {
              final manifest = acceptedLocalInput.document['manifest'] as Map;
              keys
                ..clear()
                ..addAll(List<String>.from(manifest['dependencies'] as List));
            }
            for (final key in keys) {
              sources.add(await _requests.captureSource(key));
            }
            return setupState;
          })
          .then((setupState) async {
            if (acceptedLocalInput != null) {
              if (!ConfigInput.sameAcceptedInput(
                acceptedLocalInput.expected,
                captured!.fact,
              )) {
                throw const RequestUnavailable('request_cancelled');
              }
              final yaml = acceptedLocalInput.document['yaml'] as String;
              return (
                yaml: yaml,
                md5: md5.convert(utf8.encode(yaml)).toString(),
              );
            }
            final frame = materialFrame;
            if (frame != null) {
              return _buildMaterialProfile(
                captured!,
                frame,
                (policy) => captured = captured!.resolved(policy),
                onSourceUse: sourceUses.add,
                onRuleLedger: (ledger) => ruleLedger = ledger,
                allowSourceReview: allowSourceReview,
                isCurrent: materialCurrent,
              );
            }
            return getProfile(
              setupState: setupState,
              patchConfig: captured!.patch,
              network: captured!.network,
              dnsOverride: captured!.overrideDns,
              ntpOverride: captured!.overrideNtp,
              safeMode: captured!.safeMode,
              onSourceUse: sourceUses.add,
              onRuleLedger: (ledger) => ruleLedger = ledger,
              allowSourceReview: allowSourceReview,
              isCurrent: materialCurrent,
            );
          })
          .whenComplete(() async => materialFrame?.file.close());
    }, title: 'build profile');
    Future<bool> current() async {
      if (!await triggerCurrent()) return false;
      if (profile?.id != ref.read(currentProfileIdProvider) ||
          (isCurrent != null && !await isCurrent())) {
        return false;
      }
      for (final source in sources) {
        if (!await _requests.configSourceCurrent(source)) return false;
      }
      final frame = materialFrame;
      if (frame != null) {
        try {
          if (!await frame.scriptCurrent() ||
              await _boundedFileDigest(
                    await appPath.getProfilePath(
                      captured!.profile.id.toString(),
                    ),
                  ) !=
                  frame.rawSha256) {
            return false;
          }
        } on FileSystemException {
          return false;
        } on PolicyDraftProblem {
          return false;
        }
      }
      return true;
    }

    if (realProfile == null || realProfile.yaml.trim().isEmpty) {
      await finishBuildFailure();
      if (!await current()) {
        await finishUnregisteredStart();
        return _SetupTaskResult.superseded;
      }
      await finishUnregisteredStart();
      await ref.read(configStateProvider.notifier).refresh();
      ref.read(configStateProvider.notifier).markBuildFailure();
      return _SetupTaskResult.failed;
    }
    if (!await current()) {
      if (captured?.policy != null &&
          isLatestSetup() &&
          profile?.id == ref.read(currentProfileIdProvider)) {
        if (!retryAllowed) await finishBuildFailure();
        return _SetupTaskResult.staleInput;
      }
      await finishUnregisteredStart();
      return _SetupTaskResult.superseded;
    }
    var yamlString = realProfile.yaml;
    final yamlMd5 = realProfile.md5;
    var setupFailed = false;
    var foregroundRequired = false;
    var superseded = false;
    var staleInput = false;
    ConfigApplyResult? accepted;
    await globalState.loadingRun(
      () async {
        ConfigInput? input;
        SourceProviderBundle? sourceBundle;
        ConfigApplyResult? recoveryPending;
        int? recoveryRequestId;
        var submittedToCore = false;
        try {
          final snapshot = captured!;
          if (hot && snapshot.policy != null) {
            setupFailed = true;
            return;
          }
          final runtimeEpoch = snapshot.fact.runtimeEpoch;
          onPreparation?.call(ProxyPreparationStage.sources);
          final acceptedUses = <Map<String, Object?>>[];
          final providerMaterials = <Map<String, Object?>>[];
          if (_requests.requiresSourceAcceptance &&
              acceptedLocalInput == null) {
            Object useIdentity(Map<String, Object?> use) => [
              use['key'],
              use['kind'],
              use['incarnation'],
              use['epoch'],
              use['purposeEpoch'],
            ];
            final qualifiedUses = List<Map<String, Object?>>.of(sourceUses)
              ..sort(
                (a, b) => jsonEncode(
                  useIdentity(a),
                ).compareTo(jsonEncode(useIdentity(b))),
              );
            final acceptedComposition =
                await _sourceAcceptance(
                  _core,
                  _requests,
                  confirm: ref.read(sourceConfirmationProvider),
                ).review(
                  source: sources.firstWhere(
                    (s) => s.key == 'application-config',
                  ),
                  entityKey: 'config:${snapshot.profile.id}',
                  identity: SourceAcceptance.fingerprint({
                    'profile': snapshot.profile.id,
                  }),
                  settings: {
                    'patch': snapshot.patch.toJson(),
                    'network': snapshot.network.toJson(),
                    'dns': snapshot.overrideDns,
                    'ntp': snapshot.overrideNtp,
                    'safeMode': snapshot.safeMode,
                    'policy': snapshot.policy?.descriptor,
                  },
                  body: yamlString,
                  label: snapshot.profile.realLabel,
                  location: snapshot.profile.url,
                  kind: 'config',
                  uses: qualifiedUses,
                  automatic:
                      !allowSourceReview || !ref.read(appVisibleProvider),
                  isCurrent: current,
                );
            Future<bool> providerCurrent() async {
              if (!await current()) return false;
              if (!canBootstrap) return true;
              final now = await _service!.getRequestState();
              return now['phase'] != 'started' &&
                  now['paused'] != true &&
                  [
                    'processEpoch',
                    'intentRevision',
                    'configToken',
                  ].every((key) => now[key] == nativeContext[key]);
            }

            final bundle =
                await _sourceAcceptance(
                  _core,
                  _requests,
                  confirm: ref.read(sourceConfirmationProvider),
                ).completeProviders(
                  root: acceptedComposition,
                  reuseReviewed: true,
                  acceptedOnly: !allowSourceReview,
                  reviewed:
                      SourceReviewBatchStore.forRequests(
                        _requests,
                      ).configuration(
                        'profile:${snapshot.profile.id}',
                        sources.first.client,
                      ) !=
                      null,
                  dependencies: qualifiedUses,
                  source: sources.firstWhere(
                    (s) => s.key == 'application-config',
                  ),
                  automatic:
                      !allowSourceReview || !ref.read(appVisibleProvider),
                  reuseAccepted: true,
                  onDownloading: (downloading) => onPreparation?.call(
                    downloading
                        ? ProxyPreparationStage.downloading
                        : ProxyPreparationStage.sources,
                  ),
                  allowBootstrap: canBootstrap,
                  isCurrent: providerCurrent,
                );
            sourceBundle = bundle;
            sources.addAll(bundle.sources);
            providerMaterials.addAll(bundle.materials);
            acceptedUses.addAll([...bundle.uses, bundle.rootUse]);
          }
          final localManifest =
              acceptedLocalInput?.document['manifest'] as Map?;
          if (localManifest != null) {
            acceptedUses.addAll(
              (localManifest['sourceUses'] as List).map(
                (value) => Map<String, Object?>.from(value as Map),
              ),
            );
            providerMaterials.addAll(
              (localManifest['providerMaterials'] as List? ?? const []).map(
                (value) => Map<String, Object?>.from(value as Map),
              ),
            );
            ruleLedger = localManifest['ruleLedger'] == null
                ? null
                : Map<String, Object?>.from(localManifest['ruleLedger'] as Map);
          }
          var localGroupDefinitions = snapshot.profile.localGroups
              .map((group) => group.toJson())
              .toList();
          if (_requests.requiresSourceAcceptance &&
              acceptedLocalInput == null &&
              snapshot.profile.localGroups.any(
                (group) => group.enabled && group.regex.isNotEmpty,
              )) {
            final source = sources.firstWhere(
              (source) => source.key == 'application-config',
            );
            final resolved = await _core.sourceAcceptance({
              'action': 'resolveLocalGroups',
              'key': 'config:${snapshot.profile.id}',
              'kind': 'config',
              'source': {
                'client': source.client,
                'dataset': source.snapshot['dataset'],
                'sources': {
                  for (final entry in sources)
                    entry.key: entry.snapshot['sourceRevision'],
                },
              },
              'body': jsonEncode({
                'version': 2,
                'profileId': snapshot.profile.id,
                'yamlSha256': sha256
                    .convert(utf8.encode(yamlString))
                    .toString(),
                'dependencies': sources.map((source) => source.key).toList(),
                'sourceUses': acceptedUses,
                'providerMaterials': providerMaterials,
                'localGroups': localGroupDefinitions,
              }),
            });
            if (resolved['status'] == 'resolved') {
              final document = resolved['document'] as Map;
              final manifest = document['manifest'] as Map;
              yamlString = document['yaml'] as String;
              acceptedUses
                ..clear()
                ..addAll(
                  (manifest['sourceUses'] as List).map(
                    (value) => Map<String, Object?>.from(value as Map),
                  ),
                );
              providerMaterials
                ..clear()
                ..addAll(
                  (manifest['providerMaterials'] as List? ?? const []).map(
                    (value) => Map<String, Object?>.from(value as Map),
                  ),
                );
              localGroupDefinitions = (manifest['localGroups'] as List)
                  .map((value) => Map<String, dynamic>.from(value as Map))
                  .toList();
            }
          }
          onPreparation?.call(ProxyPreparationStage.applying);
          await _requests.mutate(() async {
            if (!await current() || canSubmit != null && !await canSubmit()) {
              throw const RequestUnavailable('request_cancelled');
            }
            if (_isAndroid && !hot) {
              globalState.lastVpnState = snapshot.vpn;
              final desired = snapshot.shared;
              if (!await preferences.saveShareState(desired)) {
                throw const RequestUnavailable('preferences_save_failed');
              }
              if ((await _service!.syncState(desired)).isNotEmpty) {
                throw StateError('Service state synchronization failed');
              }
            }
            input = await ConfigInput.write(
              home: await appPath.homeDirPath,
              yaml: yamlString,
              runtimeEpoch: runtimeEpoch,
              profileId: snapshot.profile.id,
              profileName: snapshot.profile.realLabel,
              selectedMap: snapshot.picks,
              testUrl: localManifest?['testUrl'] as String? ?? snapshot.testUrl,
              sources: sources,
              sourceUses: acceptedUses,
              providerMaterials: providerMaterials,
              localGroups: localManifest == null
                  ? localGroupDefinitions
                  : (localManifest['localGroups'] as List? ?? const [])
                        .map((value) => Map<String, Object?>.from(value as Map))
                        .toList(),
              acceptedOverrides: Map<String, Object?>.from(
                localManifest?['acceptedOverrides'] as Map? ?? const {},
              ),
              ruleLedger: _requests.requiresSourceAcceptance
                  ? ruleLedger
                  : null,
              version: _requests.requiresSourceAcceptance ? 2 : 1,
              managedPolicy: snapshot.policy?.descriptor,
              managedMaterials: snapshot.policy?.materials,
            );
          });
          await sourceBundle?.release();
          final profileId = profile?.id;
          if (profileId != null) {
            await appPath.ensureProviderDirs(profileId);
          }
          if (hot) {
            submittedToCore = true;
            final result = ConfigApplyResult.fromJson(
              await _core.sourceAcceptance({
                'action': 'adoptInline',
                'input': {
                  ...input!.toRequest(
                    active: true,
                    expectedConfig: snapshot.fact.fence,
                  ),
                  'expectedRun': nativeContext,
                },
              }),
            );
            ref
                .read(configStateProvider.notifier)
                .accept(result.fact, authoritative: true);
            if (!result.succeeded) {
              acceptedLocalInput?.reportFailure(result.message);
              foregroundRequired =
                  result.status == 'deferred' &&
                  result.requiresFullApply &&
                  acceptedLocalInput != null &&
                  !result.fact.materialPending &&
                  ConfigInput.sameAcceptedInput(snapshot.fact, result.fact);
              superseded = result.status == 'superseded';
              setupFailed = !superseded;
              return;
            }
            if (!await current() ||
                result.fact.owner != snapshot.fact.owner ||
                result.fact.token != snapshot.fact.token ||
                result.fact.yamlSha256 !=
                    sha256.convert(utf8.encode(yamlString)).toString() ||
                !ConfigInput.sameAcceptedInput(
                  result.fact,
                  await _core.getConfigState(),
                )) {
              superseded = true;
              return;
            }
            accepted = result;
          }
          if (!hot) {
            for (var attempt = 0; ; attempt++) {
              if (!await current() || canSubmit != null && !await canSubmit()) {
                throw const RequestUnavailable('request_cancelled');
              }
              if (_isAndroid) {
                recoveryRequestId =
                    (expectedRun?['intentRevision'] as num?)?.toInt() ??
                    ((await _service!.getRequestState())['intentRevision']
                            as num?)
                        ?.toInt();
              }
              submittedToCore = true;
              final result = await _core.applyConfigInput(
                input!.toRequest(
                  requestId:
                      (expectedRun?['intentRevision'] as num?)?.toInt() ??
                      RunRequestScope.current,
                  expectedConfig:
                      snapshot.policy == null && acceptedLocalInput == null
                      ? null
                      : snapshot.fact.fence,
                  active:
                      !snapshot.safeMode &&
                      (_latestRunRequest?.running ?? _isRunning) &&
                      !ref.read(suspendProvider),
                ),
              );
              registeredToken =
                  (result.receipt['token'] as num?)?.toInt() ?? registeredToken;
              ref
                  .read(configStateProvider.notifier)
                  .accept(result.fact, authoritative: true);
              if (result.status != 'superseded' &&
                  !result.fact.businessActive) {
                _setLocalRunning(false);
              }
              if (result.succeeded) {
                recoveryPending = null;
                if (!await current() ||
                    onApplied != null &&
                        (result.fact.inputId != input!.id ||
                            result.receipt['inputId'] != result.fact.inputId ||
                            result.receipt['owner'] != result.fact.owner ||
                            result.receipt['token'] != result.fact.token ||
                            result.fact.runtimeEpoch != runtimeEpoch ||
                            !ConfigInput.sameAcceptedInput(
                              result.fact,
                              await _core.getConfigState(),
                            ))) {
                  throw const RequestUnavailable('request_cancelled');
                }
                accepted = result;
                if (_isAndroid && result.fact.businessActive) {
                  final native = await _service!.getRequestState();
                  ref
                      .read(nativeRequestStateProvider.notifier)
                      .onRequestState(native);
                  await _syncNativeRuntime(native);
                }
                break;
              }
              acceptedLocalInput?.reportFailure(result.message);
              if (result.status == 'staleInput') {
                staleInput = true;
                throw const RequestUnavailable('request_cancelled');
              }
              if (result.status == 'superseded') {
                superseded = true;
                throw const RequestUnavailable('request_cancelled');
              }
              recoveryPending = result.status == 'bootstrapRequired'
                  ? result
                  : null;
              if (attempt >= 4 || !await _requests.recoverMissingGeo(_core)) {
                throw MessageException(result.message);
              }
            }
          }
        } catch (error) {
          if (!await current() &&
              captured?.policy != null &&
              isLatestSetup() &&
              profile?.id == ref.read(currentProfileIdProvider)) {
            staleInput = true;
          }
          if (staleInput) return;
          superseded = superseded || !await current();
          setupFailed = !superseded;
          acceptedLocalInput?.reportFailure(
            userFacingErrorMessage(error, currentAppLocalizations),
          );
          if (hot) {
            await ref.read(configStateProvider.notifier).refresh();
            return;
          }
          final pending = recoveryPending;
          final requestId = recoveryRequestId;
          if (pending != null && requestId != null) {
            Future<void> cleanup() async {
              if (!await triggerCurrent()) return;
              final result = await _service!.failRunIntent(
                requestId,
                token: pending.fact.token,
              );
              if (result['status'] == 'cleanupFailed') {
                throw StateError('Owned service cleanup failed');
              }
            }

            await finishOrDefer(cleanup);
          } else if (!submittedToCore) {
            await finishUnregisteredStart();
          }
          if (superseded) return;
          rethrow;
        } finally {
          await sourceBundle?.release();
          final submitted = input;
          if (submitted != null) {
            try {
              await _core.releaseConfigInput(submitted.markerName);
            } catch (error) {
              commonPrint.log(
                'Configuration input cleanup: ${compactError(error)}',
              );
            } finally {
              try {
                await submitted.releaseMarker();
              } catch (error) {
                commonPrint.log(
                  'Configuration candidate cleanup: ${compactError(error)}',
                );
              }
            }
          }
        }
        final completed = accepted;
        if (completed == null) {
          superseded = true;
          return;
        }
        Future<bool> completionCurrent() async =>
            await current() &&
            (onApplied == null ||
                ConfigInput.sameAcceptedInput(
                  completed.fact,
                  await _core.getConfigState(),
                ));
        if (!await completionCurrent()) {
          superseded = true;
          return;
        }
        globalState.lastConfigMd5 = yamlMd5;
        await onUpdated?.call(completionCurrent);
        if (!await completionCurrent()) {
          superseded = true;
          return;
        }
        onApplied?.call(completed);
      },
      silence: true,
      tag: !silence ? LoadingTag.proxies : null,
    );
    if (staleInput) {
      if (!retryAllowed) await finishBuildFailure();
      return _SetupTaskResult.staleInput;
    }
    if (foregroundRequired) return _SetupTaskResult.foregroundRequired;
    if (superseded) return _SetupTaskResult.superseded;
    if (setupFailed) {
      return _SetupTaskResult.failed;
    }
    return _SetupTaskResult.completed;
  }
}
