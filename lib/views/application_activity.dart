import 'package:fl_clash/widgets/application_activity_item.dart';
import 'dart:async';

import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/widgets/application_policy_status.dart';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/exit_cache.dart';
import 'package:fl_clash/widgets/widgets.dart';

import 'access.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
  bool _scrolling = false;
  List<String> _rowOrder = [];
  bool _wasCurrent = false;

  void _search(String value) => setState(() => _query = value);

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_wasCurrent) {
      scheduleMicrotask(() {
        if (mounted) {
          unawaited(cleanExitCache(ref.read(exitCacheDatabaseProvider)));
        }
      });
    }
    _wasCurrent = current;
    final l10n = context.appLocalizations;
    final activity = ref.watch(applicationActivityProvider);
    final catalogue = ref.watch(applicationCatalogueProvider);
    final hold =
        _scrolling ||
        ref.watch(applicationRoutingControllerProvider).pending.isNotEmpty;
    final search = SearchQuery(_query);
    final visible =
        applicationActivityEntries(
              ref,
              showAllApps: _showAllApps,
              previousOrder: hold ? _rowOrder : null,
            )
            .where(
              (entry) => search.matches([
                entry.package?.label,
                entry.package?.packageName,
                entry.activity?.application.packageName,
                ...?entry.activity?.application.packages,
                if (entry.activity?.application.uid != null)
                  '${entry.activity!.application.uid}',
                applicationActivityLabel(context, entry),
              ]),
            )
            .toList();
    _rowOrder = visible.map((entry) => entry.key).toList();
    return CommonScaffold(
      title: l10n.applicationNetwork,
      menuItems: [
        CommonPopupMenuItem(
          label: l10n.appPolicyVpnScope,
          glyph: AppGlyphs.vpn,
          onPressed: () => BaseNavigator.push(context, const AccessView()),
        ),
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
            padding: EdgeInsets.only(top: context.contentTopPadding),
            child: const ApplicationPolicyStatus(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
            child: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                _scrolling = notification.direction != ScrollDirection.idle;
                return false;
              },
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
                  return ApplicationActivityItem(
                    key: ValueKey('activity:${entry.key}'),
                    entry: entry,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
