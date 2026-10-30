import 'dart:async';
import 'dart:math';

import 'package:fl_clash/plugins/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reportAppProvider = Provider<App>((ref) => App());
final reportsProvider = NotifierProvider.autoDispose<Reports, ReportState>(
  Reports.new,
);

class ReportItem {
  final String token;
  final Map<String, Object?> summary;

  ReportItem(this.token, Map<String, Object?> summary)
    : summary = Map.unmodifiable(summary);
}

class ReportState {
  final String revision;
  final List<ReportItem> items;
  final int bytes;
  final ReportItem? selected;
  final String status;
  final bool busy;
  final bool exporting;

  const ReportState({
    this.revision = '',
    this.items = const [],
    this.bytes = 0,
    this.selected,
    this.status = 'ready',
    this.busy = false,
    this.exporting = false,
  });

  ReportState update({
    ReportItem? selected,
    bool clearSelection = false,
    String? status,
    bool busy = false,
    bool exporting = false,
  }) => ReportState(
    revision: revision,
    items: items,
    bytes: bytes,
    selected: clearSelection ? null : selected ?? this.selected,
    status: status ?? this.status,
    busy: busy,
    exporting: exporting,
  );
}

class Reports extends Notifier<ReportState> {
  late App _client;
  int _generation = 0;
  final String _owner = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String? _nonce;

  @override
  ReportState build() {
    _client = ref.read(reportAppProvider);
    ref.onDispose(release);
    return const ReportState();
  }

  void _cancelPending() {
    final nonce = _nonce;
    _nonce = null;
    if (nonce != null) unawaited(_client.cancelReportExport(nonce));
  }

  void cancel() {
    release();
    state = state.update(status: 'cancelled');
  }

  void release() {
    _generation++;
    _cancelPending();
  }

  Future<void> refresh({String? notice}) async {
    _cancelPending();
    final generation = ++_generation;
    state = state.update(clearSelection: true, status: notice, busy: true);
    final value = await _client.manageReports({'action': 'inventory'});
    if (!ref.mounted || generation != _generation) return;
    final status = value['status'] as String? ?? 'io';
    state = ReportState(
      revision: value['revision'] as String? ?? '',
      items: List.unmodifiable([
        for (final entry in (value['items'] as List? ?? const []))
          ReportItem(
            (entry as Map)['token'] as String,
            Map<String, Object?>.from(entry['summary'] as Map),
          ),
      ]),
      bytes: (value['bytes'] as num?)?.toInt() ?? 0,
      status: status == 'ready' ? notice ?? status : status,
    );
  }

  Future<void> select(ReportItem item) async {
    _cancelPending();
    final generation = ++_generation;
    state = state.update(selected: item, busy: true);
    final value = await _client.manageReports({
      'action': 'summary',
      'revision': state.revision,
      'token': item.token,
    });
    if (!ref.mounted || generation != _generation) return;
    final status = value['status'] as String? ?? 'io';
    state = state.update(
      selected: status == 'ready'
          ? ReportItem(
              item.token,
              Map<String, Object?>.from(value['summary'] as Map),
            )
          : null,
      clearSelection: status != 'ready',
      status: status,
    );
  }

  void deselect() {
    cancel();
    state = state.update(clearSelection: true, status: 'ready');
  }

  Future<void> remove(String revision, String? token) async {
    _cancelPending();
    final generation = ++_generation;
    state = state.update(clearSelection: true, busy: true);
    final value = await _client.manageReports({
      'action': 'delete',
      'revision': revision,
      if (token != null) 'token': token else 'all': true,
    });
    if (!ref.mounted || generation != _generation) return;
    await refresh(notice: value['status'] as String? ?? 'io');
  }

  Future<void> export(bool raw) async {
    final selected = state.selected;
    if (selected == null || state.busy) return;
    final generation = ++_generation;
    final nonce = '$_owner:$generation';
    _nonce = nonce;
    state = state.update(busy: true, exporting: true);
    final value = await _client.exportReport({
      'revision': state.revision,
      'token': selected.token,
      'kind': raw ? 'raw' : 'summary',
      'nonce': nonce,
    });
    if (!ref.mounted || generation != _generation) return;
    _nonce = null;
    state = state.update(status: value['status'] as String? ?? 'io');
  }
}
