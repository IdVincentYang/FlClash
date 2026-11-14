import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/features/overwrite/overwrite.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/widgets/host_rule.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/widgets/application_policy_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ApplicationHostRuleView extends ConsumerStatefulWidget {
  const ApplicationHostRuleView({
    super.key,
    required this.host,
    required this.packages,
    required this.appLabel,
  });
  final String host, appLabel;
  final List<String> packages;
  @override
  ConsumerState<ApplicationHostRuleView> createState() =>
      _ApplicationHostRuleViewState();
}

class _ApplicationHostRuleViewState
    extends ConsumerState<ApplicationHostRuleView> {
  final _editor = GlobalKey<RuleEditorFormState>();
  final _drafts = <bool, Rule>{}, _baselines = <bool, Rule>{};
  bool _general = false, _initialized = false, _busy = false;
  int? _profileId;
  String? _error;

  Rule _empty(bool general) => hostRuleTemplate(widget.host).copyWith(
    hostBinding: HostRuleBinding(
      packageName: general ? null : widget.packages.firstOrNull,
    ),
  );
  bool get _dirty => _drafts.entries.any((e) => e.value != _baselines[e.key]);
  Future<bool> _leave() async =>
      !_busy &&
      (!_dirty ||
          await dialogs.showMessage(
                context: context,
                message: TextSpan(
                  text: context.appLocalizations.appHostDiscard,
                ),
              ) ==
              true);

  void _initialize(ApplicationRoutingSettings settings) {
    if (_initialized) return;
    _initialized = true;
    _profileId = ref.read(currentProfileIdProvider);
    final effective = effectiveHostPolicyForPackages(
      settings,
      widget.host,
      widget.packages,
      _profileId,
      ref.read(patchClashConfigProvider).mode,
    );
    _general =
        widget.packages.isEmpty ||
        effective.hostRule?.hostBinding?.packageName == null &&
            effective.hostRule != null;
    for (final general in [false, true]) {
      final saved = applicationHostRule(
        settings,
        widget.host,
        general ? null : widget.packages.firstOrNull,
        _profileId,
        includeDisabled: true,
      );
      _baselines[general] = saved ?? _empty(general);
      _drafts[general] = _baselines[general]!;
    }
  }

  Future<void> _save() async {
    var validated = _editor.currentState?.validatedValue();
    if (_busy || validated == null || _profileId == null) return;
    if (!_general &&
            !await confirmApplicationPackages(context, widget.packages) ||
        !mounted) {
      return;
    }
    if (validated.hostBinding!.legacy &&
        !const {'DIRECT', 'REJECT'}.contains(validated.ruleTarget)) {
      final profile = ref.read(currentProfileProvider);
      final name = validated.ruleTarget!;
      final bound = profile?.localGroups
          .where((g) => g.global && g.name == name)
          .firstOrNull;
      final target = ApplicationRouteTarget(
        name: name,
        kind: bound != null
            ? ApplicationTargetKind.globalGroup
            : ref.read(groupsProvider).any((g) => g.name == name)
            ? ApplicationTargetKind.group
            : ApplicationTargetKind.node,
        groupId: bound?.id,
      );
      validated = validated.copyWith(
        hostBinding: validated.hostBinding!.copyWith(
          targets: {...validated.hostBinding!.targets, _profileId!: target},
        ),
      );
    }
    final scope = _general;
    final settings = ref.read(applicationRoutingSettingsProvider).value!;
    final packages = scope ? <String?>[null] : widget.packages.cast<String?>();
    final rules = [
      for (final package in packages)
        validated.copyWith(
          id:
              applicationHostRule(
                settings,
                widget.host,
                package,
                _profileId,
                includeDisabled: true,
              )?.id ??
              (package == validated.hostBinding?.packageName && validated.id > 0
                  ? validated.id
                  : snowflake.id),
          hostBinding: validated.hostBinding!.copyWith(packageName: package),
        ),
    ];
    setState(() {
      _busy = true;
      _error = null;
      _drafts[scope] = rules.first;
    });
    try {
      await ref
          .read(applicationRoutingControllerProvider.notifier)
          .saveHostRules(rules, expectedProfileId: _profileId!);
      if (!mounted) return;
      final fresh = await database.readApplicationRouting();
      if (!mounted) return;
      final saved =
          applicationHostRule(
            fresh,
            widget.host,
            scope ? null : widget.packages.firstOrNull,
            _profileId,
            includeDisabled: true,
          ) ??
          rules.first;
      setState(() {
        _drafts[scope] = saved;
        _baselines[scope] = saved;
      });
      context.showNotifier(context.appLocalizations.appPolicySaved);
    } catch (error) {
      final settings = await database.readApplicationRouting();
      if (!mounted) return;
      final persisted = applicationHostRule(
        settings,
        widget.host,
        scope ? null : widget.packages.firstOrNull,
        _profileId,
        includeDisabled: true,
      );
      setState(() {
        if (persisted != null) _baselines[scope] = persisted;
        _error = userFacingErrorMessage(error, context.appLocalizations);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final l = context.appLocalizations;
    final scope = _general;
    if (!scope && !await confirmApplicationPackages(context, widget.packages) ||
        !mounted) {
      return;
    }
    final message =
        '${l.appHostDeleteConfirm(scope ? l.appHostAllScope : widget.appLabel, widget.host)}${_dirty ? '\n${l.appHostDiscard}' : ''}';
    if (await dialogs.showMessage(
              context: context,
              message: TextSpan(text: message),
            ) !=
            true ||
        !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = ref.read(applicationRoutingSettingsProvider).value!;
      final packages = scope
          ? <String?>[null]
          : widget.packages.cast<String?>();
      final ids = [
        for (final package in packages)
          if (applicationHostRule(
                settings,
                widget.host,
                package,
                _profileId,
                includeDisabled: true,
              )
              case final rule?)
            rule.id,
      ];
      await ref
          .read(applicationRoutingControllerProvider.notifier)
          .deleteHostRules(ids);
      if (!mounted) return;
      final next = await database.readApplicationRouting();
      if (!mounted) return;
      final other = applicationHostRule(
        next,
        widget.host,
        scope ? widget.packages.firstOrNull : null,
        _profileId,
        includeDisabled: true,
      );
      if (other == null || scope && widget.packages.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _baselines[scope] = _empty(scope);
        _drafts[scope] = _baselines[scope]!;
        _general = !scope;
        _baselines[_general] = other;
        _drafts[_general] ??= other;
      });
    } catch (error) {
      final next = await database.readApplicationRouting();
      if (!mounted) return;
      final persisted = applicationHostRule(
        next,
        widget.host,
        scope ? null : widget.packages.firstOrNull,
        _profileId,
        includeDisabled: true,
      );
      setState(() {
        if (persisted == null) {
          _baselines[scope] = _empty(scope);
          _drafts[scope] = _baselines[scope]!;
        }
        _error = persisted == null
            ? l.appHostDeletedPending
            : userFacingErrorMessage(error, l);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTarget(Rule rule, ValueChanged<Rule> update) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.id != _profileId) return;
    final fact = ref.read(configStateProvider).fact;
    final groups = fact.profileId == profile.id && fact.phase == 'ready'
        ? ref.read(groupsProvider)
        : <Group>[];
    final targets = <String, ApplicationRouteTarget>{};
    for (final group in groups) {
      final bound = profile.localGroups
          .where((g) => g.name == group.name && g.global)
          .firstOrNull;
      targets[group.name] = ApplicationRouteTarget(
        name: group.name,
        kind: bound == null
            ? ApplicationTargetKind.group
            : ApplicationTargetKind.globalGroup,
        groupId: bound?.id,
      );
    }
    for (final group
        in ref.read(globalLocalGroupsProvider).value ?? <LocalProxyGroup>[]) {
      if (group.enabled) {
        targets.putIfAbsent(
          group.name,
          () => ApplicationRouteTarget(
            name: group.name,
            kind: ApplicationTargetKind.globalGroup,
            groupId: group.id,
          ),
        );
      }
    }
    final nodes = localGroupNodes(groups);
    for (final node in nodes) {
      targets[node.name] = ApplicationRouteTarget(
        name: node.name,
        kind: ApplicationTargetKind.node,
      );
    }
    final l = context.appLocalizations;
    final picked = await BaseNavigator.push<String>(
      context,
      OverwriteSelectionSheet<String>(
        title: l.ruleTarget,
        bottomHeightFactor: null,
        sections: [
          OverwriteSelectionSection(
            label: l.basicStrategy,
            items: const ['DIRECT', 'REJECT'],
          ),
          OverwriteSelectionSection(
            label: l.ruleTarget,
            items: targets.values
                .where((t) => t.kind != ApplicationTargetKind.node)
                .map((t) => t.name)
                .toList(),
          ),
          OverwriteSelectionSection(
            label: l.proxies,
            items: nodes.map((n) => n.name).toList(),
          ),
        ],
        labelBuilder: (name) => name,
        selectedOf: (_) => rule.ruleTarget,
        onSelected: (name) => Navigator.of(context).pop(name),
      ),
    );
    if (!mounted || picked == null) return;
    update(
      rule.copyWith(
        ruleTarget: picked,
        hostBinding: rule.hostBinding!.copyWith(
          targets: {
            ...rule.hostBinding!.targets,
            if (targets[picked] != null) profile.id: targets[picked]!,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final settings = ref.watch(applicationRoutingSettingsProvider).value;
    if (settings != null) _initialize(settings);
    final draft = _drafts[_general];
    final existing = (_baselines[_general]?.id ?? -1) > 0;
    final mode = ref.watch(patchClashConfigProvider).mode;
    final targetState = draft == null ? null : hostRuleTargetState(ref, draft);
    return CommonPopScope(
      onPop: (_) => _leave(),
      child: CommonScaffold(
        title: l.appHostRuleTitle(widget.host),
        primaryAction: draft == null
            ? null
            : IconButtonData(
                glyph: AppGlyphs.save,
                tooltip: existing ? l.save : l.appHostCreate,
                onPressed: _busy || _profileId == null ? null : _save,
              ),
        menuItems: [
          if (existing)
            CommonPopupMenuItem(
              label: l.delete,
              glyph: AppGlyphs.delete,
              onPressed: _busy ? null : _delete,
            ),
        ],
        body: settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  context.contentTopPadding,
                  20,
                  20 + BottomInsetScope.of(context),
                ),
                children: [
                  Text(widget.appLabel, style: context.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    l.appHostCurrent(
                      hostPolicyLabel(
                        context,
                        ref,
                        widget.host,
                        widget.packages,
                      ),
                    ),
                    style: context.textTheme.bodySmall,
                  ),
                  if (mode == Mode.global)
                    Text(
                      l.appPolicyGlobalPaused,
                      style: context.textTheme.bodySmall,
                    ),
                  if (widget.packages.isEmpty)
                    Text(
                      l.appHostOnlyGeneric,
                      style: context.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l.appHostScope),
                        enabled: widget.packages.isNotEmpty,
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l.appHostAllScope),
                      ),
                    ],
                    selected: {_general},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                            _general = selection.single;
                            _error = null;
                          }),
                  ),
                  const SizedBox(height: 20),
                  if (!_general &&
                      settings.rules[widget.packages.firstOrNull]?.enabled !=
                          true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        l.appHostAppDisabled,
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  if (!existing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(l.appHostNotCreated),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: context.colorScheme.error),
                      ),
                    ),
                  if (draft != null)
                    IgnorePointer(
                      ignoring: _busy,
                      child: RuleEditorForm(
                        key: _editor,
                        rule: draft,
                        fixedCondition: true,
                        onChanged: (rule) =>
                            setState(() => _drafts[_general] = rule),
                        targetBuilder: (context, rule, update) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.ruleTarget),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                targetState?.target?.name ??
                                    rule.ruleTarget ??
                                    l.appPolicyChoose,
                              ),
                              if (targetState != null &&
                                  targetState.issue != null)
                                Text(
                                  applicationTargetIssueText(
                                    context,
                                    targetState.issue,
                                  ),
                                  style: TextStyle(
                                    color: context.colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                          trailing: const GlyphIcon(AppGlyphs.chevronForward),
                          onTap: () => _pickTarget(rule, update),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy || draft == null || _profileId == null
                        ? null
                        : _save,
                    child: Text(existing ? l.save : l.appHostCreate),
                  ),
                ],
              ),
      ),
    );
  }
}
