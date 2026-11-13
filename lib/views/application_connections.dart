import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/connection_countries.dart';
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
    final hasDirect = records.any(
      (item) =>
          item.info.chains.isNotEmpty && item.info.chains.first == 'DIRECT',
    );
    final localIp = hasDirect ? ref.watch(observedLocalPublicIpProvider) : null;
    final ips = {
      for (final item in records) ?connectionProxyServerIp(item.info),
      ?localIp,
    }.toList()..sort();
    final countries = ips.isEmpty
        ? const <String, String>{}
        : ref
                  .watch(connectionCountriesProvider(jsonEncode(ips)))
                  .asData
                  ?.value ??
              const <String, String>{};
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
          final serverIp = connectionProxyServerIp(record.info);
          final direct =
              record.info.chains.isNotEmpty &&
              record.info.chains.first == 'DIRECT';
          final countryIp = serverIp ?? (direct ? localIp : null);
          final country = countries[countryIp];
          final identity = record.application;
          return _ConnectionRow(
            key: ValueKey(
              'connection:${activity.runtimeEpoch}:${record.info.id}',
            ),
            storageKey: '${activity.runtimeEpoch}:${record.info.id}',
            record: record,
            active: activity.fresh ? record.active : null,
            appLabel: _allApps
                ? names[identity.packageName] ??
                      identity.packageName ??
                      (identity.status == 'ambiguous'
                          ? l.activitySharedUid
                          : l.activityUnknownApp)
                : null,
            country: country,
            countryIp: countryIp,
            serverIp: serverIp,
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
    required this.storageKey,
    required this.record,
    required this.active,
    this.appLabel,
    this.country,
    this.countryIp,
    this.serverIp,
  });
  final String storageKey;
  final ActivityConnection record;
  final bool? active;
  final String? appLabel, country, countryIp, serverIp;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final info = record.info;
    final shortId = info.id.length > 8 ? info.id.substring(0, 8) : info.id;
    final state = active == null
        ? l.activityPending
        : active!
        ? l.activityActive
        : l.activityConnectionEnded;
    final style = activityActiveStyle(context, active);
    final countryLabel = country == null
        ? null
        : serverIp == null
        ? l.activityLocalPublicCountry(countryIp!, country!)
        : l.activityProxyServerCountry(countryIp!, country!);
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('connection-details:$storageKey'),
        shape: AppShape.xl,
        collapsedShape: AppShape.xl,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: SizedBox(
          width: 28,
          child: country == null
              ? null
              : Tooltip(
                  message: countryLabel!,
                  child: Text(
                    country!.countryFlagEmoji,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 24,
                      fontFamily: 'Apple Color Emoji',
                      fontFamilyFallback: ['Noto Color Emoji'],
                    ),
                  ),
                ),
        ),
        trailing: const GlyphIcon(AppGlyphs.chevronDown),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final id = Tooltip(
              message: '${l.activityConnectionId(info.id)} · $state',
              child: TextButton(
                onPressed: () => _copy(context, info.id),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  alignment: Alignment.centerLeft,
                  textStyle: context.textTheme.bodyMedium,
                ),
                child: Text('#$shortId', style: style),
              ),
            );
            final traffic = Semantics(
              label:
                  '${l.activityObservedUpload}: ${record.upload.traffic.show}, ${l.activityObservedDownload}: ${record.download.traffic.show}, $state',
              excludeSemantics: true,
              child: Text(
                '↑ ${record.upload.traffic.show}   ↓ ${record.download.traffic.show}',
                style: context.textTheme.bodySmall?.merge(style),
              ),
            );
            if (constraints.maxWidth < 230 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [id, traffic],
              );
            }
            return Row(
              children: [
                id,
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: traffic,
                  ),
                ),
              ],
            );
          },
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (appLabel != null)
              Text(appLabel!, style: context.textTheme.labelSmall),
            Text(
              info.chains.isEmpty
                  ? l.unknown
                  : info.chains.reversed.join(' → '),
            ),
            Text(
              activityRuleText(context, info),
              style: context.textTheme.bodySmall,
            ),
          ],
        ),
        children: [
          _ConnectionDetails(
            record: record,
            state: state,
            countryLabel: countryLabel,
            serverIp: serverIp,
          ),
        ],
      ),
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({
    required this.record,
    required this.state,
    required this.countryLabel,
    required this.serverIp,
  });
  final ActivityConnection record;
  final String state;
  final String? countryLabel, serverIp;
  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final info = record.info, metadata = info.metadata;
    final provenance = info.provenance;
    final config = info.observation?.configuration;
    final entries = <(String, String)>[
      (l.activityConnectionIdLabel, info.id),
      (l.activityConnectionState, state),
      (l.creationTime, info.start.toLocal().showFull),
      (l.activityLastLabel, record.activityAt.toLocal().showFull),
      (l.networkType, metadata.network.toUpperCase()),
      (l.source, _endpoint(metadata.sourceIP, metadata.sourcePort)),
      (
        l.destination,
        _endpoint(metadata.destinationIP, metadata.destinationPort),
      ),
      (l.activityProxyServerAddress, serverIp ?? ''),
      (l.country, countryLabel ?? ''),
      (l.activityObservedUpload, record.upload.traffic.show),
      (l.activityObservedDownload, record.download.traffic.show),
      if (provenance?['known'] == true) ...[
        (
          l.sourceRuleOrigin,
          '${provenance?['label'] ?? provenance?['origin'] ?? l.unknown}',
        ),
        (
          l.sourceAppliedRevision,
          '${provenance?['appliedRevision'] ?? l.unknown}',
        ),
        (
          l.ruleSet,
          (provenance?['ruleSets'] as List? ?? const [])
              .whereType<Map>()
              .map((set) => '${set['name']} @ ${set['revision']}')
              .join(', '),
        ),
      ],
      if (config?.status == 'known') (l.activityConfiguration, config!.inputId),
      (l.dnsMode, metadata.dnsMode?.name ?? ''),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          for (final (label, value) in entries)
            if (value.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(label, style: context.textTheme.labelMedium),
                subtitle: Text(value),
                onTap: () => _copy(context, value),
              ),
        ],
      ),
    );
  }
}
