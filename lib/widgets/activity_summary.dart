import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';

TextStyle activityActiveStyle(BuildContext context, bool? active) => TextStyle(
  color: active == true
      ? context.colorScheme.primary
      : context.colorScheme.onSurfaceVariant,
  fontWeight: active == true ? FontWeight.w600 : FontWeight.normal,
);

String activityRuleText(BuildContext context, TrackerInfo info) {
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

class ActivityTrafficSummary extends StatelessWidget {
  const ActivityTrafficSummary({
    super.key,
    required this.traffic,
    this.showScope = true,
    this.compact = false,
    this.small = false,
  });

  final Traffic traffic;
  final bool showScope, compact, small;

  String _shortTraffic(num bytes) {
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < TrafficUnit.values.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.truncate()}${TrafficUnit.values[index].name[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final up = _shortTraffic(traffic.up);
    final down = _shortTraffic(traffic.down);
    final scope = showScope ? '${l10n.activityRetainedTraffic} · ' : '';
    final description =
        '$scope${l10n.upload} ${traffic.up.traffic.show} · '
        '${l10n.download} ${traffic.down.traffic.show}';
    final text = Text(
      '${compact ? '' : scope}↑$up ↓$down',
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      softWrap: compact ? false : null,
      textAlign: TextAlign.end,
      semanticsLabel: description,
      style:
          (small ? context.textTheme.labelSmall : context.textTheme.bodySmall)
              ?.copyWith(color: context.colorScheme.onSurfaceVariant),
    );
    return compact
        ? Tooltip(message: description, excludeFromSemantics: true, child: text)
        : text;
  }
}

class ActivityConnectionSummary extends StatelessWidget {
  const ActivityConnectionSummary({
    super.key,
    required this.totals,
    this.singleLine = false,
  });

  final ActivityTotals totals;
  final bool singleLine;

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
            style: activityActiveStyle(context, (active ?? 0) > 0),
          ),
          TextSpan(text: '${parts.last} · $time'),
        ],
      ),
      maxLines: singleLine ? 1 : null,
      overflow: singleLine ? TextOverflow.ellipsis : null,
      semanticsLabel:
          '${l10n.activityCounts(active?.toString() ?? '—', totals.connectionCount)} · ${l10n.activityLast(time)}',
    );
  }
}
