import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/views/application_targets.dart';
import 'package:fl_clash/widgets/application_policy.dart';
import 'package:fl_clash/widgets/application_policy_status.dart';
import 'package:fl_clash/widgets/activity_summary.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

typedef ApplicationActivityEntry = ({
  String key,
  Package? package,
  AppActivity? activity,
});

String applicationActivityLabel(
  BuildContext context,
  ApplicationActivityEntry entry,
) {
  final identity = entry.activity?.application;
  final packageName = entry.package?.packageName ?? identity?.packageName;
  if (packageName == globalState.packageInfo.packageName) {
    return globalState.packageInfo.appName;
  }
  if (entry.package case final package?) return package.label;
  if (identity?.status == 'notFound' && identity?.uid != null) {
    return context.appLocalizations.activityUid(identity!.uid!);
  }
  return identity?.packageName ??
      (identity?.status == 'ambiguous'
          ? context.appLocalizations.activitySharedUid
          : context.appLocalizations.activityUnknownApp);
}

List<ApplicationActivityEntry> applicationActivityEntries(
  WidgetRef ref, {
  bool showAllApps = false,
  List<String>? previousOrder,
}) {
  final activity = ref.watch(applicationActivityProvider);
  final catalogue = ref.watch(applicationCatalogueProvider).asData?.value;
  final packages = {
    for (final package in catalogue?.packages ?? <Package>[])
      package.packageName: package,
  };
  final apps = activity.apps;
  final ordered = [
    ...apps.where((item) => item.totals.confirmedActiveCount > 0),
    ...apps.where((item) => item.totals.confirmedActiveCount == 0),
  ];
  final rows = <String, ApplicationActivityEntry>{
    for (final app in ordered)
      app.key: (
        key: app.key,
        package: packages[app.application.packageName],
        activity: app,
      ),
  };
  final routing = ref.watch(applicationRoutingSettingsProvider).value;
  for (final rule in routing?.rules.values ?? <ApplicationRouteRule>[]) {
    if (!rule.enabled) continue;
    final key = 'package:${rule.packageName}';
    rows.putIfAbsent(
      key,
      () => (
        key: key,
        package:
            packages[rule.packageName] ??
            Package(
              packageName: rule.packageName,
              label: rule.packageName,
              system: false,
              internet: true,
              lastUpdateTime: 0,
            ),
        activity: null,
      ),
    );
  }
  if (showAllApps) {
    final sorted = packages.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    for (final package in sorted) {
      final key = 'package:${package.packageName}';
      rows.putIfAbsent(key, () => (key: key, package: package, activity: null));
    }
  }
  final operation = ref.watch(applicationRoutingControllerProvider);
  final profileId = ref.watch(currentProfileIdProvider);
  final invalid = <String>{};
  for (final entry in rows.values) {
    final packageName =
        entry.package?.packageName ?? entry.activity?.application.packageName;
    if (operation.errors.containsKey(packageName)) invalid.add(entry.key);
    for (final host in routing?.hostRules ?? <Rule>[]) {
      if (host.hostBinding?.packageName == packageName &&
          hostRuleApplies(host, profileId) &&
          routing?.rules[packageName]?.enabled == true) {
        final issue = hostRuleTargetState(ref, host)?.issue;
        if (issue != null && issue != ApplicationTargetIssue.preparing) {
          invalid.add(entry.key);
        }
      }
    }
    final rule = routing?.rules[packageName];
    if (rule?.enabled == true &&
        rule!.hasDefault &&
        rule.action == ApplicationRouteAction.proxy) {
      final target = applicationTargetState(ref, rule);
      if (target.issue != null &&
          target.issue != ApplicationTargetIssue.preparing) {
        invalid.add(entry.key);
      }
    }
  }
  final entries = rows.values.toList();
  final order = {
    for (final (index, entry) in entries.indexed) entry.key: index,
  };
  final previous = {
    for (final (index, key) in (previousOrder ?? <String>[]).indexed)
      key: index,
  };
  entries.sort((a, b) {
    if (previousOrder != null) {
      return (previous[a.key] ?? entries.length).compareTo(
        previous[b.key] ?? entries.length,
      );
    }
    final priority = (invalid.contains(a.key) ? 0 : 1).compareTo(
      invalid.contains(b.key) ? 0 : 1,
    );
    return priority != 0 ? priority : order[a.key]!.compareTo(order[b.key]!);
  });
  return entries;
}

class ApplicationActivityItem extends ConsumerWidget {
  const ApplicationActivityItem({super.key, required this.entry});
  final ApplicationActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final package = entry.package;
    final activity = entry.activity;
    final label = applicationActivityLabel(context, entry);
    final packageName =
        package?.packageName ?? activity?.application.packageName;
    final totals = activity?.totals;
    final paths = totals?.exitPaths ?? [];
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => BaseNavigator.push(
          context,
          ApplicationTargetsView(
            appKey: entry.key,
            label: label,
            packageName: packageName,
            identity: activity?.application ?? const ApplicationIdentity(),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        minVerticalPadding: 8,
        horizontalTitleGap: 12,
        subtitleTextStyle: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
        leading: packageName == null
            ? const GlyphIcon(AppGlyphs.application, size: 48)
            : PackageIcon(
                packageName: packageName,
                size: 48,
                placeholder: const GlyphIcon(AppGlyphs.application, size: 48),
              ),
        title: Row(
          children: [
            Expanded(
              child: DefaultTextStyle(
                style: context.textTheme.bodySmall!.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.titleMedium,
                            ),
                          ),
                          if (totals?.retainedTraffic case final traffic?)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: (constraints.maxWidth - 8).clamp(
                                  0.0,
                                  double.infinity,
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerEnd,
                                child: ActivityTrafficSummary(
                                  traffic: traffic,
                                  compact: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (totals == null)
                      Text(l10n.activityNoObserved)
                    else
                      ActivityConnectionSummary(
                        totals: totals,
                        singleLine: true,
                      ),
                    if (paths.isNotEmpty)
                      Text(
                        paths.first.isEmpty
                            ? l10n.unknown
                            : '${paths.first.join(' → ')}${paths.length > 1 ? ' (+${paths.length - 1})' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            ApplicationPolicySwitch(
              packages: packageName != null
                  ? package?.sharedPackages.isNotEmpty == true
                        ? package!.sharedPackages
                        : [packageName]
                  : activity?.application.status == 'ambiguous'
                  ? activity!.application.packages
                  : const [],
              label: label,
            ),
          ],
        ),
      ),
    );
  }
}
