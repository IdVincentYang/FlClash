import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/connection_countries.dart';
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

class ConnectionCountryIcon extends StatelessWidget {
  const ConnectionCountryIcon({
    super.key,
    required this.info,
    required this.countries,
    this.localPublicIp,
  });

  final TrackerInfo info;
  final Map<String, String> countries;
  final String? localPublicIp;

  @override
  Widget build(BuildContext context) {
    final ip = connectionCountryIp(info, localPublicIp);
    final country = countries[ip];
    final l = context.appLocalizations;
    return SizedBox(
      width: 28,
      child: country == null || ip == null
          ? null
          : Tooltip(
              message: connectionProxyServerIp(info) == null
                  ? l.activityLocalPublicCountry(ip, country)
                  : l.activityProxyServerCountry(ip, country),
              child: Text(
                country.countryFlagEmoji,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontSize: 24,
                  fontFamily: 'Apple Color Emoji',
                  fontFamilyFallback: ['Noto Color Emoji'],
                ),
              ),
            ),
    );
  }
}

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
            style: activityActiveStyle(context, (active ?? 0) > 0),
          ),
          TextSpan(text: '${parts.last} · $time'),
        ],
      ),
      semanticsLabel:
          '${l10n.activityCounts(active?.toString() ?? '—', totals.connectionCount)} · ${l10n.activityLast(time)}',
    );
  }
}
