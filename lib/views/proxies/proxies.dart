import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'setting.dart';
import 'tab.dart';
import 'local_groups.dart';
import 'group_routing.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key});

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();
  bool _hasProviders = false;
  bool _isTab = false;

  Future<void> _manageReferences() => manageLocalGroupReferences(context, ref);

  List<CommonPopupMenuItem> _buildMenuItems(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.layers,
        label: appLocalizations.localGroupsUse,
        onPressed: _manageReferences,
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.layers,
        label: appLocalizations.localGroupsTitle,
        onPressed: () => BaseNavigator.push(context, const LocalGroupsView()),
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.sliders,
        label: appLocalizations.settings,
        onPressed: () {
          showSheet(
            context: context,
            props: const SheetProps(isScrollControlled: true),
            builder: (_) {
              return CommonScaffold(
                body: const ProxiesSetting(),
                title: appLocalizations.settings,
              );
            },
          );
        },
      ),
      if (_hasProviders)
        CommonPopupMenuItem(
          glyph: AppGlyphs.layers,
          label: appLocalizations.providers,
          onPressed: () {
            showExtend(
              context,
              builder: (_) {
                return const ProvidersView();
              },
            );
          },
        ),
    ];
  }

  IconButtonData? _buildPrimaryAction() {
    if (!_isTab) {
      return null;
    }
    final currentGroupName = ref.watch(
      proxiesTabControllerStateProvider.select(
        (state) => state.currentGroupName,
      ),
    );
    final isDelayTesting = ref.watch(
      delayTestingGroupsProvider.select(
        (state) => state.contains(currentGroupName),
      ),
    );
    return IconButtonData(
      glyph: AppGlyphs.bolt,
      onPressed: () {
        _proxiesTabKey.currentState?.delayTestCurrentGroup();
      },
      tooltip: context.appLocalizations.delayTest,
      isLoading: isDelayTesting,
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(providersProvider.select((state) => state.isNotEmpty), (
      prev,
      next,
    ) {
      if (prev != next) {
        setState(() {
          _hasProviders = next;
        });
      }
    }, fireImmediately: true);
    ref.listenManual(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.tab,
      ),
      (prev, next) {
        if (prev != next) {
          setState(() {
            _isTab = next;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.type),
    );
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    final preparation = ref.watch(proxyPreparationProvider);
    final active = preparation.stage != null || isLoading;
    final phaseLabel = switch (preparation.stage) {
      ProxyPreparationStage.configuration =>
        context.appLocalizations.localGroupsPreparing,
      ProxyPreparationStage.sources =>
        context.appLocalizations.localGroupsPreparingSources,
      ProxyPreparationStage.downloading =>
        context.appLocalizations.localGroupsDownloading,
      ProxyPreparationStage.applying =>
        context.appLocalizations.localGroupsApplying,
      null => context.appLocalizations.localGroupsPreparing,
    };
    return CommonScaffold(
      isLoading: false,
      resizeToAvoidBottomInset: false,
      primaryAction: _buildPrimaryAction(),
      iconActions: [
        if (_isTab)
          IconButtonData(
            glyph: AppGlyphs.locate,
            onPressed: () {
              _proxiesTabKey.currentState?.scrollToGroupSelected();
            },
            tooltip: context.appLocalizations.scrollToSelected,
          ),
      ],
      menuItems: _buildMenuItems(context),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: Column(
        children: [
          if (active || preparation.failed)
            Padding(
              padding: EdgeInsets.only(top: context.contentTopPadding),
              child: ListTile(
                leading: active
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const GlyphIcon(AppGlyphs.info),
                title: Text(
                  active
                      ? phaseLabel
                      : ref.watch(configStateProvider).fact.businessActive
                      ? context.appLocalizations.configRetained
                      : context.appLocalizations.profileRefreshFailed,
                ),
                trailing: active
                    ? null
                    : TextButton(
                        onPressed: () => ref
                            .read(setupActionProvider.notifier)
                            .applyProfile(force: true),
                        child: Text(context.appLocalizations.retry),
                      ),
              ),
            ),
          if (!active && !preparation.failed) const SizedBox.shrink(),
          Expanded(
            key: const ValueKey('proxy-pages'),
            child: switch (proxiesType) {
              ProxiesType.tab => ProxiesTabView(key: _proxiesTabKey),
              ProxiesType.list => const ProxiesListView(),
            },
          ),
        ],
      ),
    );
  }
}
