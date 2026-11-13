import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/connection/tracker_info_item.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/widgets/connection_exit.dart';
import 'package:fl_clash/widgets/activity_summary.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ApplicationConnectionsView extends ConsumerStatefulWidget {
  const ApplicationConnectionsView({
    super.key,
    required this.appKey,
    required this.hostKey,
    required this.appLabel,
  });

  final String appKey, hostKey, appLabel;

  @override
  ConsumerState<ApplicationConnectionsView> createState() =>
      _ApplicationConnectionsViewState();
}

class _ApplicationConnectionsViewState
    extends ConsumerState<ApplicationConnectionsView> {
  bool _allApps = false, _onlyActive = false;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final activity = ref.watch(applicationActivityProvider);
    final records =
        activity.connections
            .where(
              (item) =>
                  item.hostKey == widget.hostKey &&
                  (_allApps || item.appKey == widget.appKey),
            )
            .toList()
          ..sort((a, b) {
            final time = b.info.start.compareTo(a.info.start);
            return time == 0 ? a.info.id.compareTo(b.info.id) : time;
          });
    final canFilter =
        activity.fresh && records.every((item) => item.active != null);
    final visible = records
        .where((item) => !_onlyActive || !canFilter || item.active == true)
        .toList();
    final catalogue = _allApps
        ? ref.watch(applicationCatalogueProvider).asData?.value
        : null;
    final names = {
      for (final app in catalogue?.packages ?? <Package>[])
        app.packageName: app.label,
    };
    final target = widget.hostKey.substring(widget.hostKey.indexOf(':') + 1);
    return CommonScaffold(
      title: target.isEmpty ? l.activityUnknownTarget : target,
      menuItems: [
        CommonPopupMenuItem(
          label: l.activityAllAppsForTarget,
          glyph: AppGlyphs.application,
          checked: _allApps,
          onPressed: () => setState(() => _allApps = !_allApps),
        ),
        CommonPopupMenuItem(
          label: l.activityOnlyActiveConnections,
          glyph: AppGlyphs.networkCheck,
          checked: _onlyActive,
          onPressed: canFilter || _onlyActive
              ? () => setState(() => _onlyActive = !_onlyActive)
              : null,
        ),
      ],
      body: ListView.builder(
        key: PageStorageKey(
          'host-connections:${widget.appKey}:${widget.hostKey}:$_allApps',
        ),
        padding: EdgeInsets.only(
          top: context.contentTopPadding,
          bottom: 16 + BottomInsetScope.of(context),
        ),
        findChildIndexCallback: (key) {
          if (key == const ValueKey('target-addresses')) return 0;
          final index = visible.indexWhere(
            (item) =>
                ValueKey(
                  'connection:${activity.runtimeEpoch}:${item.info.id}',
                ) ==
                key,
          );
          return index < 0 ? null : index + 1;
        },
        itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              key: const ValueKey('target-addresses'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Text(
                    _allApps ? l.activityAllApps : widget.appLabel,
                    style: context.textTheme.bodySmall,
                  ),
                ),
                _ObservedAddresses(records: records),
                if (activity.observing && activity.snapshotFailed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(child: Text(l.activitySnapshotFailed)),
                        TextButton(
                          onPressed: () => ref
                              .read(applicationActivityProvider.notifier)
                              .refresh(),
                          child: Text(l.retry),
                        ),
                      ],
                    ),
                  ),
                if (_onlyActive && !canFilter)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Text(l.activityConnectionsUnconfirmed),
                  ),
              ],
            );
          }
          if (visible.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _onlyActive && canFilter
                    ? l.activityNoActive
                    : l.activityNoObserved,
              ),
            );
          }
          final record = visible[index - 1];
          final identity = record.application;
          return _ConnectionRow(
            key: ValueKey(
              'connection:${activity.runtimeEpoch}:${record.info.id}',
            ),
            record: record,
            active: activity.fresh ? record.active : null,
            appLabel: _allApps
                ? names[identity.packageName] ??
                      identity.packageName ??
                      (identity.status == 'ambiguous'
                          ? l.activitySharedUid
                          : l.activityUnknownApp)
                : null,
          );
        },
      ),
    );
  }
}

Future<void> _copy(BuildContext context, String value) async {
  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      context.showNotifier(context.appLocalizations.copySuccess);
    }
  } catch (_) {
    if (context.mounted) {
      context.showNotifier(context.appLocalizations.clipboardWriteFailed);
    }
  }
}

String _endpoint(String ip, String port) {
  if (ip.isEmpty) return '';
  if (port.isEmpty) return ip;
  return '${ip.contains(':') ? '[$ip]' : ip}:$port';
}

class _ObservedAddresses extends StatefulWidget {
  const _ObservedAddresses({required this.records});
  final List<ActivityConnection> records;
  @override
  State<_ObservedAddresses> createState() => _ObservedAddressesState();
}

class _ObservedAddressesState extends State<_ObservedAddresses> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final addresses = <String, Set<String>>{};
    for (final item in widget.records) {
      final data = item.info.metadata;
      final address = _endpoint(data.destinationIP, data.destinationPort);
      if (address.isEmpty) continue;
      (addresses[address] ??= {}).addAll([
        if (data.network.isNotEmpty) data.network.toUpperCase(),
        ...data.destinationGeoIP,
        if (data.destinationIPASN.isNotEmpty) data.destinationIPASN,
      ]);
    }
    if (addresses.isEmpty) return const SizedBox.shrink();
    final entries = addresses.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final shown = _expanded ? entries : entries.take(3);
    final l = context.appLocalizations;
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      shape: AppShape.xl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.activityObservedAddresses,
              style: context.textTheme.labelLarge,
            ),
            for (final entry in shown)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entry.key),
                subtitle: entry.value.isEmpty
                    ? null
                    : Text(entry.value.join(' · ')),
                onTap: () => _copy(context, entry.key),
              ),
            if (entries.length > 3)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? l.activityFewerAddresses
                      : l.activityMoreAddresses(entries.length - 3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    super.key,
    required this.record,
    required this.active,
    this.appLabel,
  });
  final ActivityConnection record;
  final bool? active;
  final String? appLabel;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final info = record.info;
    final state = active == null
        ? l.activityPending
        : active!
        ? l.activityActive
        : l.activityConnectionEnded;
    final style = activityActiveStyle(context, active);
    final textStyles = RecordTextStyles.of(context);
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () => showExtend(
          context,
          builder: (_) => CommonScaffold(
            title: l.details(l.request),
            body: TrackerInfoDetailView(
              trackerInfo: info.copyWith(
                upload: record.upload,
                download: record.download,
              ),
            ),
          ),
        ),
        leading: ConnectionExitIcon(info: info, active: active),
        title: RecordHeader(
          trailing: Semantics(
            label:
                '${l.activityObservedUpload}: ${record.upload.traffic.show}, ${l.activityObservedDownload}: ${record.download.traffic.show}, $state',
            excludeSemantics: true,
            child: Text(
              '↑ ${record.upload.traffic.show}   ↓ ${record.download.traffic.show}',
              style: style,
            ),
          ),
          children: [
            Tooltip(
              message: '${l.creationTime}: ${info.start.showFull} · $state',
              child: DefaultTextStyle.merge(
                style: style,
                child: RecordTimestamp(info.start.showFull),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            if (appLabel != null) Text(appLabel!, style: textStyles.secondary),
            Text(
              info.chains.isEmpty
                  ? l.unknown
                  : info.chains.reversed.join(' → '),
              style: textStyles.primary,
            ),
            Text(activityRuleText(context, info), style: textStyles.secondary),
          ],
        ),
      ),
    );
  }
}
