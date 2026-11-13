import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/widgets/activity_summary.dart';

import 'application_targets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApplicationActivityView extends ConsumerStatefulWidget {
  const ApplicationActivityView({super.key});

  @override
  ConsumerState<ApplicationActivityView> createState() =>
      _ApplicationActivityViewState();
}

class _ApplicationActivityViewState
    extends ConsumerState<ApplicationActivityView> {
  bool _showAllApps = false;
  String _query = '';

  void _search(String value) => setState(() => _query = value);

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final activity = ref.watch(applicationActivityProvider);
    final catalogue = ref.watch(applicationCatalogueProvider);
    final packages = {
      for (final package in catalogue.asData?.value.packages ?? <Package>[])
        package.packageName: package,
    };
    final apps = activity.apps;
    final ordered = [
      ...apps.where((item) => item.totals.confirmedActiveCount > 0),
      ...apps.where((item) => item.totals.confirmedActiveCount == 0),
    ];
    final rows = <String, ({Package? package, AppActivity? activity})>{
      for (final item in ordered)
        item.key: (
          package: packages[item.application.packageName],
          activity: item,
        ),
    };
    if (_showAllApps) {
      final sorted = packages.values.toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      for (final package in sorted) {
        rows.putIfAbsent(
          'package:${package.packageName}',
          () => (package: package, activity: null),
        );
      }
    }
    final search = SearchQuery(_query);
    final visible = rows.entries.where((entry) {
      final item = entry.value;
      return search.matches([
        item.package?.label,
        item.package?.packageName,
        item.activity?.application.packageName,
        ...?item.activity?.application.packages,
        if (item.activity?.application.uid != null)
          '${item.activity!.application.uid}',
        _label(item.package, item.activity),
      ]);
    }).toList();
    return CommonScaffold(
      title: l10n.applicationNetwork,
      menuItems: [
        CommonPopupMenuItem(
          label: l10n.activityShowAllApps,
          glyph: AppGlyphs.appsList,
          checked: _showAllApps,
          onPressed: () => setState(() => _showAllApps = !_showAllApps),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 8),
            child: SearchField(
              hintText: l10n.activitySearchApps,
              onChanged: _search,
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
          if (_showAllApps && catalogue.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(l10n.activityLoadingApps),
            ),
          if (catalogue.hasError || catalogue.asData?.value.accessible == false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.activityCatalogueUnavailable)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(applicationCatalogueProvider),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey('application-network'),
              findChildIndexCallback: (key) {
                final index = visible.indexWhere(
                  (entry) => ValueKey('activity:${entry.key}') == key,
                );
                return index < 0 ? null : index;
              },
              padding: EdgeInsets.only(
                bottom: 16 + BottomInsetScope.of(context),
              ),
              itemCount: visible.isEmpty ? 1 : visible.length,
              itemBuilder: (context, index) {
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      search.isNotEmpty
                          ? l10n.activityNoMatches
                          : l10n.activityNoObserved,
                    ),
                  );
                }
                final entry = visible[index];
                return _ApplicationActivityRow(
                  key: ValueKey('activity:${entry.key}'),
                  label: _label(entry.value.package, entry.value.activity),
                  package: entry.value.package,
                  activity: entry.value.activity,
                  onTap: () => BaseNavigator.push(
                    context,
                    ApplicationTargetsView(
                      appKey: entry.key,
                      label: _label(entry.value.package, entry.value.activity),
                      packageName:
                          entry.value.package?.packageName ??
                          entry.value.activity?.application.packageName,
                      identity:
                          entry.value.activity?.application ??
                          const ApplicationIdentity(),
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

  String _label(Package? package, AppActivity? activity) {
    if (package != null) return package.label;
    final identity = activity?.application;
    return identity?.packageName ??
        (identity?.status == 'ambiguous'
            ? context.appLocalizations.activitySharedUid
            : context.appLocalizations.activityUnknownApp);
  }
}

class _ApplicationActivityRow extends StatelessWidget {
  const _ApplicationActivityRow({
    super.key,
    required this.label,
    required this.onTap,
    this.package,
    this.activity,
  });
  final String label;
  final VoidCallback onTap;
  final Package? package;
  final AppActivity? activity;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final packageName =
        package?.packageName ?? activity?.application.packageName;
    final totals = activity?.totals;
    final paths = totals?.exitPaths ?? [];
    return Card.filled(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (totals == null)
              Text(l10n.activityNoObserved)
            else
              ActivityConnectionSummary(totals: totals),
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
    );
  }
}
