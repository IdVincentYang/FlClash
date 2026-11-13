import 'dart:async';

import 'group_routing.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/config_input.dart';
import 'package:collection/collection.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/common/global_proxy_groups.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/source_review_status.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

final _appliedLocalGroupsProvider = FutureProvider.autoDispose((ref) async {
  final fact = ref.watch(configStateProvider).fact;
  if (fact.inputId.isEmpty) return null;
  final values = await ConfigInput.acceptedLocalGroups(
    home: await appPath.homeDirPath,
    accepted: fact,
    readFact: ref.read(coreHandlerProvider).getConfigState,
  );
  return values?.map(LocalProxyGroup.fromJson).toList();
}, retry: (retryCount, error) => null);

String _modeLabel(BuildContext context, GroupType type) => switch (type) {
  GroupType.URLTest => context.appLocalizations.localGroupsAutomatic,
  GroupType.Fallback => context.appLocalizations.localGroupsFallback,
  _ => context.appLocalizations.localGroupsManual,
};

class LocalGroupsView extends ConsumerStatefulWidget {
  const LocalGroupsView({super.key, this.initialParent});
  final String? initialParent;

  @override
  ConsumerState<LocalGroupsView> createState() => _LocalGroupsViewState();
}

class _LocalGroupsViewState extends ConsumerState<LocalGroupsView> {
  bool _busy = false;
  Object? _error;

  Future<void> _store(
    List<LocalProxyGroup> expected,
    List<LocalProxyGroup> groups, {
    int? profileId,
    int? activate,
    void Function()? onSaved,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(globalGroupsActionProvider.notifier)
          .save(
            expected,
            groups,
            profileId: profileId,
            activate: activate,
            onSaved: onSaved,
          );
    } catch (error) {
      if (mounted) setState(() => _error = error);
      rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEditor(
    List<LocalProxyGroup> expected,
    List<LocalProxyGroup> groups, {
    int? profileId,
    int? activate,
  }) {
    final saved = Completer<void>();
    unawaited(
      _store(
        expected,
        groups,
        profileId: profileId,
        activate: activate,
        onSaved: () {
          if (!saved.isCompleted) saved.complete();
        },
      ).then(
        (_) {
          if (!saved.isCompleted) saved.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!saved.isCompleted) {
            saved.completeError(error, stack);
          } else if (mounted) {
            context.showNotifier(
              userFacingErrorMessage(error, context.appLocalizations),
              level: MessageLevel.error,
            );
          }
        },
      ),
    );
    return saved.future;
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        context.showNotifier(
          userFacingErrorMessage(error, context.appLocalizations),
          level: MessageLevel.error,
        );
      }
    }
  }

  Future<void> _refresh(Profile? profile, {bool review = false}) =>
      _perform(() async {
        if (_busy) return;
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          if (review && profile != null) {
            await ref
                .read(profilesActionProvider.notifier)
                .manageSourcePermissions(profile, review: true);
          } else {
            await ref
                .read(setupActionProvider.notifier)
                .applyProfile(force: true);
          }
          await ref.read(proxiesActionProvider.notifier).updateGroups();
          if (profile != null && mounted) {
            ref.invalidate(profileReviewStatusProvider(profile));
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      });

  Future<void> _toggle(
    List<LocalProxyGroup> definitions,
    LocalProxyGroup group,
  ) => _perform(
    () => _store(definitions, [
      for (final item in definitions)
        item.id == group.id ? item.copyWith(enabled: !group.enabled) : item,
    ]),
  );

  Future<void> _delete(
    List<LocalProxyGroup> definitions,
    LocalProxyGroup group,
  ) => _perform(() async {
    if (await dialogs.showMessage(
              context: context,
              message: TextSpan(
                text: context.appLocalizations.localGroupsDelete(group.name),
              ),
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _store(definitions, [
      for (final item in definitions)
        if (item.id != group.id) item,
    ]);
  });

  Future<void> _edit(
    Profile? profile,
    List<LocalProxyGroup> definitions,
    List<Group> actual,
    List<Proxy> nodes, [
    LocalProxyGroup? group,
  ]) async {
    final value =
        group?.copyWith(
          testUrl: group.testUrl.isEmpty
              ? ref.read(appSettingProvider).testUrl
              : group.testUrl,
        ) ??
        LocalProxyGroup(
          id: snowflake.id,
          global: true,
          name: '',
          type: GroupType.Fallback,
          testUrl: ref.read(appSettingProvider).testUrl,
        );
    await BaseNavigator.push(
      context,
      LocalGroupEditor(
        value: value,
        nodes: nodes,
        matchNodes: (pattern) async {
          final result = await ref.read(coreHandlerProvider).sourceAcceptance({
            'action': 'matchLocalNodes',
            'pattern': pattern,
            'names': nodes.map((node) => node.name).toList(),
          });
          if (result['patternError'] case final String error
              when error.isNotEmpty) {
            throw MessageException(error);
          }
          return List<String>.from(result['matches'] as List? ?? const []);
        },
        reservedNames: {
          ...actual
              .where(
                (item) =>
                    !(profile?.localGroups ?? const <LocalProxyGroup>[]).any(
                      (binding) =>
                          binding.id == group?.id && binding.name == item.name,
                    ),
              )
              .map((item) => item.name),
          ...nodes.map((item) => item.name),
          ...definitions
              .where((item) => item.id != value.id)
              .map((item) => item.name),
        },
        onSave: (next) => _saveEditor(
          definitions,
          [
            for (final item in definitions)
              if (item.id != next.id) item,
            next,
          ],
          profileId: profile?.id,
          activate: group == null ? next.id : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final profile = ref.watch(currentProfileProvider);
    final library = ref.watch(globalLocalGroupsProvider);
    final definitions = library.value ?? const <LocalProxyGroup>[];
    final syncError = ref.watch(globalGroupsActionProvider);
    final actual = ref.watch(groupsProvider);
    final nodes = localGroupNodes(actual);
    final fact = ref.watch(configStateProvider).fact;
    final applied = ref.watch(_appliedLocalGroupsProvider).value;
    final review = profile == null
        ? null
        : ref.watch(profileReviewStatusProvider(profile));
    final managed = profile == null
        ? null
        : ref.watch(policySelectionProvider(profile.id)).value;
    final pending =
        profile != null &&
        (profile.localGroups.any(
              (binding) =>
                  !binding.global ||
                  !definitions.any(
                    (definition) =>
                        sameGlobalGroupDefinition(binding, definition),
                  ),
            ) ||
            (applied != null && fact.profileId == profile.id
                ? !const ListEquality<LocalProxyGroup>().equals(
                    applied.where((group) => group.enabled).toList(),
                    profile.localGroups
                        .where((group) => group.enabled)
                        .toList(),
                  )
                : profile.localGroups.any((group) {
                    final runtime = actual
                        .where((item) => item.name == group.name)
                        .firstOrNull;
                    return group.enabled
                        ? runtime == null ||
                              runtime.type != group.type ||
                              !const SetEquality<String>().equals(
                                runtime.all.map((node) => node.name).toSet(),
                                group.effectiveNodes.toSet(),
                              )
                        : runtime != null;
                  })));
    final loaded =
        profile != null &&
        fact.profileId == profile.id &&
        const {'ready', 'installed'}.contains(fact.phase) &&
        nodes.isNotEmpty &&
        managed == null;
    return CommonScaffold(
      title: l.localGroupsTitle,
      isLoading: _busy,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.add,
        tooltip: l.localGroupsCreate,
        onPressed: !_busy && loaded && library.hasValue
            ? () => _edit(profile, definitions, actual, nodes)
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).copyWith(
          top: context.contentTopPadding + 16,
          bottom: 16 + BottomInsetScope.of(context),
        ),
        children: [
          Text(l.localGroupsGlobal, style: context.textTheme.titleSmall),
          const SizedBox(height: 12),
          if (pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(l.localGroupsPending),
            ),
          if (!loaded) ...[
            Text(
              managed == null ? l.localGroupsLoadFirst : l.localGroupsManaged,
            ),
            TextButton(
              onPressed: _busy ? null : () => _refresh(profile),
              child: Text(l.retry),
            ),
            if (review?.asData?.value == SourceReviewStatus.required)
              TextButton(
                onPressed: _busy ? null : () => _refresh(profile, review: true),
                child: Text(l.sourceReviewTitle),
              ),
          ],
          if (_error != null || syncError != null || library.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                userFacingErrorMessage(
                  _error ?? syncError ?? library.error!,
                  l,
                ),
                style: TextStyle(color: context.colorScheme.error),
              ),
            ),
          if (library.isLoading) const LinearProgressIndicator(),
          if (library.hasValue && definitions.isEmpty) Text(l.localGroupsEmpty),
          for (final group in definitions)
            Card(
              child: ListTile(
                leading: const GlyphIcon(AppGlyphs.layers),
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${l.localGroupsOwn} · ${_modeLabel(context, group.type)} · ${l.localGroupsNodeCount(group.regex.isEmpty ? group.nodes.length : (profile?.localGroups.where((binding) => binding.id == group.id).firstOrNull?.effectiveNodes.length ?? 0))}${group.enabled ? '' : ' · ${l.disabled}'}\n${profile?.localGroups.any((binding) => binding.id == group.id) == true ? l.localGroupsReferences(profile!.localGroups.firstWhere((binding) => binding.id == group.id).entrances.length) : l.localGroupsUnbound}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => BaseNavigator.push(
                  context,
                  LocalGroupDetail(
                    name: group.name,
                    localId: group.id,
                    onEdit: () async {
                      final latest = ref.read(currentProfileProvider);
                      final catalog = ref.read(globalLocalGroupsProvider).value;
                      final current = catalog
                          ?.where((value) => value.id == group.id)
                          .firstOrNull;
                      if (current == null || catalog == null) return;
                      final runtime = ref.read(groupsProvider);
                      await _edit(
                        latest,
                        catalog,
                        runtime,
                        localGroupNodes(runtime),
                        current,
                      );
                    },
                  ),
                ),
                trailing: CommonPopupBox(
                  targetBuilder: (open) => IconButton(
                    tooltip: l.localGroupsActions(group.name),
                    icon: const GlyphIcon(AppGlyphs.more),
                    onPressed: () => open(),
                  ),
                  popupBuilder: (_) => CommonPopupMenu(
                    items: [
                      CommonPopupMenuItem(
                        label: l.localGroupsRouteThis,
                        glyph: AppGlyphs.layers,
                        onPressed: !_busy && loaded
                            ? () => manageLocalGroupReferences(
                                context,
                                ref,
                                groupName: group.name,
                              )
                            : null,
                      ),
                      CommonPopupMenuItem(
                        label: l.edit,
                        glyph: AppGlyphs.edit,
                        onPressed: !_busy
                            ? () => _edit(
                                profile,
                                definitions,
                                actual,
                                nodes,
                                group,
                              )
                            : null,
                      ),
                      CommonPopupMenuItem(
                        label: group.enabled
                            ? l.localGroupsDisable
                            : l.localGroupsEnable,
                        onPressed: !_busy
                            ? () => _toggle(definitions, group)
                            : null,
                      ),
                      CommonPopupMenuItem(
                        label: l.delete,
                        glyph: AppGlyphs.delete,
                        danger: true,
                        onPressed: !_busy
                            ? () => _delete(definitions, group)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (loaded)
            for (final group in actual.where(
              (group) =>
                  group.name != 'GLOBAL' &&
                  !profile.localGroups.any((local) => local.name == group.name),
            ))
              Card(
                child: ListTile(
                  leading: const GlyphIcon(AppGlyphs.layers),
                  title: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${l.localGroupsSubscription} · ${_modeLabel(context, group.type)} · ${l.localGroupsNodeCount(group.all.length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const SizedBox(
                    width: 48,
                    child: Center(child: GlyphIcon(AppGlyphs.chevronForward)),
                  ),
                  onTap: () => BaseNavigator.push(
                    context,
                    LocalGroupDetail(name: group.name),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class LocalGroupEditor extends StatefulWidget {
  const LocalGroupEditor({
    super.key,
    required this.value,
    required this.nodes,
    required this.matchNodes,
    required this.reservedNames,
    required this.onSave,
  });
  final LocalProxyGroup value;
  final List<Proxy> nodes;
  final Future<List<String>> Function(String) matchNodes;
  final Set<String> reservedNames;
  final Future<void> Function(LocalProxyGroup) onSave;

  @override
  State<LocalGroupEditor> createState() => _LocalGroupEditorState();
}

class _LocalGroupEditorState extends State<LocalGroupEditor> {
  final _name = TextEditingController();
  final _query = TextEditingController();
  final _testUrl = TextEditingController();
  late Set<String> _members;
  late Set<String> _excluded;
  late GroupType _type;
  List<String> _matches = [];
  Timer? _matchTimer;
  int _matchRevision = 0;
  bool _matching = false;
  Object? _patternError;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _name.text = widget.value.name;
    _testUrl.text = widget.value.testUrl;
    _members = widget.value.nodes.toSet();
    _excluded = widget.value.excludedNodes.toSet();
    _type = widget.value.type == GroupType.URLTest
        ? GroupType.URLTest
        : GroupType.Fallback;
    _query.text = widget.value.regex;
    _matches = widget.value.matchedNodes;
    if (_query.text.isNotEmpty) unawaited(_match());
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
    _matchRevision++;
    _name.dispose();
    _query.dispose();
    _testUrl.dispose();
    super.dispose();
  }

  Future<void> _match() async {
    _matchTimer?.cancel();
    final revision = ++_matchRevision;
    final pattern = _query.text;
    if (pattern.isEmpty) {
      if (mounted) {
        setState(() {
          _matching = false;
          _patternError = null;
          _matches = [];
        });
      }
      return;
    }
    setState(() {
      _matching = true;
      _patternError = null;
    });
    try {
      final matches = await widget.matchNodes(pattern);
      if (mounted && revision == _matchRevision) {
        setState(() => _matches = matches);
      }
    } catch (error) {
      if (mounted && revision == _matchRevision) {
        setState(() {
          _patternError = error;
          _matches = [];
        });
      }
    } finally {
      if (mounted && revision == _matchRevision) {
        setState(() => _matching = false);
      }
    }
  }

  void _queryChanged(String value) {
    _matchRevision++;
    _matchTimer?.cancel();
    _excluded.clear();
    setState(() {
      _matching = value.isNotEmpty;
      _patternError = null;
    });
    if (value.isEmpty) {
      unawaited(_match());
      return;
    }
    _matchTimer = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_match()),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_query.text.isNotEmpty) await _match();
      if (!mounted) return;
      if (_patternError != null) {
        throw MessageException(
          userFacingErrorMessage(_patternError!, context.appLocalizations),
        );
      }
      final members = _query.text.isEmpty
          ? _members.toList()
          : _matches.where((name) => !_excluded.contains(name)).toList();
      final name = _name.text.trim();
      if (name.isEmpty ||
          name.length > 128 ||
          widget.reservedNames.contains(name) ||
          const {
            'GLOBAL',
            'DIRECT',
            'REJECT',
            'REJECT-DROP',
            'PASS',
            'PASS-RULE',
            'COMPATIBLE',
          }.contains(name) ||
          name.runes.any((rune) => rune < 32 || rune == 127)) {
        throw const LocalProxyGroupProblem('name');
      }
      if (members.isEmpty && _query.text.isEmpty) {
        throw const LocalProxyGroupProblem('members');
      }
      if (members.length > localProxyGroupMembersLimit) {
        throw const LocalProxyGroupProblem('limit');
      }
      bool validTestUrl(String value) {
        final uri = Uri.tryParse(value);
        return uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty;
      }

      final draftTestUrl = _testUrl.text.trim();
      final testUrl = _type == GroupType.Fallback && !validTestUrl(draftTestUrl)
          ? widget.value.testUrl
          : draftTestUrl;
      if (!validTestUrl(testUrl)) {
        throw const LocalProxyGroupProblem('testUrl');
      }
      await widget.onSave(
        widget.value.copyWith(
          global: true,
          name: name,
          type: _type,
          nodes: _members.toList(),
          regex: _query.text,
          matchedNodes: _matches,
          excludedNodes: _query.text.isEmpty ? const [] : _excluded.toList(),
          testUrl: testUrl,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final regex = _query.text.isNotEmpty;
    final visibleNodes = widget.nodes
        .where((node) => !regex || _matches.contains(node.name))
        .toList();
    return CommonScaffold(
      title: widget.value.name.isEmpty ? l.localGroupsCreate : l.edit,
      isLoading: _saving,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: l.save,
        onPressed: _saving ? null : _save,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).copyWith(
          top: context.contentTopPadding + 16,
          bottom: 16 + BottomInsetScope.of(context),
        ),
        children: [
          if (_error != null)
            Text(
              userFacingErrorMessage(_error!, l),
              style: TextStyle(color: context.colorScheme.error),
            ),
          if (_saving)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(l.localGroupsSaving),
            ),
          ListHeader(
            title: l.localGroupsIdentitySection,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _name,
                enabled: !_saving,
                decoration: InputDecoration(labelText: l.name),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListHeader(
            title: l.localGroupsStrategySection,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l.localGroupsEnableSpeedTest),
                  value: _type == GroupType.URLTest,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _type = value
                              ? GroupType.URLTest
                              : GroupType.Fallback,
                        ),
                ),
                if (_type == GroupType.URLTest)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: TextField(
                      controller: _testUrl,
                      enabled: !_saving,
                      decoration: InputDecoration(labelText: l.testUrl),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListHeader(
            title: l.localGroupsNodesSection,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _query,
                enabled: !_saving,
                onChanged: _queryChanged,
                decoration: InputDecoration(
                  labelText: l.localGroupsRegex,
                  helperText: l.localGroupsRegexHelp,
                  helperMaxLines: 2,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_query.text.isNotEmpty)
                        IconButton(
                          tooltip: l.clearSearch,
                          icon: const GlyphIcon(AppGlyphs.close),
                          onPressed: _saving
                              ? null
                              : () {
                                  _query.clear();
                                  _queryChanged('');
                                },
                        ),
                      IconButton(
                        tooltip: l.localGroupsRegexDocs,
                        icon: const GlyphIcon(AppGlyphs.info),
                        onPressed: () =>
                            dialogs.openUrl('https://pkg.go.dev/regexp/syntax'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_matching) const LinearProgressIndicator(),
          if (_patternError != null)
            Text(
              userFacingErrorMessage(_patternError!, l),
              style: TextStyle(color: context.colorScheme.error),
            ),
          Text(
            l.selectedCountTitle(
              regex
                  ? _matches.where((name) => !_excluded.contains(name)).length
                  : _members.length,
            ),
          ),
          if (visibleNodes.isEmpty) Text(l.nullTip(l.proxies)),
          if (!regex)
            for (final missing
                in _members
                    .where(
                      (name) => !widget.nodes.any((node) => node.name == name),
                    )
                    .toList())
              CheckboxListTile(
                value: true,
                title: Text(l.localGroupsMissing(missing)),
                onChanged: _saving
                    ? null
                    : (_) => setState(() => _members.remove(missing)),
              ),
          for (final proxy in visibleNodes)
            CheckboxListTile(
              value: regex
                  ? !_excluded.contains(proxy.name)
                  : _members.contains(proxy.name),
              title: Text(proxy.name),
              subtitle: Text(proxy.type),
              onChanged: _saving
                  ? null
                  : (selected) => setState(() {
                      if (regex) {
                        if (selected == true) {
                          _excluded.remove(proxy.name);
                        } else {
                          _excluded.add(proxy.name);
                        }
                        return;
                      }
                      if (selected == true) {
                        _members.add(proxy.name);
                      } else {
                        _members.remove(proxy.name);
                      }
                    }),
            ),
        ],
      ),
    );
  }
}

class LocalGroupDetail extends ConsumerStatefulWidget {
  const LocalGroupDetail({
    super.key,
    required this.name,
    this.localId,
    this.onEdit,
  });
  final String name;
  final int? localId;
  final Future<void> Function()? onEdit;

  @override
  ConsumerState<LocalGroupDetail> createState() => _LocalGroupDetailState();
}

class _LocalGroupDetailState extends ConsumerState<LocalGroupDetail> {
  bool _busy = false;

  Future<void> _select(Group group, String node) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(proxiesActionProvider.notifier)
          .changeProxy(
            groupName: group.name,
            proxyName: node,
            transient: group.type.isComputedSelected,
          );
      await ref.read(proxiesActionProvider.notifier).updateGroups();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final saved = ref
        .watch(currentProfileProvider)
        ?.localGroups
        .where((group) => group.id == widget.localId)
        .firstOrNull;
    final definition = ref
        .watch(globalLocalGroupsProvider)
        .value
        ?.where((group) => group.id == widget.localId)
        .firstOrNull;
    final name = definition?.name ?? saved?.name ?? widget.name;
    final runtimeName = saved?.name ?? name;
    final group = widget.localId != null && saved == null
        ? null
        : ref
              .watch(groupsProvider)
              .where((group) => group.name == runtimeName)
              .firstOrNull;
    final nodes = localGroupNodes(ref.watch(groupsProvider));
    final selected = ref.watch(selectedProxyNameProvider(runtimeName));
    final exit = ref
        .watch(realSelectedProxyStateProvider(runtimeName))
        .proxyName;
    return CommonScaffold(
      title: name,
      isLoading: _busy,
      iconActions: [
        if (definition != null)
          IconButtonData(
            glyph: AppGlyphs.layers,
            tooltip: l.localGroupsRouteThis,
            onPressed: _busy
                ? null
                : () =>
                      manageLocalGroupReferences(context, ref, groupName: name),
          ),
      ],
      primaryAction: widget.onEdit == null
          ? null
          : IconButtonData(
              glyph: AppGlyphs.edit,
              tooltip: l.edit,
              onPressed: _busy ? null : widget.onEdit,
            ),
      body: ListView(
        padding: const EdgeInsets.all(16).copyWith(
          top: context.contentTopPadding + 16,
          bottom: 16 + BottomInsetScope.of(context),
        ),
        children: [
          if (group == null) ...[
            Text(
              saved == null && definition != null
                  ? l.localGroupsUnbound
                  : l.localGroupsUnavailable,
            ),
            if (definition != null || saved != null)
              for (final name
                  in definition?.regex.isEmpty == true
                      ? definition!.nodes
                      : saved?.effectiveNodes ?? const <String>[])
                Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(
                      nodes
                              .where((node) => node.name == name)
                              .firstOrNull
                              ?.type ??
                          l.localGroupsMissing(name),
                    ),
                  ),
                ),
          ] else ...[
            Text(_modeLabel(context, group.type)),
            const SizedBox(height: 12),
            Text(
              l.localGroupsPreferred(selected ?? '—'),
              style: context.textTheme.titleMedium,
            ),
            if (exit.isNotEmpty && exit != selected)
              Text(l.localGroupsActualExit(exit)),
            if (group.type.isComputedSelected) Text(l.localGroupsTransientHelp),
            if (group.type == GroupType.Selector)
              Text(l.localGroupsSelectNodeHelp),
            const SizedBox(height: 12),
            for (final node in group.all)
              Card(
                child: ListTile(
                  title: Text(node.name),
                  subtitle: Text(node.type),
                  selected: selected == node.name,
                  trailing: selected == node.name
                      ? const GlyphIcon(AppGlyphs.check)
                      : null,
                  onTap:
                      !_busy &&
                          (group.type.isComputedSelected ||
                              group.type == GroupType.Selector)
                      ? () => _select(group, node.name)
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
