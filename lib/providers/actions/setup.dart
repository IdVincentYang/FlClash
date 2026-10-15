part of '../action.dart';

enum _SetupTaskResult { completed, handoffToCoreRestart, failed }

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

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  Timer? _runtimeTimer;
  final _setupScheduler = SerialTaskScheduler();
  final _listenerScheduler = SerialTaskScheduler();
  _RunRequest? _latestRunRequest;
  DateTime? _startTime;

  bool get _isRunning => _startTime != null && _startTime!.isBeforeNow;

  @override
  void build() {
    ref.onDispose(_stopRuntimeTicker);
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

  SetupParams get _setupParams {
    final selectedMap = ref.read(selectedMapProvider);
    final testUrl = ref.read(
      appSettingProvider.select((state) => state.testUrl),
    );
    return SetupParams(selectedMap: selectedMap, testUrl: testUrl);
  }

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

  Future<void> _updateStartTime() async {
    _startTime = await service?.getRunTime();
  }

  Future<void> initStatus() async {
    if (!globalState.needInitStatus) {
      commonPrint.log('init status cancel');
      return;
    }
    commonPrint.log('init status');
    Map<String, Object?>? native;
    if (system.isAndroid) {
      final snapshot = await service!.getRequestState();
      await service!.initializeRequestState(snapshot['revision'] as int);
      native = await service!.getRequestState();
      await _updateStartTime();
    }
    final shouldRun =
        native?['intentRunning'] == true ||
        _isRunning ||
        ref.read(appSettingProvider).autoRun;
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
      paused: system.isAndroid && (paused ?? ref.read(suspendProvider)),
      previousStartTime: _startTime,
      nativeRequest: preparedRequestId != null
          ? Future.value(preparedRequestId)
          : service?.prepareRunIntent(
                  running: running,
                  source: source,
                  paused: paused ?? ref.read(suspendProvider),
                ) ??
                Future.value(null),
    );
    _latestRunRequest = request;
    _setLocalRunning(running);
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
    final native = service;
    if (native == null) return;
    final snapshot = await native.getRequestState();
    await setRunning(
      snapshot['intentRunning'] == true,
      source: 'ssid',
      paused: paused,
    );
  }

  Future<bool> _start(_RunRequest request) async {
    if (request.initialize) {
      var applied = false;
      try {
        applied = await applyProfile(
          force: true,
          preloadInvoke: () => _setCoreRunning(request),
        );
      } catch (_) {
        applied = false;
      }
      if (!applied && _isCurrent(request)) {
        if (system.isAndroid) {
          await _failRunRequest(request);
        } else {
          await globalState.safeRun(() => setRunning(false));
        }
      }
      return applied;
    }

    try {
      await _setCoreRunning(request);
    } catch (_) {
      await _failRunRequest(request);
      _rollbackRunning(request);
      rethrow;
    }
    if (_isCurrent(request)) {
      applyProfileDebounce(force: true, silence: true);
    }
    return true;
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
      if (!system.isAndroid && request.running && ref.read(suspendProvider)) {
        return;
      }
      if (ref.read(safeModeProvider)) {
        return;
      }
      final requestId = await request.nativeRequest;
      final running = request.running && !request.paused;
      if (requestId == null) {
        await setCoreRunning(running);
      } else {
        await RunRequestScope.run(requestId, () => setCoreRunning(running));
      }
    });
  }

  Future<void> _failRunRequest(_RunRequest request) async {
    final requestId = await request.nativeRequest;
    if (requestId == null) return;
    await service!.failRunIntent(requestId);
    if (_isCurrent(request)) _setLocalRunning(false);
  }

  void _rollbackRunning(_RunRequest request) {
    if (!_isCurrent(request)) {
      return;
    }
    _startTime = request.previousStartTime;
    _setLocalRunning(!request.running);
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
      if (message.isNotEmpty) throw MessageException(message);
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

  void changeMode(Mode mode) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
    if (mode == Mode.global) {
      ref
          .read(proxiesActionProvider.notifier)
          .updateCurrentGroupName(GroupName.GLOBAL.name);
    }
  }

  void autoApplyProfile() {
    runAfterFrame(applyProfile);
  }

  // False means building the profile, the config write, or the Core setup
  // step failed; a profile that fails to build is still pushed to the Core
  // as the empty config so it never keeps serving the previous one.
  // authorizeCore failures still throw.
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    final result = await _runSetup(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
    );
    return result != _SetupTaskResult.failed;
  }

  Future<_SetupTaskResult> _runSetup({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    Future<bool> Function()? isCurrent,
  }) async {
    final result = await _setupScheduler.run(() async {
      await dataMutations.run(() async {});
      if (request.partialCommit) return _SetupTaskResult.failed;
      if (isCurrent != null && !await isCurrent()) {
        return _SetupTaskResult.failed;
      }
      return _setupConfig(
        force: force,
        silence: silence,
        preloadInvoke: preloadInvoke,
        isCurrent: isCurrent,
        onUpdated: () async {
          await ref.read(proxiesActionProvider.notifier).updateGroups();
          await ref.read(providersProvider.notifier).syncProviders();
        },
      );
    });
    if (result != _SetupTaskResult.handoffToCoreRestart) {
      return result;
    }
    // Release the current serial task before restartCore reapplies the profile.
    final restarted = await _restartCoreAfterAuthorization();
    return restarted ? _SetupTaskResult.completed : _SetupTaskResult.failed;
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
  }) async {
    final profileId = setupState.profileId;
    if (profileId == null) return (yaml: '', md5: '');
    final defaultUA = globalState.packageInfo.ua;
    final networkSetting = ref.read(
      networkSettingProvider.select(
        (state) => (
          appendSystemDns: state.appendSystemDns,
          routeMode: state.routeMode,
          authentication: state.authentication,
        ),
      ),
    );
    final overrideDns = ref.read(overrideDnsProvider);
    final overrideNtp = ref.read(overrideNtpProvider);
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
        safeMode: ref.read(safeModeProvider),
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

  /// An empty profile list is left alone: it is the first-run state, and it is
  /// what the profile stream holds before its first emission.
  @visibleForTesting
  Profile? recoverMissingProfile() {
    final profileId = ref.read(currentProfileIdProvider);
    if (profileId == null) return null;
    final profiles = ref.read(profilesProvider);
    if (profiles.isEmpty) return null;
    final fallback = profiles.first;
    commonPrint.log(
      'profile $profileId is missing, falling back to ${fallback.id}',
      logLevel: LogLevel.warning,
    );
    ref.read(currentProfileIdProvider.notifier).value = fallback.id;
    return fallback;
  }

  Future<_SetupTaskResult> _setupConfig({
    bool force = false,
    bool silence = false,
    Future<void> Function()? preloadInvoke,
    FutureOr Function()? onUpdated,
    Future<bool> Function()? isCurrent,
  }) async {
    var profile = ref.read(currentProfileProvider) ?? recoverMissingProfile();
    // A refresh failure is surfaced by safeRun; setup keeps the old profile.
    final nextProfile = await globalState.safeRun(
      () => profile == null
          ? Future<Profile?>.value(null)
          : ref.read(profilesActionProvider.notifier).ensureFile(profile),
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
    final realPatchConfig = _effectivePatchConfig(patchConfig);
    final realProfile = await globalState.safeRun(() async {
      final setupState = await ref.read(setupStateProvider(profile?.id).future);
      return getProfile(setupState: setupState, patchConfig: realPatchConfig);
    }, title: 'build profile');
    final profileFailed = realProfile == null;
    final yamlString = realProfile?.yaml ?? '';
    final yamlMd5 = realProfile?.md5 ?? '';
    Future<bool> current() async =>
        profile?.id == ref.read(currentProfileIdProvider) &&
        (isCurrent == null || await isCurrent());
    if (!await current()) return _SetupTaskResult.failed;
    if (!profileFailed && yamlMd5 == globalState.lastConfigMd5 && !force) {
      return _SetupTaskResult.completed;
    }
    // Recaptured so _start's catch can roll back after safeRun swallows it.
    (Object, StackTrace)? handoffFailure;
    var setupFailed = false;
    await globalState.loadingRun(
      () async {
        try {
          final configFilePath = await appPath.configFilePath;
          await request.mutate(() async {
            if (!await current()) {
              throw const RequestUnavailable('request_cancelled');
            }
            if (system.isAndroid) {
              globalState.lastVpnState = ref.read(vpnStateProvider);
              if (!await preferences.saveShareState(
                ref.read(sharedStateProvider),
              )) {
                throw const RequestUnavailable('preferences_save_failed');
              }
            }
            final staged = File('$configFilePath.pending');
            try {
              await staged.writeAsString(yamlString, flush: true);
              await staged.rename(configFilePath);
            } finally {
              await staged.safeDelete();
            }
          });
          final profileId = profile?.id;
          if (profileId != null) {
            await appPath.ensureProviderDirs(profileId);
          }
          for (var attempt = 0; ; attempt++) {
            if (!await current()) {
              throw const RequestUnavailable('request_cancelled');
            }
            final message = await _core.setupConfig(
              params: _setupParams,
              preloadInvoke: preloadInvoke,
            );
            if (message.isEmpty) break;
            if (attempt >= 4 || !await request.recoverMissingGeo(_core)) {
              throw MessageException(message);
            }
          }
        } catch (e, s) {
          setupFailed = true;
          if (preloadInvoke != null) {
            handoffFailure = (e, s);
          }
          rethrow;
        }
        globalState.lastConfigMd5 = yamlMd5;
        await onUpdated?.call();
      },
      silence: true,
      tag: !silence ? LoadingTag.proxies : null,
    );
    if (handoffFailure != null) {
      Error.throwWithStackTrace(handoffFailure!.$1, handoffFailure!.$2);
    }
    if (setupFailed || profileFailed) {
      return _SetupTaskResult.failed;
    }
    return _SetupTaskResult.completed;
  }
}
