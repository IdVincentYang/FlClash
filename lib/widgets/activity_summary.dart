import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:material_ui/material_ui.dart';

class ActivityConnectionSummary extends StatelessWidget {
  const ActivityConnectionSummary({super.key, required this.totals});

  final ActivityTotals totals;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final active = totals.activeCount;
    final time = totals.lastActivity.getLastUpdateTimeDesc(context);
    const activePlaceholder = '{active}';
    final parts = l10n
        .activityCompactCounts(activePlaceholder, totals.connectionCount)
        .split(activePlaceholder);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.first),
          TextSpan(
            text: active?.toString() ?? '—',
            style: TextStyle(
              color: (active ?? 0) > 0
                  ? context.colorScheme.primary
                  : context.colorScheme.onSurfaceVariant,
              fontWeight: (active ?? 0) > 0
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          TextSpan(text: '${parts.last} · $time'),
        ],
      ),
      semanticsLabel:
          '${l10n.activityCounts(active?.toString() ?? '—', totals.connectionCount)} · ${l10n.activityLast(time)}',
    );
  }
}
