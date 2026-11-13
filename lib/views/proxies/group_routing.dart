import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/source_review_status.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

typedef _GroupReferenceChoice = ({List<LocalProxyGroup> definitions, int id});

Future<void> manageLocalGroupReferences(
  BuildContext context,
  WidgetRef ref, {
  String? groupName,
}) async {
  final profile = ref.read(currentProfileProvider);
  if (profile == null) {
    context.showSnackBar(context.appLocalizations.localGroupsLoadFirst);
    return;
  }
  final subscription = ref.listenManual(globalLocalGroupsProvider, (_, _) {});
  try {
    _GroupReferenceChoice? choice;
    if (groupName == null) {
      choice = await dialogs.showCommonDialog<_GroupReferenceChoice>(
        context: context,
        child: Consumer(
          builder: (context, ref, _) {
            final l = context.appLocalizations;
            final library = ref.watch(globalLocalGroupsProvider);
            return CommonDialog(
              title: l.localGroupsUse,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.cancel),
                ),
              ],
              child: SizedBox(
                width: 360,
                child: library.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.localGroupsLoadFailed),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(globalLocalGroupsProvider),
                        child: Text(l.retry),
                      ),
                    ],
                  ),
                  data: (definitions) => definitions.isEmpty
                      ? Text(l.localGroupsNoSaved)
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final group in definitions)
                                ListTile(
                                  title: Text(group.name),
                                  subtitle: Text(
                                    l.localGroupsReferences(
                                      profile.localGroups
                                              .where(
                                                (binding) =>
                                                    binding.id == group.id,
                                              )
                                              .firstOrNull
                                              ?.entrances
                                              .length ??
                                          0,
                                    ),
                                  ),
                                  onTap: () => Navigator.of(context).pop((
                                    definitions: definitions,
                                    id: group.id,
                                  )),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      );
    } else {
      final List<LocalProxyGroup> definitions;
      try {
        definitions = await ref.read(globalLocalGroupsProvider.future);
      } catch (_) {
        if (context.mounted) {
          context.showSnackBar(context.appLocalizations.localGroupsLoadFailed);
        }
        return;
      }
      final local = definitions
          .where((group) => group.name == groupName)
          .firstOrNull;
      if (!context.mounted) return;
      if (local == null) {
        context.showSnackBar(context.appLocalizations.localGroupsChanged);
        return;
      }
      choice = (definitions: definitions, id: local.id);
    }
    if (choice == null || !context.mounted) return;
    if (ref.read(currentProfileIdProvider) != profile.id) {
      context.showSnackBar(context.appLocalizations.localGroupsChanged);
      return;
    }
    await BaseNavigator.push(
      context,
      LocalGroupRoutingView(
        profile: profile,
        definitions: choice.definitions,
        localId: choice.id,
      ),
    );
  } finally {
    subscription.close();
  }
}

class LocalGroupRoutingView extends ConsumerStatefulWidget {
  const LocalGroupRoutingView({
    super.key,
    required this.profile,
    required this.localId,
    required this.definitions,
  });

  final Profile profile;
  final int localId;
  final List<LocalProxyGroup> definitions;

  @override
  ConsumerState<LocalGroupRoutingView> createState() =>
      _LocalGroupRoutingViewState();
}

class _LocalGroupRoutingViewState extends ConsumerState<LocalGroupRoutingView> {
  late Profile _baseline;
  late final LocalProxyGroup _local;
  late Set<String> _selected;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _baseline = widget.profile;
    _local = widget.definitions
        .firstWhere((group) => group.id == widget.localId)
        .copyWith(
          parents:
              _baseline.localGroups
                  .where((group) => group.id == widget.localId)
                  .firstOrNull
                  ?.entrances
                  .toList() ??
              const [],
        );
    _selected = {..._local.entrances};
  }

  bool get _isCurrent =>
      ref.read(currentProfileProvider)?.id == widget.profile.id;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    if (_error != null) ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_isCurrent) throw const LocalProxyGroupProblem('changed');
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
        context.showSnackBar(
          userFacingErrorMessage(error, context.appLocalizations),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _perform(() async {
    final groups = ref.read(groupsProvider);
    final removed = _local.entrances.difference(_selected);
    if (groups.any(
      (group) => removed.contains(group.name) && group.now == _local.name,
    )) {
      throw const LocalProxyGroupProblem('inUse');
    }
    await ref
        .read(globalGroupsActionProvider.notifier)
        .saveReferences(
          _baseline,
          widget.definitions,
          _local.id,
          _selected.toList(),
        );
    if (!mounted) return;
    if (!_isCurrent) throw const LocalProxyGroupProblem('changed');
    final message = context.appLocalizations.localGroupsReferencesSaved;
    context.showSnackBar(message);
    Navigator.of(context).pop();
  });

  Future<void> _review() => _perform(() async {
    final profile = ref.read(currentProfileProvider)!;
    await ref
        .read(profilesActionProvider.notifier)
        .manageSourcePermissions(profile, review: true);
    if (!mounted) return;
    if (!_isCurrent) throw const LocalProxyGroupProblem('changed');
    final latest = ref.read(currentProfileProvider)!;
    if (!const ListEquality<LocalProxyGroup>().equals(
      latest.localGroups,
      _baseline.localGroups,
    )) {
      throw const LocalProxyGroupProblem('changed');
    }
    _baseline = latest;
    ref.invalidate(profileReviewStatusProvider(latest));
  });

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final profile = ref.watch(currentProfileProvider);
    final groups = ref.watch(groupsProvider);
    final current =
        profile?.id == widget.profile.id &&
            const ListEquality<LocalProxyGroup>().equals(
              ref.watch(globalLocalGroupsProvider).value,
              widget.definitions,
            )
        ? _local
        : null;
    final localNames =
        profile?.localGroups.map((group) => group.name).toSet() ?? {};
    final targets = <String>{
      ..._local.entrances,
      ..._selected,
      if (current != null)
        for (final group in groups)
          if (group.type == GroupType.Selector &&
              group.name != 'GLOBAL' &&
              !localNames.contains(group.name))
            group.name,
    };
    final changed = !const SetEquality<String>().equals(
      _selected,
      _local.entrances,
    );
    final reviewRequired =
        _error is RequestUnavailable &&
        (_error as RequestUnavailable).code ==
            'local_groups_source_unavailable';
    final enabled = !_busy && current != null;
    Widget target(String name) {
      final runtime = current == null
          ? null
          : groups.where((group) => group.name == name).firstOrNull;
      final member =
          runtime?.all.any((node) => node.name == _local.name) ?? false;
      final using = member && runtime?.now == _local.name;
      final saved = _local.entrances.contains(name);
      final status = runtime == null
          ? l.localGroupsUnavailable
          : using
          ? l.localGroupsReferenceUsing
          : member
          ? l.localGroupsReferenceAdded
          : saved
          ? l.localGroupsPending
          : l.localGroupsReferenceNotAdded;
      return Card(
        child: CheckboxListTile(
          title: Text(name),
          subtitle: Text(status),
          value: _selected.contains(name),
          onChanged: enabled && (runtime != null || saved)
              ? (value) => setState(() {
                  if (value == true) {
                    _selected.add(name);
                  } else {
                    _selected.remove(name);
                  }
                })
              : null,
        ),
      );
    }

    return CommonScaffold(
      title: l.localGroupsUse,
      isLoading: _busy,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: l.save,
        onPressed: enabled && changed ? _save : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).copyWith(
          top: context.contentTopPadding + 16,
          bottom: 16 + BottomInsetScope.of(context),
        ),
        children: [
          Text(_local.name, style: context.textTheme.titleLarge),
          Text(widget.profile.realLabel, style: context.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(l.localGroupsUseHelp),
          if (current == null) Text(l.localGroupsChanged),
          if (current != null && !current.enabled) Text(l.disabled),
          if (_busy) Text(l.localGroupsApplying),
          if (_error != null)
            Text(
              userFacingErrorMessage(_error!, l),
              style: TextStyle(color: context.colorScheme.error),
            ),
          if (reviewRequired)
            TextButton(
              onPressed: enabled ? _review : null,
              child: Text(l.sourceReviewTitle),
            ),
          const SizedBox(height: 16),
          if (targets.isEmpty) Text(l.localGroupsNoEntrance),
          for (final name in targets) target(name),
        ],
      ),
    );
  }
}
