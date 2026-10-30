part of '../action.dart';

typedef ConfigFailureObservation = ({
  CoreController core,
  ConfigFact fact,
  Map<String, Object?>? nativeRun,
  int registeredToken,
});

enum _SetupTaskResult {
  completed,
  handoffToCoreRestart,
  failed,
  superseded,
  staleInput,
}

class _RunRequest {
  final bool running;
  final bool initialize;
  final bool paused;
  final DateTime? previousStartTime;
  final Future<int?> nativeRequest;

  const _RunRequest({
    required this.running,
    required this.initialize,
    required this.paused,
    required this.previousStartTime,
    required this.nativeRequest,
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
}

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
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
  Request get _requests => _requestClient ?? request;

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
  DateTime? _startTime;
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
      await globalState.safeRun(() => applyProfile(force: true));
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

    final request = _RunRequest(
      running: running,
      initialize: running && initialize,
      paused: _isAndroid && (paused ?? ref.read(suspendProvider)),
      previousStartTime: _startTime,
      nativeRequest: preparedRequestId != null
          ? Future.value(preparedRequestId)
          : _service?.prepareRunIntent(
                  running: running,
                  source: source,
                  paused: paused ?? ref.read(suspendProvider),
                ) ??
                Future.value(null),
    );
    _latestRunRequest = request;
    if (!running) {
      _setupGeneration++;
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
        request.running ? _start(request) : _stop(request);
    return requestId == null
        ? dispatch()
        : RunRequestScope.run(requestId, dispatch);
  }

  Future<void> setPaused(bool paused) async {
    final native = _service;
    if (native == null) return;
    final snapshot = await native.getRequestState();
    await setRunning(
      snapshot['intentRunning'] == true,
      source: 'ssid',
      paused: paused,
    );
  }

  Future<bool> _start(_RunRequest request) async {
    var applied = false;
    try {
      applied = await applyProfile(force: true);
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
    return applied;
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
    Future<bool> Function()? isCurrent,
  }) {
    debouncer.call(FunctionTag.applyProfile, () async {
      if (isCurrent == null) {
        await applyProfile(silence: silence, force: force);
      } else {
        await _runSetup(silence: silence, force: force, isCurrent: isCurrent);
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
    runAfterFrame(applyProfile);
  }

  Future<bool> applyProfile({bool silence = false, bool force = false}) async {
    final result = await _runSetup(force: force, silence: silence);
    return result == _SetupTaskResult.completed;
  }

  Future<ProfileApplicationOutcome> applyRefreshedProfile({
    required Future<bool> Function() isCurrent,
    required ConfigFact previous,
    Future<bool> Function()? canSubmit,
  }) async {
    if (!await isCurrent()) return ProfileApplicationOutcome.superseded;
    ConfigApplyResult? accepted;
    final result = await _runSetup(
      silence: true,
      force: true,
      isCurrent: isCurrent,
      canSubmit: canSubmit,
      onApplied: (value) => accepted = value,
    );
    if (result == _SetupTaskResult.superseded ||
        result == _SetupTaskResult.staleInput) {
      return ProfileApplicationOutcome.superseded;
    }
    if (result == _SetupTaskResult.completed && accepted != null) {
      return accepted!.status == 'activated'
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
    bool silence = false,
    bool force = false,
    Future<bool> Function()? isCurrent,
    void Function(ConfigApplyResult)? onApplied,
    Future<bool> Function()? canSubmit,
  }) async {
    final generation = ++_setupGeneration;
    unawaited(
      ref.read(profilesActionProvider.notifier)._cancelExpiredDemands(),
    );
    Future<void>? deferredCleanup;
    Future<bool> current() async =>
        generation == _setupGeneration &&
        (isCurrent == null || await isCurrent());
    final result = await _setupScheduler.run(() async {
      ref.read(profilesActionProvider.notifier).setupExecutionChanged(true);
      try {
        await dataMutations.run(() async {});
        if (!await current()) {
          return _SetupTaskResult.superseded;
        }
        Future<_SetupTaskResult> run({bool retryAllowed = true}) =>
            _setupConfig(
              force: force,
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
        if (first != _SetupTaskResult.staleInput || !await current()) {
          return first;
        }
        final second = await run(retryAllowed: false);
        return second == _SetupTaskResult.staleInput
            ? _SetupTaskResult.superseded
            : second;
      } finally {
        if (ref.mounted) {
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
    final configMap = await _core.getConfig(profileId);
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
    if (scriptContent?.isNotEmpty == true) {
      rawConfig = await handleEvaluate(scriptContent!, rawConfig);
    }
    final directory = await appPath.profilesPath;
    final injected = await _resolveInjectedProviders(
      setupState,
      proxyGroups: proxyGroups,
      rules: rules,
    );
    final res = makeRealProfileTask(
      MakeRealProfileState(
        rules: rules,
        proxies: proxies,
        proxyGroups: proxyGroups,
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
        safeMode: safeMode ?? ref.read(safeModeProvider),
        policySelection: setupState.policySelection,
      ),
    );
    return res;
  }

  /// Only what the overwrite actually references is injected, so an app-level
  /// provider costs nothing in the profiles that never name it.
  Future<({Map<String, dynamic> proxies, Map<String, dynamic> rules})>
  _resolveInjectedProviders(
    SetupState setupState, {
    required List<ProxyGroup> proxyGroups,
    required List<Rule> rules,
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
      proxies[entry.key] = {
        'type': 'file',
        'path': await appPath.getProfilePath(entry.value.toString()),
      };
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
    bool force = false,
    bool silence = false,
    FutureOr<void> Function(Future<bool> Function())? onUpdated,
    Future<bool> Function()? isCurrent,
    void Function(ConfigApplyResult)? onApplied,
    required bool Function() isLatestSetup,
    required void Function(Future<void>) onCleanupDeferred,
    bool retryAllowed = true,
    Future<bool> Function()? canSubmit,
  }) async {
    final nativeContext = _isAndroid ? await _service!.getRequestState() : null;
    final failureCore = _core;
    final observedFact = await failureCore.getConfigState();
    var registeredToken =
        (nativeContext?['configToken'] as num?)?.toInt() ?? observedFact.token;
    var managedRequested = false;
    Future<void> finishBuildFailure() async {
      if (!isLatestSetup() || !managedRequested && !observedFact.isManaged) {
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
        final cleanup = await _service!.failRunIntent(
          (nativeContext['intentRevision'] as num).toInt(),
          token: (nativeContext['configToken'] as num?)?.toInt() ?? 0,
        );
        if (cleanup['status'] == 'cleanupFailed') {
          throw StateError('Owned service cleanup failed');
        }
      });
    }

    var profile = ref.read(currentProfileProvider) ?? recoverMissingProfile();
    Future<bool> materialCurrent() async {
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
      () => profile == null
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
    final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
    if (!shouldContinueSetup) {
      return _SetupTaskResult.handoffToCoreRestart;
    }
    final sources = <RequestSource>[];
    _SetupInputs? captured;
    final realProfile = await globalState.safeRun(() async {
      if (_requests.partialCommit) return null;
      final selectedProfile = profile;
      if (selectedProfile == null) {
        throw StateError('No configuration selected');
      }
      return _requests
          .mutate(() async {
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
              policy?.picks(actualProfile.selectedMap) ??
                  actualProfile.selectedMap,
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
                vpnOptions: shared.vpnOptions?.copyWith(
                  port: policy.policy.mixedPort,
                ),
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
            final keys = <String>{'profile:${selectedProfile.id}'};
            if (selection != null) keys.add('application-config');
            if (setupState.overwriteType == OverwriteType.standard) {
              keys.add('global-rules');
            }
            if (setupState.overwriteType == OverwriteType.script &&
                setupState.script != null) {
              keys.add('script:${setupState.script!.id}');
            }
            if (setupState.overwriteType == OverwriteType.custom) {
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
            for (final key in keys) {
              sources.add(await _requests.captureSource(key));
            }
            return setupState;
          })
          .then(
            (setupState) => getProfile(
              setupState: setupState,
              patchConfig: captured!.patch,
              network: captured!.network,
              dnsOverride: captured!.overrideDns,
              ntpOverride: captured!.overrideNtp,
              safeMode: captured!.safeMode,
            ),
          );
    }, title: 'build profile');
    Future<bool> current() async {
      if (profile?.id != ref.read(currentProfileIdProvider) ||
          (isCurrent != null && !await isCurrent())) {
        return false;
      }
      for (final source in sources) {
        if (!await _requests.configSourceCurrent(source)) return false;
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
    final yamlString = realProfile.yaml;
    final yamlMd5 = realProfile.md5;
    var setupFailed = false;
    var superseded = false;
    var staleInput = false;
    ConfigApplyResult? accepted;
    await globalState.loadingRun(
      () async {
        ConfigInput? input;
        ConfigApplyResult? recoveryPending;
        int? recoveryRequestId;
        var submittedToCore = false;
        try {
          final snapshot = captured!;
          final runtimeEpoch = snapshot.fact.runtimeEpoch;
          await _requests.mutate(() async {
            if (!await current() || canSubmit != null && !await canSubmit()) {
              throw const RequestUnavailable('request_cancelled');
            }
            if (_isAndroid) {
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
              testUrl: snapshot.testUrl,
              sources: sources,
              managedPolicy: snapshot.policy?.descriptor,
            );
          });
          final profileId = profile?.id;
          if (profileId != null) {
            await appPath.ensureProviderDirs(profileId);
          }
          for (var attempt = 0; ; attempt++) {
            if (!await current() || canSubmit != null && !await canSubmit()) {
              throw const RequestUnavailable('request_cancelled');
            }
            if (_isAndroid) {
              recoveryRequestId =
                  ((await _service!.getRequestState())['intentRevision']
                          as num?)
                      ?.toInt();
            }
            submittedToCore = true;
            final result = await _core.applyConfigInput(
              input!.toRequest(
                requestId: RunRequestScope.current,
                expectedConfig: snapshot.policy == null
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
            if (result.status != 'superseded' && !result.fact.businessActive) {
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
        } catch (_) {
          if (!await current() &&
              captured?.policy != null &&
              isLatestSetup() &&
              profile?.id == ref.read(currentProfileIdProvider)) {
            staleInput = true;
          }
          if (staleInput) return;
          superseded = superseded || !await current();
          setupFailed = !superseded;
          final pending = recoveryPending;
          final requestId = recoveryRequestId;
          if (pending != null && requestId != null) {
            Future<void> cleanup() async {
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
    if (superseded) return _SetupTaskResult.superseded;
    if (setupFailed) {
      return _SetupTaskResult.failed;
    }
    return _SetupTaskResult.completed;
  }
}
