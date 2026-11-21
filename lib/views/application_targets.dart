import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/connection_exit.dart';
import 'package:fl_clash/widgets/activity_summary.dart';
import 'package:fl_clash/widgets/widgets.dart';

import 'application_connections.dart';
import 'application_host_rule.dart';
import 'package:fl_clash/widgets/host_rule.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/application_policy_status.dart';
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
  bool _captureBusy = false;
  String? _captureError;

  List<String> get _applicationPackages {
    if (widget.identity.status == 'ambiguous') return widget.identity.packages;
    final name = widget.packageName;
    if (name == null) return const [];
    final package = ref
        .read(applicationCatalogueProvider)
        .value
        ?.packages
        .where((value) => value.packageName == name)
        .firstOrNull;
    return package?.sharedPackages.isNotEmpty == true
        ? package!.sharedPackages
        : [name];
  }

  Future<void> _capture(bool enabled) async {
    if (!await confirmApplicationPackages(context, _applicationPackages) ||
        !mounted) {
      return;
    }
    setState(() {
      _captureBusy = true;
      _captureError = null;
    });
    try {
      await ref
          .read(applicationInputActionProvider.notifier)
          .updateVpn(
            (previous) => previous.copyWith(
              accessControlProps: setApplicationCapture(
                previous.accessControlProps,
                _applicationPackages,
                enabled,
              ),
            ),
          );
      if (mounted) {
        context.showNotifier(context.appLocalizations.appPolicyCaptureSaved);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _captureError = userFacingErrorMessage(
            error,
            context.appLocalizations,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _captureBusy = false);
    }
  }

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
    num upload = 0, download = 0;
    for (final host in hosts) {
      if (host.totals.retainedTraffic case final traffic?) {
        upload += traffic.up;
        download += traffic.down;
      }
    }
    final retainedTraffic = Traffic(up: upload, down: download);
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
    final label = packages[widget.packageName]?.label ?? widget.label;
    final capture = ref.watch(vpnSettingProvider).accessControlProps;
    final included = _applicationPackages.every(
      (name) => applicationCaptured(capture, name),
    );
    final capturePending =
        ref.watch(runControlProvider) &&
        ref.watch(nativeRequestStateProvider)['captureFingerprint'] !=
            applicationCaptureFingerprint(capture);
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
        if (_applicationPackages.isNotEmpty &&
            !_applicationPackages.contains(globalState.packageInfo.packageName))
          CommonPopupMenuItem(
            label: l10n.appPolicyCapture,
            glyph: AppGlyphs.vpn,
            checked: included,
            onPressed: _captureBusy ? null : () => _capture(!included),
          ),
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
          if (_captureBusy) const LinearProgressIndicator(),
          if (_captureError != null || capturePending)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                _captureError ?? l10n.appPolicyCapturePending,
                style: TextStyle(
                  color: _captureError != null
                      ? context.colorScheme.error
                      : context.colorScheme.tertiary,
                ),
              ),
            ),
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
                    retainedTraffic: retainedTraffic,
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
                  packages: _applicationPackages,
                  onRulePressed: () => BaseNavigator.push(
                    context,
                    ApplicationHostRuleView(
                      host: host.target,
                      packages: _applicationPackages,
                      appLabel: label,
                    ),
                  ),
                  active: activity.fresh
                      ? host.totals.confirmedActiveCount > 0
                      : null,
                  onPressed: () => BaseNavigator.push(
                    context,
                    ApplicationConnectionsView(
                      appKey: widget.appKey,
                      hostKey: host.key,
                      onOpenApplication: () {
                        final route = ModalRoute.of(context);
                        Navigator.of(
                          context,
                        ).popUntil((candidate) => candidate == route);
                      },
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

ActivityConnection _latestConnection(HostActivity host) {
  final active = host.totals.connections
      .where((item) => host.totals.fresh && item.active == true)
      .toList();
  final candidates = active.isNotEmpty ? active : host.totals.connections;
  return candidates.reduce((latest, candidate) {
    final time = candidate.info.start.compareTo(latest.info.start);
    return time > 0 ||
            time == 0 && candidate.info.id.compareTo(latest.info.id) < 0
        ? candidate
        : latest;
  });
}

class _ApplicationIdentity extends StatelessWidget {
  const _ApplicationIdentity({
    super.key,
    required this.identity,
    required this.packageName,
    required this.packages,
    required this.retainedTraffic,
  });

  final ApplicationIdentity identity;
  final String? packageName;
  final Map<String, Package> packages;
  final Traffic? retainedTraffic;

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
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              if (uid == null)
                Text(l10n.activitySharedUid)
              else
                _value(context, '$uid', label: l10n.activityUid(uid)),
              if (retainedTraffic case final traffic?)
                ActivityTrafficSummary(traffic: traffic, compact: true),
            ],
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
        spacing: 8,
        runSpacing: 4,
        children: [
          if (packageName case final String name) _value(context, name),
          if (uid != null)
            _value(context, '$uid', label: l10n.activityUid(uid)),
          if (retainedTraffic case final traffic?)
            ActivityTrafficSummary(traffic: traffic, compact: true),
          if (packageName == null)
            Text(
              identity.status == 'notFound'
                  ? l10n.activityUidNoPackage
                  : l10n.activityIdentityUncertain,
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
    required this.active,
    required this.onPressed,
    required this.onRulePressed,
    required this.packages,
  });

  static const _iconWidth = 36.0;
  static const _actionsWidth = 72.0;

  final HostActivity host;
  final VoidCallback onRulePressed;
  final List<String> packages;
  final TrackerInfo latestConnection;
  final bool? active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final exits = host.totals.exitPaths;
    final chain = latestConnection.chains.isEmpty
        ? l10n.unknown
        : latestConnection.chains.join(' → ');
    final route = exits.length > 1
        ? '$chain · ${l10n.activityOtherExitPaths(exits.length - 1)}'
        : chain;
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: _iconWidth,
                child: ConnectionExitIcon(
                  info: latestConnection,
                  active: active,
                  size: _iconWidth,
                  emojiSize: 28,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.target.isEmpty
                          ? l10n.activityUnknownTarget
                          : host.target,
                      style: context.textTheme.titleMedium,
                    ),
                    ActivityConnectionSummary(totals: host.totals),
                    Text(route, style: context.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: _actionsWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (host.totals.retainedTraffic case final traffic?)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: ActivityTrafficSummary(
                          traffic: traffic,
                          compact: true,
                          small: true,
                        ),
                      ),
                    HostRuleButton(
                      host: host.target,
                      packages: packages,
                      onPressed: onRulePressed,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
