import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/widgets/application_policy_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ApplicationPolicyView extends ConsumerStatefulWidget {
  const ApplicationPolicyView({
    super.key,
    required this.packages,
    required this.label,
    this.enableOnSave = false,
    this.sharedTarget = false,
  });
  final List<String> packages;
  final String label;
  final bool enableOnSave, sharedTarget;

  @override
  ConsumerState<ApplicationPolicyView> createState() =>
      _ApplicationPolicyViewState();
}

class _ApplicationPolicyViewState extends ConsumerState<ApplicationPolicyView> {
  String _query = '';
  int _filter = 0;
  String? _members;
  bool _busy = false;
  String? _error;

  Future<void> _save(
    ApplicationRouteAction action, {
    ApplicationRouteTarget? target,
    bool shared = false,
    int? expectedProfileId,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(
        applicationRoutingControllerProvider.notifier,
      );
      if (widget.sharedTarget) {
        if (target == null) return;
        final count =
            ref
                .read(applicationRoutingSettingsProvider)
                .value
                ?.rules
                .values
                .where(
                  (rule) =>
                      rule.enabled &&
                      rule.useSharedTarget &&
                      rule.action == ApplicationRouteAction.proxy,
                )
                .length ??
            0;
        if (count > 0 &&
            await dialogs.showMessage(
                  context: context,
                  message: TextSpan(
                    text: context.appLocalizations.appPolicySharedChange(count),
                  ),
                ) !=
                true) {
          return;
        }
        if (!mounted) return;
        await controller.setSharedTarget(
          target,
          expectedProfileId: expectedProfileId,
        );
      } else {
        await controller.setPolicy(
          widget.packages,
          action,
          target: target,
          shared: shared,
          enable: widget.enableOnSave ? true : null,
          expectedProfileId: expectedProfileId,
        );
      }
      if (mounted) {
        context.showNotifier(
          ref.read(patchClashConfigProvider).mode == Mode.global
              ? context.appLocalizations.appPolicyGlobalSaved
              : context.appLocalizations.appPolicySaved,
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = userFacingErrorMessage(error, context.appLocalizations),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shared() async {
    final settings = ref.read(applicationRoutingSettingsProvider).value;
    final rule = ApplicationRouteRule(
      packageName: (widget.packages.firstOrNull ?? ''),
    );
    if (settings == null) return;
    if (applicationTargetFor(
          settings,
          rule,
          ref.read(currentProfileIdProvider),
        ) ==
        null) {
      if (await BaseNavigator.push<bool>(
                context,
                ApplicationPolicyView(
                  packages: widget.packages,
                  label: widget.label,
                  sharedTarget: true,
                ),
              ) !=
              true ||
          !mounted) {
        return;
      }
    }
    await _save(ApplicationRouteAction.proxy, shared: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final settings =
        ref.watch(applicationRoutingSettingsProvider).value ??
        const ApplicationRoutingSettings();
    final profile = ref.watch(currentProfileProvider);
    final groups = ref
        .watch(groupsProvider)
        .where((group) => group.name != 'GLOBAL')
        .toList();
    final definitions =
        ref.watch(globalLocalGroupsProvider).value ?? const <LocalProxyGroup>[];
    final rule =
        settings.rules[(widget.packages.firstOrNull ?? '')] ??
        ApplicationRouteRule(packageName: (widget.packages.firstOrNull ?? ''));
    final selected = applicationTargetFor(
      settings,
      widget.sharedTarget ? rule.copyWith(useSharedTarget: true) : rule,
      profile?.id,
    );
    final fact = ref.watch(configStateProvider).fact;
    final ready =
        profile != null &&
        fact.profileId == profile.id &&
        fact.phase == 'ready';
    final query = SearchQuery(_query);
    final groupEntries = groups
        .where(
          (group) =>
              _members == null &&
              _filter != 2 &&
              query.matches([group.name, group.type.name]),
        )
        .toList();
    final memberGroup = groups
        .where((group) => group.name == _members)
        .firstOrNull;
    final nodes = localGroupNodes(memberGroup == null ? groups : [memberGroup])
        .where((node) => _filter != 1 && query.matches([node.name, node.type]))
        .toList();
    final choices =
        <
          ({
            String name,
            String type,
            ApplicationRouteTarget target,
            ApplicationTargetState status,
            Group? group,
          })
        >[];
    for (final group in groupEntries) {
      final binding = profile?.localGroups
          .where((value) => value.name == group.name)
          .firstOrNull;
      final target = ApplicationRouteTarget(
        name: group.name,
        kind: binding?.global == true
            ? ApplicationTargetKind.globalGroup
            : ApplicationTargetKind.group,
        groupId: binding?.global == true ? binding?.id : null,
      );
      choices.add((
        name: group.name,
        type: group.type.name,
        target: target,
        status: resolveApplicationTarget(
          target: target,
          profile: profile,
          groups: groups,
          definitions: definitions,
          ready: ready,
        ),
        group: group,
      ));
    }
    for (final group in definitions) {
      if (_members != null ||
          _filter == 2 ||
          !query.matches([group.name, group.type.name]) ||
          choices.any((entry) => entry.target.groupId == group.id)) {
        continue;
      }
      final target = ApplicationRouteTarget(
        name: group.name,
        kind: ApplicationTargetKind.globalGroup,
        groupId: group.id,
      );
      final count = group.regex.isEmpty
          ? localGroupNodes(
              groups,
            ).where((node) => group.nodes.contains(node.name)).length
          : null;
      choices.add((
        name: group.name,
        type: group.type.name,
        target: target,
        status: ApplicationTargetState(
          target: target,
          issue: !group.enabled
              ? ApplicationTargetIssue.disabled
              : count == 0
              ? ApplicationTargetIssue.empty
              : !ready
              ? ApplicationTargetIssue.preparing
              : null,
        ),
        group: null,
      ));
    }
    for (final node in nodes) {
      final target = ApplicationRouteTarget(
        name: node.name,
        kind: ApplicationTargetKind.node,
      );
      choices.add((
        name: node.name,
        type: node.type,
        target: target,
        status: ApplicationTargetState(
          target: target,
          issue: ready ? null : ApplicationTargetIssue.preparing,
        ),
        group: null,
      ));
    }
    final savedError = widget.packages
        .map(
          (package) =>
              ref.watch(applicationRoutingControllerProvider).errors[package],
        )
        .whereType<String>()
        .firstOrNull;
    final targetStatus = resolveApplicationTarget(
      target: selected,
      profile: profile,
      groups: groups,
      definitions: definitions,
      ready: ready,
    );
    final error =
        _error ??
        (selected?.kind == ApplicationTargetKind.globalGroup
            ? ref.watch(globalGroupsActionProvider)
            : null) ??
        savedError ??
        (rule.enabled &&
                rule.action == ApplicationRouteAction.proxy &&
                targetStatus.issue != null &&
                targetStatus.issue != ApplicationTargetIssue.preparing
            ? applicationTargetIssueText(context, targetStatus.issue)
            : null);
    return CommonScaffold(
      title: widget.sharedTarget
          ? l.appPolicySharedTarget
          : l.appPolicyTitle(widget.label),
      isLoading: _busy,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              context.contentTopPadding + 8,
              20,
              0,
            ),
            child: Text(
              '${profile?.label ?? l.unknown} · ${ref.watch(patchClashConfigProvider).mode.label}',
              style: context.textTheme.bodySmall,
            ),
          ),
          const ApplicationPolicyStatus(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hintText: l.appPolicySearch,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error,
                style: TextStyle(color: context.colorScheme.error),
              ),
            ),
          if (_members != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _members = null;
                _filter = 0;
              }),
              icon: const GlyphIcon(AppGlyphs.arrowBack),
              label: Text(_members!),
            )
          else ...[
            if (!widget.sharedTarget)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _PolicyChoice(
                        name: 'DIRECT',
                        type: l.appPolicyDirect,
                        selected: rule.action == ApplicationRouteAction.direct,
                        onTap: _busy
                            ? null
                            : () => _save(ApplicationRouteAction.direct),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PolicyChoice(
                        name: 'REJECT',
                        type: l.appPolicyReject,
                        selected: rule.action == ApplicationRouteAction.reject,
                        onTap: _busy
                            ? null
                            : () => _save(ApplicationRouteAction.reject),
                      ),
                    ),
                  ],
                ),
              ),
            if (!widget.sharedTarget)
              ListTile(
                title: Text(l.appPolicySharedTarget),
                subtitle: Text(
                  applicationTargetFor(
                        settings,
                        rule.copyWith(useSharedTarget: true),
                        profile?.id,
                      )?.name ??
                      l.appPolicyChoose,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected:
                    rule.action == ApplicationRouteAction.proxy &&
                    rule.useSharedTarget,
                onTap: _busy ? null : _shared,
                trailing: IconButton(
                  tooltip: l.edit,
                  onPressed: _busy
                      ? null
                      : () => BaseNavigator.push(
                          context,
                          ApplicationPolicyView(
                            packages: widget.packages,
                            label: widget.label,
                            sharedTarget: true,
                          ),
                        ),
                  icon: const GlyphIcon(AppGlyphs.edit),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (index, text) in [
                    l.appPolicyAll,
                    l.appPolicyGroups,
                    l.appPolicyNodes,
                  ].indexed) ...[
                    ChoiceChip(
                      label: Text(text),
                      selected: _filter == index,
                      onSelected: (_) => setState(() => _filter = index),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
          Expanded(
            child: choices.isEmpty
                ? Center(
                    child: Text(
                      ready ? l.activityNoMatches : l.appPolicyPreparing,
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      4,
                      18,
                      16 + BottomInsetScope.of(context),
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      mainAxisExtent:
                          88 + MediaQuery.textScalerOf(context).scale(28),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: choices.length,
                    itemBuilder: (context, index) {
                      final choice = choices[index];
                      return _PolicyChoice(
                        name: choice.name,
                        type: choice.status.available
                            ? choice.type
                            : applicationTargetIssueText(
                                context,
                                choice.status.issue,
                              ),
                        selected:
                            rule.action == ApplicationRouteAction.proxy &&
                            (widget.sharedTarget || !rule.useSharedTarget) &&
                            (choice.target.kind ==
                                    ApplicationTargetKind.globalGroup
                                ? choice.target.groupId == selected?.groupId
                                : choice.target == selected),
                        onTap: _busy || !choice.status.available
                            ? null
                            : () => _save(
                                ApplicationRouteAction.proxy,
                                target: choice.target,
                                expectedProfileId: profile?.id,
                              ),
                        members: choice.group == null
                            ? null
                            : () => setState(() {
                                _members = choice.name;
                                _filter = 2;
                              }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PolicyChoice extends StatelessWidget {
  const _PolicyChoice({
    required this.name,
    required this.type,
    required this.selected,
    this.onTap,
    this.members,
  });
  final String name, type;
  final bool selected;
  final VoidCallback? onTap, members;
  @override
  Widget build(BuildContext context) => CommonCard(
    isSelected: selected,
    radius: AppCorner.lg,
    onPressed: onTap,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmojiText(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (members != null)
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    tooltip: context.appLocalizations.appPolicyMembers,
                    onPressed: members,
                    icon: const GlyphIcon(AppGlyphs.layers, size: 18),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
