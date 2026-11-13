import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/widgets/activity_summary.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ApplicationTargetsView extends ConsumerStatefulWidget {
  const ApplicationTargetsView({
    super.key,
    required this.appKey,
    required this.label,
    this.packageName,
    this.identity = const ApplicationIdentity(),
  });

  final String appKey, label;
  final String? packageName;
  final ApplicationIdentity identity;

  @override
  ConsumerState<ApplicationTargetsView> createState() =>
      _ApplicationTargetsViewState();
}

class _ApplicationTargetsViewState
    extends ConsumerState<ApplicationTargetsView> {
  String _query = '';
  bool _onlyActive = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final activity = ref.watch(applicationActivityProvider);
    final catalogue = ref.watch(applicationCatalogueProvider);
    final packages = {
      for (final package in catalogue.asData?.value.packages ?? <Package>[])
        package.packageName: package,
    };
    final hosts = activity.hostsForApp(widget.appKey);
    final canFilter =
        activity.fresh &&
        hosts.every((item) => item.totals.activeCount != null);
    final search = SearchQuery(_query);
    final visible =
        [
          ...hosts.where((item) => item.totals.confirmedActiveCount > 0),
          ...hosts.where((item) => item.totals.confirmedActiveCount == 0),
        ].where((item) {
          if (_onlyActive &&
              canFilter &&
              item.totals.confirmedActiveCount == 0) {
            return false;
          }
          return search.matches([item.target]);
        }).toList();
    final label = packages[widget.packageName]?.label ?? widget.label;
    return CommonScaffold(
      titleWidget: Row(
        children: [
          if (widget.packageName case final String packageName)
            PackageIcon(
              packageName: packageName,
              size: 32,
              placeholder: const GlyphIcon(AppGlyphs.application, size: 32),
            )
          else
            const GlyphIcon(AppGlyphs.application, size: 32),
          const SizedBox(width: 12),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      menuItems: [
        CommonPopupMenuItem(
          label: l10n.activityOnlyActiveTargets,
          glyph: AppGlyphs.networkCheck,
          checked: _onlyActive,
          onPressed: canFilter || _onlyActive
              ? () => setState(() => _onlyActive = !_onlyActive)
              : null,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 8),
            child: SearchField(
              hintText: l10n.activitySearchTargets,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (activity.observing && activity.snapshotFailed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.activitySnapshotFailed)),
                  TextButton(
                    onPressed: () => ref
                        .read(applicationActivityProvider.notifier)
                        .refresh(),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          if (_onlyActive && !canFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(l10n.activityActiveFilterUnavailable),
            ),
          Expanded(
            child: ListView.builder(
              key: PageStorageKey('application-targets:${widget.appKey}'),
              padding: EdgeInsets.only(
                bottom: 16 + BottomInsetScope.of(context),
              ),
              findChildIndexCallback: (key) {
                if (key == const ValueKey('application-identity')) return 0;
                final index = visible.indexWhere(
                  (item) => ValueKey('target:${item.key}') == key,
                );
                return index < 0 ? null : index + 1;
              },
              itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _ApplicationIdentity(
                    key: const ValueKey('application-identity'),
                    identity: widget.identity,
                    packageName: widget.packageName,
                    packages: packages,
                  );
                }
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      search.isNotEmpty
                          ? l10n.activityNoTargetMatches
                          : _onlyActive && canFilter
                          ? l10n.activityNoActive
                          : l10n.activityNoObserved,
                    ),
                  );
                }
                final host = visible[index - 1];
                return _TargetActivityRow(
                  key: ValueKey('target:${host.key}'),
                  host: host,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationIdentity extends StatelessWidget {
  const _ApplicationIdentity({
    super.key,
    required this.identity,
    required this.packageName,
    required this.packages,
  });

  final ApplicationIdentity identity;
  final String? packageName;
  final Map<String, Package> packages;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final uid = identity.uid;
    if (identity.status == 'ambiguous') {
      return Card.filled(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: AppShape.xl,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: const PageStorageKey('shared-identity-details'),
          initiallyExpanded: true,
          shape: AppShape.xl,
          collapsedShape: AppShape.xl,
          trailing: const _ActivityExpansionIcon(),
          title: Text(
            uid == null ? l10n.activitySharedUid : l10n.activityUid(uid),
          ),
          subtitle: Text(l10n.activitySharedIdentityHelp),
          children: [
            for (final name in identity.packages)
              ListTile(
                title: Text(packages[name]?.label ?? name),
                subtitle: packages[name] == null ? null : Text(name),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Text(
        [
          ?packageName,
          if (uid != null) l10n.activityUid(uid),
          if (packageName == null) l10n.activityIdentityUncertain,
        ].join(' · '),
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TargetActivityRow extends StatelessWidget {
  const _TargetActivityRow({super.key, required this.host});

  final HostActivity host;

  String _rule(BuildContext context, TrackerInfo info) {
    if (info.rule.isNotEmpty) {
      return info.rulePayload.isEmpty
          ? info.rule
          : '${info.rule} · ${info.rulePayload}';
    }
    final config = info.observation?.configuration;
    return config?.status == 'known' &&
            (config?.mode == 'global' || config?.mode == 'direct')
        ? context.appLocalizations.activityRulesBypassed
        : context.appLocalizations.unknown;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final routes = {
      for (final connection in host.totals.connections)
        jsonEncode([_rule(context, connection.info), connection.info.chains]):
            connection.info,
    };
    final rules = routes.values.map((info) => _rule(context, info)).toSet();
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('target-details:${host.key}'),
        shape: AppShape.xl,
        collapsedShape: AppShape.xl,
        trailing: const _ActivityExpansionIcon(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          host.target.isEmpty ? l10n.activityUnknownTarget : host.target,
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActivityConnectionSummary(totals: host.totals),
            Text(
              routes.length == 1
                  ? '${_rule(context, routes.values.single)} · ${routes.values.single.chains.isEmpty ? l10n.unknown : routes.values.single.chains.join(' → ')}'
                  : l10n.activityRouteCounts(
                      rules.length,
                      host.totals.exitPaths.length,
                    ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ],
        ),
        children: [
          for (final info in routes.values)
            ListTile(
              title: Text(_rule(context, info)),
              subtitle: Text(
                info.chains.isEmpty ? l10n.unknown : info.chains.join(' → '),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityExpansionIcon extends StatelessWidget {
  const _ActivityExpansionIcon();

  @override
  Widget build(BuildContext context) {
    final controller = ExpansibleController.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => AnimatedRotation(
        turns: controller.isExpanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
      child: const GlyphIcon(AppGlyphs.chevronDown),
    );
  }
}
