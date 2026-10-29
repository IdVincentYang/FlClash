import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/features/ip_quality/ip_quality_text.dart';
import 'package:fl_clash/features/ip_quality/labels.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/views/dashboard/widget_metrics.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class NetworkDetection extends ConsumerStatefulWidget {
  const NetworkDetection({super.key, this.preview = false});
  final bool preview;
  @override
  ConsumerState<NetworkDetection> createState() => _NetworkDetectionState();
}

class _NetworkDetectionState extends ConsumerState<NetworkDetection> {
  OutboundIpProbe? _probe;
  ProviderSubscription<OutboundIpProbe>? _observation;

  void _observe() {
    if (widget.preview) return;
    _observation = ref.listenManual(outboundIpProbeProvider.notifier, (
      previous,
      next,
    ) {
      previous?.unwatch(routedOutbound);
      _probe = next;
      next.watch(routedOutbound);
    }, fireImmediately: true);
  }

  void _release() {
    _observation?.close();
    _observation = null;
    _probe?.unwatch(routedOutbound);
    _probe = null;
  }

  @override
  void initState() {
    super.initState();
    _observe();
  }

  @override
  void didUpdateWidget(covariant NetworkDetection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview == widget.preview) return;
    _release();
    _observe();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    if (widget.preview) {
      return SizedBox(
        height: DashboardWidgetMetrics.heightOf(context, 1),
        child: CommonCard(child: Center(child: Text(l.outboundIp))),
      );
    }
    final entry = ref.watch(
      outboundIpProbeProvider.select((s) => s.entryOf(routedOutbound)),
    );
    final proxied = ref.watch(routeTrackerProvider.select((s) => s.proxied));
    final info = entry.value;
    return SizedBox(
      height: DashboardWidgetMetrics.heightOf(context, 1),
      child: CommonCard(
        radius: DashboardWidgetMetrics.radiusOf(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        info == null
                            ? l.outboundIp
                            : '${info.countryCode.countryFlagEmoji} ${l.outboundIp}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: l.settings,
                      onPressed: () => showSheet<void>(
                        context: context,
                        builder: (_) => const _IpLookupSettings(),
                      ),
                      icon: const GlyphIcon(AppGlyphs.info),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: l.ipLookupManual,
                      onPressed: entry.isLoading
                          ? null
                          : () => _probe!.refresh([routedOutbound]),
                      icon: const GlyphIcon(AppGlyphs.refresh),
                    ),
                  ],
                ),
              ),
              if (info != null)
                IpQualityText(ip: info.ip, openDetails: true)
              else
                Text(
                  entry.isLoading
                      ? entry.phase == ProbePhase.queued
                            ? l.ipLookupWaiting
                            : l.loading
                      : entry.phase == ProbePhase.failed
                      ? ipLookupReason(context, entry.reason)
                      : l.ipLookupNotChecked,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Tooltip(
                message:
                    'Cloudflare · ${info?.checkedAt?.toLocal() ?? l.ipLookupNotChecked}',
                child: Text(
                  '${proxied ? l.ipLookupRoutes : l.direct}${entry.expired ? ' · ${l.ipLookupStale}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IpLookupSettings extends StatelessWidget {
  const _IpLookupSettings();
  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.ipLookupDisclosure),
          ConfigToggleItem(
            selector: appSettingProvider.select((s) => s.automaticOutboundIp),
            title: (l) => l.ipLookupAutomatic,
            onChanged: (ref, value) => ref
                .read(appSettingProvider.notifier)
                .update((s) => s.copyWith(automaticOutboundIp: value)),
          ),
        ],
      ),
    );
  }
}
