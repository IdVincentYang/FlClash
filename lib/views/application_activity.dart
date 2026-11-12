import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ActivityFilter { recent, active, all }

class ApplicationActivityView extends ConsumerStatefulWidget {
  const ApplicationActivityView({super.key});

  @override
  ConsumerState<ApplicationActivityView> createState() =>
      _ApplicationActivityViewState();
}

class _ApplicationActivityViewState
    extends ConsumerState<ApplicationActivityView> {
  _ActivityFilter _filter = _ActivityFilter.recent;
  String _query = '';
  late final _searchState = AppBarSearchState(onSearch: _search);

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
    final rows = <String, ({Package? package, AppActivity? activity})>{
      for (final item in activity.apps)
        if (_filter != _ActivityFilter.active ||
            item.totals.confirmedActiveCount > 0)
          item.key: (
            package: packages[item.application.packageName],
            activity: item,
          ),
    };
    if (_filter == _ActivityFilter.all) {
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
    final status = !activity.observing
        ? l10n.activityPaused
        : activity.snapshotFailed
        ? l10n.activitySnapshotFailed
        : !activity.hasSnapshot
        ? l10n.activityChecking
        : l10n.activityObserving;
    return CommonScaffold(
      title: l10n.applicationNetwork,
      searchState: _searchState,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: l10n.retry,
          onPressed: activity.observing
              ? () => ref.read(applicationActivityProvider.notifier).refresh()
              : null,
        ),
        IconButtonData(
          glyph: AppGlyphs.info,
          tooltip: l10n.activityObservationScope,
          onPressed: () => dialogs.showMessage(
            message: TextSpan(text: l10n.activityScopeHelp),
          ),
        ),
      ],
      body: ListView.builder(
        findChildIndexCallback: (key) {
          final index = visible.indexWhere(
            (entry) => ValueKey('activity:${entry.key}') == key,
          );
          return index < 0 ? null : index + 3;
        },
        key: const PageStorageKey('application-network'),
        padding: EdgeInsets.only(
          top: context.contentTopPadding,
          bottom: 16 + BottomInsetScope.of(context),
        ),
        itemCount: 3 + (visible.isEmpty ? 1 : visible.length),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: context.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    l10n.activityRetention(activity.capacity),
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in _ActivityFilter.values)
                    ChoiceChip(
                      label: Text(switch (value) {
                        _ActivityFilter.recent => l10n.activityRecent,
                        _ActivityFilter.active => l10n.activityActive,
                        _ActivityFilter.all => l10n.activityAllApps,
                      }),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                ],
              ),
            );
          }
          if (index == 2) {
            if (catalogue.isLoading) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(l10n.activityLoadingApps),
              );
            }
            if (catalogue.hasError ||
                catalogue.asData?.value.accessible == false) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.activityCatalogueUnavailable),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(applicationCatalogueProvider),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }
          if (visible.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                search.isNotEmpty
                    ? l10n.activityNoMatches
                    : _filter == _ActivityFilter.active
                    ? l10n.activityNoActive
                    : l10n.activityNoObserved,
              ),
            );
          }
          final entry = visible[index - 3];
          return _ApplicationActivityRow(
            key: ValueKey('activity:${entry.key}'),
            label: _label(entry.value.package, entry.value.activity),
            package: entry.value.package,
            activity: entry.value.activity,
          );
        },
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
    this.package,
    this.activity,
  });
  final String label;
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
        contentPadding: const EdgeInsets.all(16),
        leading: packageName == null
            ? const GlyphIcon(AppGlyphs.application, size: 40)
            : PackageIcon(
                packageName: packageName,
                size: 40,
                placeholder: const GlyphIcon(AppGlyphs.application, size: 40),
              ),
        title: Text(label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              totals == null
                  ? l10n.activityNoObserved
                  : l10n.activityCounts(
                      totals.activeCount?.toString() ?? l10n.activityPending,
                      totals.connectionCount,
                    ),
            ),
            if (totals != null)
              Text(
                l10n.activityLast(
                  totals.lastActivity.getLastUpdateTimeDesc(context),
                ),
              ),
            if (paths.isNotEmpty)
              Text(
                paths.first.isEmpty
                    ? l10n.unknown
                    : '${paths.first.join(' → ')}${paths.length > 1 ? ' (+${paths.length - 1})' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
