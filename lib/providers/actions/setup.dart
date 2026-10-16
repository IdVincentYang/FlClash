part of '../action.dart';

enum _SetupTaskResult { completed, handoffToCoreRestart, failed, superseded }

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

  Future<void> _syncNativeRuntime(Map<String, Object?> snapshot) async {
    try {
      final startedAt = await _service?.getRunTime();
      if (!ref.mounted) return;
      final current = ref.read(nativeRequestStateProvider);
      if (current['processEpoch'] != snapshot['processEpoch'] ||
          current['revision'] != snapshot['revision'] ||
          current['phase'] != 'started') {
        return;
      }
      _startTime = startedAt;
      if (startedAt == null) {
        _stopRuntimeTicker();
        ref.read(runTimeProvider.notifier).value = null;
      } else {
        _setLocalRunning(true);
      }
    } catch (_) {
      if (ref.mounted) ref.read(runTimeProvider.notifier).value = null;
    }
  }

  Future<void> _updateStartTime() async {
    _startTime = await _service?.getRunTime();
  }

  Future<void> initStatus() async {
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
    if (!running) _setLocalRunning(false);
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

  Future<bool> applyProfile({bool silence = false, bool force = false}) async {
    final result = await _runSetup(force: force, silence: silence);
    return result == _SetupTaskResult.completed;
  }

  Future<_SetupTaskResult> _runSetup({
    bool silence = false,
    bool force = false,
    Future<bool> Function()? isCurrent,
  }) async {
    final generation = ++_setupGeneration;
    Future<void>? deferredCleanup;
    Future<bool> current() async =>
        generation == _setupGeneration &&
        (isCurrent == null || await isCurrent());
    final result = await _setupScheduler.run(() async {
      await dataMutations.run(() async {});
      if (!await current()) {
        return _SetupTaskResult.superseded;
      }
      return _setupConfig(
        force: force,
        silence: silence,
        isCurrent: current,
        isLatestSetup: () => generation == _setupGeneration,
        onCleanupDeferred: (cleanup) => deferredCleanup = cleanup,
        onUpdated: () async {
          await ref.read(proxiesActionProvider.notifier).updateGroups();
          await ref.read(providersProvider.notifier).syncProviders();
        },
      );
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
    FutureOr Function()? onUpdated,
    Future<bool> Function()? isCurrent,
    required bool Function() isLatestSetup,
    required void Function(Future<void>) onCleanupDeferred,
  }) async {
    final nativeContext = _isAndroid ? await _service!.getRequestState() : null;
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
    final selectedMap = Map<String, String>.of(ref.read(selectedMapProvider));
    final testUrl = ref.read(appSettingProvider).testUrl;
    final sources = <RequestSource>[];
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
            final keys = <String>{'profile:${selectedProfile.id}'};
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
              patchConfig: realPatchConfig,
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
      await finishUnregisteredStart();
      return _SetupTaskResult.superseded;
    }
    final yamlString = realProfile.yaml;
    final yamlMd5 = realProfile.md5;
    var setupFailed = false;
    var superseded = false;
    await globalState.loadingRun(
      () async {
        ConfigInput? input;
        ConfigApplyResult? recoveryPending;
        int? recoveryRequestId;
        var submittedToCore = false;
        try {
          final runtimeEpoch = (await _core.getConfigState()).runtimeEpoch;
          await _requests.mutate(() async {
            if (!await current()) {
              throw const RequestUnavailable('request_cancelled');
            }
            if (_isAndroid) {
              globalState.lastVpnState = ref.read(vpnStateProvider);
              final desired = ref.read(sharedStateProvider);
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
              profileId: profile!.id,
              profileName: profile.realLabel,
              selectedMap: selectedMap,
              testUrl: testUrl,
              sources: sources,
            );
          });
          final profileId = profile?.id;
          if (profileId != null) {
            await appPath.ensureProviderDirs(profileId);
          }
          for (var attempt = 0; ; attempt++) {
            if (!await current()) {
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
                active:
                    !ref.read(safeModeProvider) &&
                    (_latestRunRequest?.running ?? _isRunning) &&
                    !ref.read(suspendProvider),
              ),
            );
            ref
                .read(configStateProvider.notifier)
                .accept(result.fact, authoritative: true);
            if (result.status != 'superseded' && !result.fact.businessActive) {
              _setLocalRunning(false);
            }
            if (result.succeeded) {
              recoveryPending = null;
              if (!await current()) {
                throw const RequestUnavailable('request_cancelled');
              }
              if (_isAndroid && result.fact.businessActive) {
                final native = await _service!.getRequestState();
                ref
                    .read(nativeRequestStateProvider.notifier)
                    .onRequestState(native);
                await _syncNativeRuntime(native);
              }
              break;
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
        globalState.lastConfigMd5 = yamlMd5;
        await onUpdated?.call();
      },
      silence: true,
      tag: !silence ? LoadingTag.proxies : null,
    );
    if (superseded) return _SetupTaskResult.superseded;
    if (setupFailed) {
      return _SetupTaskResult.failed;
    }
    return _SetupTaskResult.completed;
  }
}
