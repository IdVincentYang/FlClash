part of '../action.dart';

class _DelayTestTarget {
  const _DelayTestTarget({
    required this.proxyName,
    required this.testUrl,
    required this.key,
  });

  final String proxyName;
  final String testUrl;
  final String key;
}

typedef _DelayTestBatch = ({List<Proxy> proxies, String? testUrl});

class _DelayTestJob {
  _DelayTestJob(Iterable<String> keys) : held = keys.toSet();

  final Set<String> held;
  final Set<String> startedOnDispatch = {};
  bool cancelled = false;
  Object? failure;
  final cancellation = Completer<void>();
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  Request get requestClient => request;

  final TaskPool _delayTestPool = TaskPool(maxConcurrentDelayTests);

  final List<_DelayTestJob> _delayTestJobs = [];
  final Map<String, _DelayTestJob> _delayTestOwners = {};

  final List<Delay> _bufferedDelays = [];

  final List<String> _bufferedStarts = [];

  final List<String> _bufferedFinishes = [];

  Timer? _delayFlushTimer;
  String _localGroupInput = '';
  int _groupsRefreshSequence = 0;

  final Map<String, String> _pendingSelectedRollback = {};
  final _delaySessions = <RequestSession>{};

  @override
  void build() {
    ref.onDispose(() {
      _delayFlushTimer?.cancel();
      for (final job in _delayTestJobs) {
        job.cancelled = true;
        if (!job.cancellation.isCompleted) job.cancellation.complete();
      }
    });
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        cancelDelayTests();
      }
    });
  }

  void cancelDelayTests() {
    for (final session in List.of(_delaySessions)) {
      session.close();
    }
    for (final job in _delayTestJobs) {
      job.cancelled = true;
      if (!job.cancellation.isCompleted) job.cancellation.complete();
      job.held.clear();
    }
    _delayTestOwners.clear();
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    _bufferedDelays.clear();
    _bufferedStarts.clear();
    _bufferedFinishes.clear();
    ref.read(pendingDelayTestsProvider.notifier).clear();
    ref.read(delayTestFailuresProvider.notifier).clear();
  }

  void _scheduleDelayFlush() {
    _delayFlushTimer ??= Timer(renderThrottleDuration, _flushDelayResults);
  }

  void _flushDelayResults() {
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    if (_bufferedDelays.isNotEmpty) {
      final delays = List.of(_bufferedDelays);
      _bufferedDelays.clear();
      ref.read(delayDataSourceProvider.notifier).setDelays(delays);
      ref
          .read(delayTestFailuresProvider.notifier)
          .remove(delays.map((delay) => delayTestKey(delay.url, delay.name)));
    }
    if (_bufferedStarts.isNotEmpty || _bufferedFinishes.isNotEmpty) {
      final started = List.of(_bufferedStarts);
      final finished = List.of(_bufferedFinishes);
      _bufferedStarts.clear();
      _bufferedFinishes.clear();
      ref
          .read(pendingDelayTestsProvider.notifier)
          .apply(started: started, finished: finished);
    }
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(
    String groupName,
    String proxyName, {
    bool transient = false,
  }) {
    final observed = ref.read(configStateProvider).fact;
    if (observed.profileId != ref.read(currentProfileIdProvider)) return;
    if (!transient) {
      _pendingSelectedRollback.putIfAbsent(
        groupName,
        () => _currentSelectedName(groupName),
      );
    }
    if (!transient) {
      ref
          .read(profilesActionProvider.notifier)
          .updateCurrentSelectedMap(groupName, proxyName);
    }
    debouncer.call((FunctionTag.changeProxy, groupName), (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(
        groupName: groupName,
        proxyName: proxyName,
        observed: observed,
        transient: transient,
      );
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  String _currentSelectedName(String groupName) {
    return ref.read(currentProfileProvider)?.selectedMap[groupName] ?? '';
  }

  Future<void> updateGroups({Future<bool> Function()? isCurrent}) async {
    try {
      commonPrint.log('updateGroups');
      final observed = ref.read(configStateProvider).fact;
      if (observed.profileId != null &&
          observed.profileId != ref.read(currentProfileIdProvider)) {
        ref.read(groupsProvider.notifier).value = [];
        return;
      }
      bool keepCachedGroups() =>
          isCurrent == null &&
          ref.read(proxyPreparationProvider).stage != null &&
          ref.read(groupsProvider).isNotEmpty;
      if (keepCachedGroups()) return;
      final sequence = ++_groupsRefreshSequence;
      final groups = await retry<List<Group>>(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          try {
            return await _core.getProxiesGroups(
              selectedMap: selectedMap,
              sortType: sortType,
              delayMap: delayMap,
              defaultTestUrl: testUrl,
            );
          } catch (e) {
            commonPrint.log(
              'updateGroups error: $e',
              logLevel: coreFailureLogLevel(e),
            );
            return [];
          }
        },
        retryIf: (res) => res.isEmpty,
      );
      if (ref.mounted &&
          sequence == _groupsRefreshSequence &&
          !keepCachedGroups() &&
          groups.isNotEmpty &&
          (isCurrent == null || await isCurrent()) &&
          observed.profileId == ref.read(configStateProvider).fact.profileId &&
          observed.profileId == ref.read(currentProfileIdProvider)) {
        ref.read(groupsProvider.notifier).value = groups;
        final fact = ref.read(configStateProvider).fact;
        if (fact.inputId.isNotEmpty &&
            fact.inputId != _localGroupInput &&
            fact.profileId == ref.read(currentProfileIdProvider)) {
          final applied = await ConfigInput.acceptedLocalGroups(
            home: await appPath.homeDirPath,
            accepted: fact,
            readFact: _core.getConfigState,
          );
          if (applied != null &&
              ref.mounted &&
              (isCurrent == null || await isCurrent())) {
            final accepted = applied.map(LocalProxyGroup.fromJson).toList();
            final profile = ref.read(currentProfileProvider);
            if (profile != null && profile.id == fact.profileId) {
              bool sameDefinitions(List<LocalProxyGroup> groups) =>
                  const ListEquality<LocalProxyGroup>().equals(
                    groups
                        .map((group) => group.copyWith(matchedNodes: const []))
                        .toList(),
                    accepted
                        .map((group) => group.copyWith(matchedNodes: const []))
                        .toList(),
                  );
              if (sameDefinitions(profile.localGroups) &&
                  !const ListEquality<LocalProxyGroup>().equals(
                    profile.localGroups,
                    accepted,
                  )) {
                await ref
                    .read(profilesProvider.notifier)
                    .updateProfile(
                      profile.id,
                      (current) => sameDefinitions(current.localGroups)
                          ? current.copyWith(localGroups: accepted)
                          : current,
                    );
              }
              _localGroupInput = fact.inputId;
            }
          }
        }
      }
    } catch (e) {
      // The Core failure path already runs inside the retry task above; a
      // throw here only means ref.read hit a disposed container or the
      // groupsProvider write itself failed.
      commonPrint.log(
        'updateGroups failed: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    unawaited(
      ref
          .read(profilesProvider.notifier)
          .updateProfile(
            profile.id,
            (current) => current.copyWith(currentGroupName: groupName),
          ),
    );
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    unawaited(
      ref
          .read(profilesProvider.notifier)
          .updateProfile(
            currentProfile.id,
            (current) => current.copyWith(unfoldSet: value),
          ),
    );
  }

  void setDelay(Delay delay) {
    _bufferedDelays.add(delay);
    _scheduleDelayFlush();
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
    ConfigFact? observed,
    bool transient = false,
  }) async {
    final fact = observed ?? ref.read(configStateProvider).fact;
    if (fact.profileId != ref.read(currentProfileIdProvider)) return;
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final rollbackName =
        _pendingSelectedRollback.remove(groupName) ??
        _currentSelectedName(groupName);
    if (!transient) {
      profilesAction.updateCurrentSelectedMap(groupName, proxyName);
    }
    final ChangeProxyResult result;
    try {
      result = await _core.changeProxy(
        ChangeProxyParams(
          groupName: groupName,
          proxyName: proxyName,
          owner: fact.owner,
          token: fact.token,
          transient: transient,
        ),
      );
      if (result.message.isNotEmpty) {
        throw MessageException(result.message);
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
      if (!transient) {
        profilesAction.updateCurrentSelectedMap(groupName, rollbackName);
      }
      dialogs.showNotifier(
        currentAppLocalizations.changeProxyFailedTip,
        level: MessageLevel.error,
      );
      return;
    }
    if (!result.changed) {
      return;
    }
    try {
      if (ref.read(appSettingProvider).closeConnections) {
        await _core.closeConnections();
      } else {
        await _core.resetConnections();
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) connection reset failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      String message;
      try {
        message = await _core.updateExternalProvider(
          providerName: provider.name,
        );
      } on CoreMethodException catch (error) {
        if (!request.requiresSourceAcceptance ||
            provider.sourceKey.isEmpty ||
            error.code != 'source_review_required') {
          rethrow;
        }
        await _sourceAcceptance(
          _core,
          request,
          confirm: ref.read(sourceConfirmationProvider),
        ).applyProvider(
          key: provider.sourceKey,
          name: provider.name,
          kind: provider.type == 'Rule' ? 'provider-rule' : 'provider-proxy',
        );
        message = '';
      }
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<String> sideLoadExternalProvider(
    ExternalProvider provider,
    String data, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final message = await _core.sideLoadExternalProvider(
        providerName: provider.name,
        data: data,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<void> sideLoadSourceProvider(
    ExternalProvider provider,
    List<int> body,
  ) async {
    await _sourceAcceptance(
      _core,
      request,
      confirm: ref.read(sourceConfirmationProvider),
    ).applyProvider(
      key: provider.sourceKey,
      name: provider.name,
      kind: provider.type == 'Rule' ? 'provider-rule' : 'provider-proxy',
      body: body,
    );
    ref
        .read(providersProvider.notifier)
        .setProvider(await _core.getExternalProvider(provider.name));
  }

  Future<void> manageProviderSource(ExternalProvider provider) async {
    if (!request.requiresSourceAcceptance || provider.sourceKey.isEmpty) return;
    final acceptance = _sourceAcceptance(
      _core,
      request,
      confirm: ref.read(sourceConfirmationProvider),
    );
    final source = await request.captureSource(provider.sourceKey);
    final permissions = await acceptance.permissions(
      source: source,
      kind: provider.type == 'Rule' ? 'provider-rule' : 'provider-proxy',
    );
    if (permissions.isEmpty) return;
    final choice = await dialogs.showCommonDialog<SourcePermissionChoice>(
      child: SourcePermissionsDialog(
        label: provider.name,
        permissions: permissions,
      ),
    );
    if (choice == null) return;
    if (choice.action == SourcePermissionAction.review) {
      await acceptance.applyProvider(
        key: provider.sourceKey,
        name: provider.name,
        kind: provider.type == 'Rule' ? 'provider-rule' : 'provider-proxy',
        forceReview: true,
      );
    } else {
      await acceptance.withdraw(
        choice.permission!,
        stopUse: choice.action == SourcePermissionAction.stopUse,
      );
    }
    await ref.read(configStateProvider.notifier).refresh();
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) {
    return _runDelayTests([
      (proxies: [proxy], testUrl: testUrl),
    ]);
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    await _runDelayTests([(proxies: proxies, testUrl: testUrl)]);
    ref.read(sortNumProvider.notifier).add();
  }

  Future<void> delayTestGroups(List<Group> groups) async {
    await _runDelayTests([
      for (final group in groups) (proxies: group.all, testUrl: group.testUrl),
    ]);
    ref.read(sortNumProvider.notifier).add();
  }

  Future<void> delayTestPageGroup(String groupName) async {
    final group = ref.read(groupsProvider).getGroup(groupName);
    if (group == null) {
      dialogs.showNotifier(
        currentAppLocalizations.localGroupsLoadFirst,
        level: MessageLevel.warning,
      );
      return;
    }
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    if (!testing.start(groupName)) {
      return;
    }
    try {
      final query = SearchQuery(ref.read(queryProvider(QueryTag.proxies)));
      await delayTest(
        group.all.whereMatches(query, (proxy) => proxy.searchFields).toList(),
        group.testUrl,
      );
    } finally {
      testing.stop(groupName);
    }
  }

  List<_DelayTestTarget> _resolveDelayTestTargets(
    List<_DelayTestBatch> batches,
  ) {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final seen = <String>{};
    final targets = <_DelayTestTarget>[];
    for (final batch in batches) {
      final fallbackTestUrl = ref.read(realTestUrlProvider(batch.testUrl));
      for (final proxy in batch.proxies) {
        final state = computeRealSelectedProxyState(
          proxy.name,
          groups: groups,
          selectedMap: selectedMap,
        );
        if (state.proxyName.isEmpty) {
          continue;
        }
        final currentTestUrl = state.testUrl.takeFirstValid([fallbackTestUrl]);
        final key = delayTestKey(currentTestUrl, state.proxyName);
        if (!seen.add(key)) {
          continue;
        }
        targets.add(
          _DelayTestTarget(
            proxyName: state.proxyName,
            testUrl: currentTestUrl,
            key: key,
          ),
        );
      }
    }
    return targets;
  }

  Future<void> _runDelayTests(List<_DelayTestBatch> batches) async {
    final targets = _resolveDelayTestTargets(batches);
    if (targets.isEmpty) {
      return;
    }
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    final job = _DelayTestJob(targets.map((target) => target.key));
    _delayTestJobs.add(job);
    for (final key in job.held) {
      _delayTestOwners[key] = job;
    }
    ref.read(delayTestFailuresProvider.notifier).remove(job.held);
    // TaskPool.run starts a task synchronously while it has an idle slot.
    job.startedOnDispatch.addAll(
      targets.take(_delayTestPool.idleSlots).map((target) => target.key),
    );
    final preparing = ref.read(proxyPreparationProvider).stage != null;
    if (preparing || requestClient.hasNativeClient) {
      job.startedOnDispatch.clear();
    }
    pending.apply(acquired: job.held, started: job.startedOnDispatch);
    try {
      if (preparing) {
        final ready = Completer<void>();
        final subscription = ref.listen(proxyPreparationProvider, (_, next) {
          if (next.stage == null && !ready.isCompleted) ready.complete();
        });
        try {
          if (ref.read(proxyPreparationProvider).stage != null) {
            await Future.any([ready.future, job.cancellation.future]);
          }
        } finally {
          subscription.close();
        }
      }
      if (job.cancelled) return;
      if (requestClient.hasNativeClient) {
        Object? unavailable;
        try {
          final run = await requestClient.captureNativeRunState();
          if (run?['intentRunning'] != true ||
              run?['phase'] != 'started' ||
              run?['paused'] == true) {
            unavailable = const RequestUnavailable('delay_test_requires_proxy');
          }
        } catch (error) {
          unavailable = error;
        }
        if (job.cancelled) return;
        if (unavailable != null) {
          ref.read(delayTestFailuresProvider.notifier).setAll({
            for (final target in targets) target.key: unavailable,
          });
          _reportDelayTestFailure(unavailable);
          return;
        }
      }

      if (job.cancelled) return;
      if (job.startedOnDispatch.isEmpty) {
        job.startedOnDispatch.addAll(
          targets.take(_delayTestPool.idleSlots).map((target) => target.key),
        );
        pending.apply(started: job.startedOnDispatch);
      }
      await Future.wait(
        targets.map(
          (target) => _delayTestPool.run(() => _runDelayTest(job, target)),
        ),
      );
    } finally {
      _delayTestJobs.remove(job);
      _delayTestOwners.removeWhere((_, owner) => identical(owner, job));
      if (ref.mounted) _flushDelayResults();
      final abandoned = job.held.toList();
      job.held.clear();
      if (ref.mounted) {
        pending.apply(
          finished: abandoned.where(job.startedOnDispatch.contains),
          released: abandoned.where(
            (key) => !job.startedOnDispatch.contains(key),
          ),
        );
      }
    }
    if (ref.mounted && job.failure != null) {
      final error = job.failure!;
      _reportDelayTestFailure(error);
    }
  }

  void _reportDelayTestFailure(Object error) {
    dialogs.showNotifier(
      currentAppLocalizations.delayTestFailed(
        userFacingErrorMessage(error, currentAppLocalizations),
      ),
      level: MessageLevel.warning,
    );
  }

  Future<void> _runDelayTest(_DelayTestJob job, _DelayTestTarget target) async {
    if (job.cancelled) {
      return;
    }
    if (!job.startedOnDispatch.contains(target.key)) {
      _bufferedStarts.add(target.key);
      _scheduleDelayFlush();
    }
    RequestSession? session;
    try {
      session = await requestClient.begin(
        key: 'delay:${target.key}',
        url: target.testUrl,
        explicitTarget: target.proxyName,
      );
      _delaySessions.add(session);
      if (job.cancelled) {
        session.close();
        return;
      }
      final delay = await session.run(
        () => _core.getDelay(target.testUrl, target.proxyName),
      );
      await session.check();
      if (!job.cancelled) {
        if (delay == null) {
          throw const RequestUnavailable('delay_test_no_result');
        }
        setDelay(delay);
      }
    } catch (error) {
      if (!job.cancelled && identical(_delayTestOwners[target.key], job)) {
        job.failure ??= error;
        ref.read(delayTestFailuresProvider.notifier).set(target.key, error);
      }
      if (error is CoreMethodException && error.isCoreUnavailable) {
        job.cancelled = true;
      }
      commonPrint.log(
        'Delay test failed for ${target.proxyName}: '
        '${error is RequestUnavailable ? error.code : error}',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      session?.close();
      _delaySessions.remove(session);
      if (job.held.remove(target.key) && ref.mounted) {
        _bufferedFinishes.add(target.key);
        _scheduleDelayFlush();
      }
    }
  }
}
