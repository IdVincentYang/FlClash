import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/connection_countries.dart';
import 'package:fl_clash/widgets/activity_summary.dart';
import 'package:fl_clash/widgets/widgets.dart';

import 'application_connections.dart';
import 'package:flutter/services.dart';
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
    final latestConnections = {
      for (final host in visible) host.key: _latestConnection(host).info,
    };
    final hasDirect = latestConnections.values.any(
      (info) => info.chains.isNotEmpty && info.chains.first == 'DIRECT',
    );
    final localIp = hasDirect ? ref.watch(observedLocalPublicIpProvider) : null;
    final ips = {
      for (final info in latestConnections.values)
        ?connectionCountryIp(info, localIp),
    }.toList()..sort();
    final countries = ips.isEmpty
        ? const <String, String>{}
        : ref
                  .watch(connectionCountriesProvider(jsonEncode(ips)))
                  .asData
                  ?.value ??
              const <String, String>{};
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
                  latestConnection: latestConnections[host.key]!,
                  countries: countries,
                  localPublicIp: localIp,
                  onPressed: () => BaseNavigator.push(
                    context,
                    ApplicationConnectionsView(
                      appKey: widget.appKey,
                      hostKey: host.key,
                      appLabel: label,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

ActivityConnection _latestConnection(HostActivity host) =>
    host.totals.connections.reduce((latest, candidate) {
      final time = candidate.info.start.compareTo(latest.info.start);
      return time > 0 ||
              time == 0 && candidate.info.id.compareTo(latest.info.id) < 0
          ? candidate
          : latest;
    });

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

  Future<void> _copy(BuildContext context, String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!context.mounted) return;
      context.showNotifier(context.appLocalizations.copySuccess);
    } catch (_) {
      if (!context.mounted) return;
      context.showNotifier(context.appLocalizations.clipboardWriteFailed);
    }
  }

  Widget _value(BuildContext context, String value, {String? label}) => Tooltip(
    message: '${context.appLocalizations.copy} ${label ?? value}',
    child: TextButton(
      onPressed: () => _copy(context, value),
      style: TextButton.styleFrom(textStyle: context.textTheme.bodySmall),
      child: Text(label ?? value),
    ),
  );

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
          title: uid == null
              ? Text(l10n.activitySharedUid)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: _value(context, '$uid', label: l10n.activityUid(uid)),
                ),
          subtitle: Text(l10n.activitySharedIdentityHelp),
          children: [
            for (final name in identity.packages)
              ListTile(
                onTap: () => _copy(context, name),
                title: Text(packages[name]?.label ?? name),
                subtitle: packages[name] == null ? null : Text(name),
                trailing: const GlyphIcon(AppGlyphs.copy),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (packageName case final String name) _value(context, name),
          if (uid != null)
            _value(context, '$uid', label: l10n.activityUid(uid)),
          if (packageName == null)
            Text(
              l10n.activityIdentityUncertain,
              style: context.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _TargetActivityRow extends StatelessWidget {
  const _TargetActivityRow({
    required super.key,
    required this.host,
    required this.latestConnection,
    required this.countries,
    this.localPublicIp,
    required this.onPressed,
  });

  final HostActivity host;
  final TrackerInfo latestConnection;
  final Map<String, String> countries;
  final String? localPublicIp;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final rules = host.totals.rules;
    final exits = host.totals.exitPaths;
    final single = host.totals.connections.first.info;
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onPressed,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: ConnectionCountryIcon(
          info: latestConnection,
          countries: countries,
          localPublicIp: localPublicIp,
        ),
        title: Text(
          host.target.isEmpty ? l10n.activityUnknownTarget : host.target,
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActivityConnectionSummary(totals: host.totals),
            Text(
              rules.length == 1 && exits.length == 1
                  ? '${activityRuleText(context, single)} · ${single.chains.isEmpty ? l10n.unknown : single.chains.join(' → ')}'
                  : l10n.activityRouteCounts(rules.length, exits.length),
              style: context.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: const GlyphIcon(AppGlyphs.chevronForward),
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
