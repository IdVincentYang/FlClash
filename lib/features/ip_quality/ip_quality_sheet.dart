import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'ip_quality_text.dart';
import 'labels.dart';

Future<void> showIpQualitySheet(BuildContext context, {required String ip}) {
  if (isSheetPage(context)) {
    return Navigator.of(
      context,
    ).push(PagedSheetRoute(builder: (_) => _IpQualitySheet(ip: ip)));
  }
  return showSheet<void>(
    context: context,
    builder: (_) => _IpQualitySheet(ip: ip),
  );
}

class _IpQualitySheet extends ConsumerStatefulWidget {
  const _IpQualitySheet({required this.ip});
  final String ip;
  @override
  ConsumerState<_IpQualitySheet> createState() => _IpQualitySheetState();
}

class _IpQualitySheetState extends ConsumerState<_IpQualitySheet> {
  late IpQualityProbe _probe;
  late ProviderSubscription<IpQualityProbe> _observation;
  @override
  void initState() {
    super.initState();
    _observation = ref.listenManual(ipQualityProbeProvider.notifier, (
      previous,
      next,
    ) {
      previous?.unwatch(widget.ip, automatic: false);
      _probe = next;
      _probe.watch(widget.ip, automatic: false);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _observation.close();
    _probe.unwatch(widget.ip, automatic: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final ip = widget.ip;
    final entry = ref.watch(
      ipQualityProbeProvider.select((s) => s.entryOf(ip)),
    );
    final quality = entry.value;
    final proxied = ref.watch(routeTrackerProvider.select((s) => s.proxied));
    Widget text(String? value) => Text(value ?? l.unknown);
    String flag(bool? value) => value == null
        ? l.unknown
        : value
        ? l.yes
        : l.no;
    final page = CommonScaffold(
      title: l.outboundIp,
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.ipClassificationDisclosure),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: entry.isLoading ? null : () => _probe.refresh([ip]),
            child: Text(l.ipClassificationStart),
          ),
          if (entry.isLoading)
            Text(
              entry.phase == ProbePhase.queued ? l.ipLookupWaiting : l.loading,
            ),
          if (entry.phase == ProbePhase.failed)
            Text(ipLookupReason(context, entry.reason)),
          if (entry.phase == ProbePhase.empty) Text(l.ipLookupNotChecked),
          if (entry.expired) Text(l.ipLookupStale),
          if (quality?.warning == true) Text(l.ipLookupSourceWarning),
          generateSectionV3(
            title: l.basicInfo,
            items: [
              DetailRow(
                title: l.ipAddress,
                copyText: ip,
                value: IpQualityText(ip: ip),
              ),
              DetailRow(
                title: l.requestMode,
                value: Text(proxied ? l.ipLookupRoutes : l.direct),
              ),
              DetailRow(
                title: l.ipQualitySource,
                value: const Text('proxycheck.io'),
              ),
              DetailRow(
                title: l.ipLookupCheckedAt,
                value: text(quality?.checkedAt?.toLocal().toString()),
              ),
              DetailRow(
                title: l.ipType,
                value: text(quality?.type?.label(context)),
              ),
            ],
          ),
          generateSectionV3(
            title: l.ipFlags,
            items: [
              DetailRow(
                title: l.ipFlagProxy,
                value: Text(flag(quality?.isProxy)),
              ),
              DetailRow(title: l.ipFlagVpn, value: Text(flag(quality?.isVpn))),
              DetailRow(title: l.ipFlagTor, value: Text(flag(quality?.isTor))),
              DetailRow(
                title: l.ipFlagCompromised,
                value: Text(flag(quality?.isCompromised)),
              ),
              DetailRow(
                title: l.ipFlagHosting,
                value: Text(flag(quality?.isHosting)),
              ),
              DetailRow(
                title: l.ipFlagAnonymous,
                value: Text(flag(quality?.isAnonymous)),
              ),
              DetailRow(
                title: l.ipFlagScraper,
                value: Text(flag(quality?.isScraper)),
              ),
            ],
          ),
          generateSectionV3(
            title: l.network,
            items: [
              DetailRow(
                title: l.ipOrganization,
                copyText: quality?.organization,
                value: text(quality?.organization),
              ),
              DetailRow(
                title: l.ipAsn,
                value: text(quality?.asn == null ? null : 'AS${quality!.asn}'),
              ),
            ],
          ),
          ConfigToggleItem(
            selector: appSettingProvider.select((s) => s.hideIp),
            title: (l) => l.hideIp,
            subtitle: (l) => l.ipLookupDisplayOnly,
            onChanged: (ref, value) => ref
                .read(appSettingProvider.notifier)
                .update((s) => s.copyWith(hideIp: value)),
          ),
        ],
      ),
    );
    if (!isSheetPage(context)) return page;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: ref.sheetHeight(context, shortSheetMaxHeight),
      ),
      child: page,
    );
  }
}
