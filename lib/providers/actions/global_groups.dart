part of '../action.dart';

@Riverpod(keepAlive: true)
class GlobalGroupsAction extends _$GlobalGroupsAction {
  bool _setupBusy = false, _scheduled = false, _syncing = false, _again = false;
  String? _failedStamp;
  bool _watching = false;

  @protected
  Request get requestClient => request;

  @override
  String? build() {
    ref.listen(initProvider, (_, _) {
      _watchSources();
      _schedule();
    });
    _watchSources();
    return null;
  }

  void _watchSources() {
    if (_watching || !ref.read(initProvider) || !requestClient.isAttached) {
      return;
    }
    _watching = true;
    ref.listen(currentProfileIdProvider, (_, _) {
      state = null;
      _schedule();
    });
    ref.listen(
      configStateProvider.select((value) => value.fact),
      (_, _) => _schedule(),
    );
    ref.listen(groupsProvider, (_, _) => _schedule());
    _schedule();
  }

  void setupExecutionChanged(bool busy) {
    _setupBusy = busy;
    if (!busy) {
      _watchSources();
      _schedule();
    }
  }

  void _schedule() {
    if (_syncing) {
      _again = true;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    unawaited(
      Future<void>(() async {
        _scheduled = false;
        if (!ref.mounted ||
            _setupBusy ||
            !ref.read(initProvider) ||
            !requestClient.isAttached) {
          return;
        }
        _syncing = true;
        try {
          do {
            _again = false;
            await _synchronize();
          } while (_again && ref.mounted && !_setupBusy);
        } catch (error) {
          if (ref.mounted) {
            state = userFacingErrorMessage(error, currentAppLocalizations);
          }
        } finally {
          _syncing = false;
        }
      }),
    );
  }

  Future<void> synchronizeApplicationGroups() => _synchronize(explicit: true);

  Future<List<LocalProxyGroup>> _materialize(
    List<LocalProxyGroup> definitions,
    Profile profile, {
    Set<int> attach = const {},
    Map<int, List<String>> references = const {},
  }) async {
    final names = localGroupNodes(
      ref.read(groupsProvider),
    ).map((node) => node.name).toList();
    final existing = {for (final group in profile.localGroups) group.id: group};
    final result = <LocalProxyGroup>[];
    for (final definition in definitions) {
      final binding = existing[definition.id];
      if (binding == null && !attach.contains(definition.id)) continue;
      List<String> matches;
      if (definition.regex.isEmpty) {
        matches = definition.nodes.where(names.contains).toList();
      } else if (!definition.enabled) {
        matches = binding?.matchedNodes ?? const [];
      } else {
        final response = await ref.read(coreHandlerProvider).sourceAcceptance({
          'action': 'matchLocalNodes',
          'pattern': definition.regex,
          'names': names,
        });
        if (response['patternError'] case final String error
            when error.isNotEmpty) {
          throw MessageException(error);
        }
        matches = List<String>.from(response['matches'] as List? ?? const []);
      }
      result.add(
        definition.copyWith(
          global: true,
          parent: null,
          parents:
              references[definition.id] ??
              binding?.entrances.toList() ??
              const [],
          matchedNodes: matches,
        ),
      );
    }
    return result;
  }

  Future<void> _synchronize({
    Set<int> attach = const {},
    bool explicit = false,
    int? expectedProfileId,
  }) async {
    final profile = ref.read(currentProfileProvider);
    final fact = ref.read(configStateProvider).fact;
    if (profile == null ||
        expectedProfileId != null && profile.id != expectedProfileId ||
        fact.profileId != profile.id ||
        !const {'ready', 'installed'}.contains(fact.phase)) {
      return;
    }
    final settings = await database.readApplicationRouting();
    attach = {
      ...attach,
      for (final rule in settings.rules.values)
        if (rule.enabled && rule.action == ApplicationRouteAction.proxy)
          if (applicationTargetFor(settings, rule, profile.id)
              case final target?
              when target.kind == ApplicationTargetKind.globalGroup)
            target.groupId!,
    };
    final definitions = await database.readGlobalGroups();
    if (!ref.mounted || ref.read(currentProfileIdProvider) != profile.id) {
      return;
    }
    final synchronized =
        attach.every(
          (id) => profile.localGroups.any((group) => group.id == id),
        ) &&
        profile.localGroups.every(
          (group) =>
              group.global &&
              definitions.any(
                (definition) => sameGlobalGroupDefinition(group, definition),
              ),
        );
    if (synchronized) {
      if (ref.mounted) state = null;
      return;
    }
    final stamp = SourceAcceptance.fingerprint({
      'profile': profile.id,
      'input': fact.fence,
      'nodes': localGroupNodes(
        ref.read(groupsProvider),
      ).map((node) => node.name).toList(),
      'picks': {
        for (final group in ref.read(groupsProvider)) group.name: group.now,
      },
      'definitions': definitions.map((group) => group.toJson()).toList(),
      'bindings': profile.localGroups.map((group) => group.toJson()).toList(),
    });
    if (!explicit && stamp == _failedStamp) return;
    if (localGroupNodes(ref.read(groupsProvider)).isEmpty &&
        definitions.any((group) => group.enabled)) {
      return;
    }
    try {
      final after = await _materialize(definitions, profile, attach: attach);
      await ref
          .read(profilesActionProvider.notifier)
          .saveLocalGroups(profile, after, expectedGlobalGroups: definitions);
      _failedStamp = null;
      if (ref.mounted) state = null;
    } catch (_) {
      _failedStamp = stamp;
      rethrow;
    }
  }

  Future<void> save(
    List<LocalProxyGroup> expected,
    List<LocalProxyGroup> groups, {
    int? profileId,
    int? activate,
    void Function()? onSaved,
  }) async {
    final definitions = groups.map(globalGroupDefinition).toList();
    if (definitions.length > localProxyGroupsLimit &&
            definitions.length > expected.length ||
        definitions.map((group) => group.id).toSet().length !=
            definitions.length ||
        definitions.map((group) => group.name).toSet().length !=
            definitions.length ||
        definitions.any(
          (group) =>
              group.id < 0 || group.nodes.length > localProxyGroupMembersLimit,
        )) {
      throw const LocalProxyGroupProblem('limit');
    }
    await requestClient.mutate(() async {
      if (profileId != null &&
              ref.read(currentProfileIdProvider) != profileId ||
          !const ListEquality<LocalProxyGroup>().equals(
            await database.readGlobalGroups(),
            expected,
          )) {
        throw const LocalProxyGroupProblem('changed');
      }
      final profiles = await database.profilesDao.query().get();
      for (final profile in profiles) {
        for (final snapshot in profile.localGroups) {
          final next = definitions
              .where((group) => group.id == snapshot.id)
              .firstOrNull;
          final previous = expected
              .where((group) => group.id == snapshot.id)
              .firstOrNull;
          if (previous != null &&
              snapshot.enabled &&
              (next == null ||
                  previous.enabled && !next.enabled ||
                  previous.name != next.name) &&
              (profile.selectedMap.values.contains(snapshot.name) ||
                  ref.read(configStateProvider).fact.profileId == profile.id &&
                      ref
                          .read(groupsProvider)
                          .any(
                            (group) =>
                                group.name != snapshot.name &&
                                group.now == snapshot.name,
                          ))) {
            throw LocalProxyGroupProblem('inUseProfile', profile.realLabel);
          }
        }
      }
      await requestClient.invalidate('application-config');
      await database.writeGlobalGroups(definitions);
    });
    if (ref.mounted) state = null;
    onSaved?.call();
    await _synchronize(
      attach: {?activate},
      explicit: true,
      expectedProfileId: profileId,
    );
  }

  Future<void> saveReferences(
    Profile expected,
    List<LocalProxyGroup> definitions,
    int groupId,
    List<String> parents,
  ) async {
    final fact = ref.read(configStateProvider).fact;
    if (ref.read(currentProfileIdProvider) != expected.id ||
        fact.profileId != expected.id ||
        !const {'ready', 'installed'}.contains(fact.phase)) {
      throw const LocalProxyGroupProblem('loading');
    }
    final after = await _materialize(
      definitions,
      expected,
      attach: {groupId},
      references: {groupId: parents},
    );
    final added = after.firstWhere((group) => group.id == groupId);
    if (parents.isNotEmpty && added.enabled && added.effectiveNodes.isEmpty) {
      throw const LocalProxyGroupProblem('noMatchingNodes');
    }
    await ref
        .read(profilesActionProvider.notifier)
        .saveLocalGroups(expected, after, expectedGlobalGroups: definitions);
    _failedStamp = null;
    if (ref.mounted) state = null;
  }
}
