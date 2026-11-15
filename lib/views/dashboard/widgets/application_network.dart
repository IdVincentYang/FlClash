import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/views/application_activity.dart';
import 'package:fl_clash/views/dashboard/widget_metrics.dart';
import 'package:fl_clash/widgets/application_activity_item.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ApplicationNetworkCard extends ConsumerStatefulWidget {
  const ApplicationNetworkCard({super.key});

  @override
  ConsumerState<ApplicationNetworkCard> createState() =>
      _ApplicationNetworkCardState();
}

class _ApplicationNetworkCardState
    extends ConsumerState<ApplicationNetworkCard> {
  List<String> _rowOrder = [];

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final ready = ref.watch(initProvider);
    final pending =
        ready &&
        ref.watch(applicationRoutingControllerProvider).pending.isNotEmpty;
    final entries = ready
        ? applicationActivityEntries(
            ref,
            previousOrder: pending ? _rowOrder : null,
          )
        : <ApplicationActivityEntry>[];
    _rowOrder = entries.map((entry) => entry.key).toList();
    return Card.outlined(
      margin: EdgeInsets.zero,
      color: context.colorScheme.surfaceContainerLow,
      shape: AppShape.all(DashboardWidgetMetrics.radiusOf(context)).copyWith(
        side: BorderSide(color: context.colorScheme.surfaceContainerHighest),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: !ready
                ? null
                : () => BaseNavigator.push(
                    context,
                    const ApplicationActivityView(),
                  ),
            child: Row(
              children: [
                Expanded(
                  child: InfoHeader(
                    info: Info(
                      label: l.applicationNetwork,
                      glyph: AppGlyphs.application,
                    ),
                    padding: DashboardWidgetMetrics.paddingOf(context),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: GlyphIcon(AppGlyphs.chevronForward, size: 20),
                ),
              ],
            ),
          ),
          if (!ready)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: LinearProgressIndicator(),
            )
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(l.activityNoObserved),
            ),
          for (final entry in entries.take(5))
            ApplicationActivityItem(
              key: ValueKey('activity:${entry.key}'),
              entry: entry,
            ),
          if (entries.isNotEmpty) const SizedBox(height: 12),
        ],
      ),
    );
  }
}
