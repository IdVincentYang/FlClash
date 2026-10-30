import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/reports.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [reportsProvider.overrideWith(Reports.new)],
    child: const _ReportsPage(),
  );
}

class _ReportsPage extends ConsumerStatefulWidget {
  const _ReportsPage();

  @override
  ConsumerState<_ReportsPage> createState() => _ReportsViewState();
}

class _ReportsViewState extends ConsumerState<_ReportsPage> {
  late final Reports _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(reportsProvider.notifier);
    scheduleMicrotask(() {
      if (mounted) unawaited(ref.read(reportsProvider.notifier).refresh());
    });
  }

  @override
  void dispose() {
    _controller.release();
    super.dispose();
  }

  String _status(String value) {
    final s = context.appLocalizations;
    return switch (value) {
      'ready' => '',
      'deleted' => s.reportDeleted,
      'exported' => s.reportExported,
      'written_unverified' => s.reportWrittenUnverified,
      'cancelled' => s.reportCancelled,
      'stale' => s.reportStale,
      'busy' || 'deadline' => s.reportBusy,
      'limited' => s.reportLimited,
      'integrity' => s.reportIntegrity,
      _ => s.reportFailed,
    };
  }

  String _material(String? value) {
    final s = context.appLocalizations;
    return switch (value) {
      'metadata_only' => s.reportMetadataOnly,
      'unverified' => s.reportRawUnverified,
      'missing_raw' => s.reportRawMissing,
      'unknown_schema' => s.reportUnknownFormat,
      _ => s.reportCorrupt,
    };
  }

  String _description(Map<String, Object?> summary) {
    final time = summary['savedAt'] as int?;
    final date = time != null && time <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(time).toLocal().toString()
        : context.appLocalizations.unknown;
    return '$date · ${summary['source'] ?? context.appLocalizations.unknown}\n'
        '${summary['versionName'] ?? summary['versionCode'] ?? context.appLocalizations.unknown}'
        ' · ${_material(summary['state'] as String?)}';
  }

  Future<void> _delete(ReportState state) async {
    final confirmed = await dialogs.showMessage(
      context: context,
      title: state.selected == null
          ? context.appLocalizations.reportDeleteAll
          : context.appLocalizations.delete,
      message: TextSpan(text: context.appLocalizations.reportDeleteWarning),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(reportsProvider.notifier)
          .remove(state.revision, state.selected?.token);
    }
  }

  Future<void> _export(bool raw) async {
    final selected = ref.read(reportsProvider).selected?.token;
    final confirmed = await dialogs.showMessage(
      context: context,
      message: TextSpan(
        text: raw
            ? context.appLocalizations.reportRawWarning
            : context.appLocalizations.reportDestinationWarning,
      ),
    );
    if (confirmed == true &&
        mounted &&
        ref.read(reportsProvider).selected?.token == selected) {
      await ref.read(reportsProvider.notifier).export(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportsProvider);
    final controller = ref.read(reportsProvider.notifier);
    final s = context.appLocalizations;
    final selected = state.selected;
    final status = _status(state.status);
    final usage = state.revision.isEmpty
        ? s.unknown
        : '${state.items.length}/20 · ${state.bytes} B / 16 MiB';
    return CommonScaffold(
      title: s.localCrashReports,
      backAction: selected == null ? null : controller.deselect,
      isLoading: state.busy,
      iconActions: [
        if (state.exporting)
          IconButtonData(
            glyph: AppGlyphs.close,
            tooltip: s.cancel,
            onPressed: controller.cancel,
          ),
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: s.reportRefresh,
          onPressed: () => controller.refresh(),
        ),
        IconButtonData(
          glyph: AppGlyphs.delete,
          tooltip: selected == null ? s.reportDeleteAll : s.delete,
          onPressed: state.busy || state.items.isEmpty
              ? null
              : () => _delete(state),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.only(
          top: context.appBarInset,
          bottom: 20 + BottomInsetScope.of(context),
        ),
        children: [
          ListItem(
            title: Text(s.reportUsage),
            subtitle: Text('$usage\n${s.reportRetention}'),
          ),
          if (status.isNotEmpty)
            ListItem(title: Text(status, key: const ValueKey('report-status'))),
          if (selected == null) ...[
            if (state.items.isEmpty && !state.busy && state.status == 'ready')
              ListItem(title: Text(s.reportEmpty)),
            for (final item in state.items)
              ListItem(
                key: ValueKey(item.token),
                title: Text(_description(item.summary)),
                onTap: state.busy ? null : () => controller.select(item),
              ),
          ] else ...[
            ListItem(title: Text(_description(selected.summary))),
            if (selected.summary['reason'] case final int reason)
              ListItem(
                title: Text(
                  s.bootRecoveryReason(switch (reason) {
                    4 => s.bootExitCrash,
                    5 => s.bootExitNativeCrash,
                    6 => s.bootExitAnr,
                    7 => s.bootExitInitialization,
                    _ => '$reason',
                  }),
                ),
              ),
            ListItem(
              title: Text(
                '${s.format}: ${selected.summary['format'] ?? s.unknown}',
              ),
              subtitle: Text(
                '${s.size}: ${selected.summary['rawBytes'] ?? s.unknown} B',
              ),
            ),
            ListItem(
              title: Text(s.reportBuildIdentity),
              subtitle: SelectableText(
                [
                  for (final key in const [
                    'versionName',
                    'versionCode',
                    'api',
                    'process',
                    'abi',
                    'apkSha256',
                    'libclash.so:gnu',
                    'libcore.so:gnu',
                    'librust_api.so:gnu',
                    'libapp.so:gnu',
                    'libflutter.so:gnu',
                  ])
                    '$key: ${selected.summary[key] ?? s.unknown}',
                  for (final library in const [
                    'libclash.so',
                    'libcore.so',
                    'librust_api.so',
                    'libapp.so',
                    'libflutter.so',
                  ])
                    if (selected.summary['$library:go'] case final String id)
                      '$library:go: $id',
                ].join('\n'),
              ),
            ),
            if (selected.summary['truncated'] == true)
              ListItem(title: Text(s.reportTruncated)),
            ListItem(
              title: Text(s.reportExportSummary),
              onTap: state.busy ? null : () => _export(false),
            ),
            if (selected.summary['rawAvailable'] == true)
              ListItem(
                title: Text(s.reportExportRaw),
                onTap: state.busy ? null : () => _export(true),
              ),
          ],
        ],
      ),
    );
  }
}
