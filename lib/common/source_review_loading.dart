import 'dart:async';

import 'package:flutter/foundation.dart';

import 'source_acceptance.dart';

enum SourceReviewLoadPhase { queued, loading, parsing, ready, failed }

typedef SourceReviewItemLoader =
    Future<SourceReviewBatchEntry> Function(
      String key,
      void Function(SourceReviewLoadPhase phase, {bool cached}) progress,
    );

class SourceReviewLoadItem {
  SourceReviewLoadItem({
    required this.key,
    required this.label,
    required this.kind,
    this.origin = '',
    this.entry,
  }) : phase = entry == null
           ? SourceReviewLoadPhase.queued
           : SourceReviewLoadPhase.ready;
  final String key, label, kind, origin;
  SourceReviewLoadPhase phase;
  SourceReviewBatchEntry? entry;
  Object? error;
  bool cached = false;
}

class SourceReviewLoading extends ChangeNotifier {
  List<SourceReviewLoadItem> _items = const [];
  final _queue = <SourceReviewLoadItem>[];
  final _idle = <Completer<void>>[];
  SourceReviewItemLoader? _loader;
  int _generation = 0;
  int _active = 0;
  bool _disposed = false;
  List<SourceReviewLoadItem> get items => List.unmodifiable(_items);
  bool get ready =>
      _items.isNotEmpty &&
      _items.every((item) => item.phase == SourceReviewLoadPhase.ready);
  bool get busy => _active != 0 || _queue.isNotEmpty;
  bool get settled =>
      _items.isNotEmpty &&
      !busy &&
      _items.every(
        (item) =>
            item.phase == SourceReviewLoadPhase.ready ||
            item.phase == SourceReviewLoadPhase.failed,
      );

  void reset() {
    _generation++;
    _active = 0;
    _queue.clear();
    _items = const [];
    for (final waiter in _idle) {
      waiter.complete();
    }
    _idle.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> load(
    List<SourceReviewLoadItem> items,
    SourceReviewItemLoader loader,
  ) {
    reset();
    if (_disposed) return Future.value();
    _items = List.of(items);
    _loader = loader;
    _queue.addAll(items.where((item) => item.entry == null));
    notifyListeners();
    return _drain();
  }

  Future<void> retry(String key) {
    if (_disposed) return Future.value();
    final item = _items.where((item) => item.key == key).firstOrNull;
    if (item == null || item.phase != SourceReviewLoadPhase.failed) {
      return Future.value();
    }
    item.phase = SourceReviewLoadPhase.queued;
    item.error = null;
    _queue.add(item);
    notifyListeners();
    return _drain();
  }

  Future<void> _drain() {
    final done = Completer<void>();
    _idle.add(done);
    _pump();
    return done.future;
  }

  void _pump() {
    if (_disposed) return;
    final generation = _generation;
    while (_active < 3 && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _active++;
      unawaited(_load(item, generation));
    }
    if (!busy) {
      for (final waiter in _idle) {
        waiter.complete();
      }
      _idle.clear();
    }
  }

  Future<void> _load(SourceReviewLoadItem item, int generation) async {
    bool current() => !_disposed && _generation == generation;
    void progress(SourceReviewLoadPhase phase, {bool cached = false}) {
      if (!current()) return;
      item.phase = phase;
      item.cached = cached;
      notifyListeners();
    }

    progress(SourceReviewLoadPhase.loading);
    try {
      final entry = await _loader!(item.key, progress);
      if (!current()) return;
      item.entry = entry;
      item.phase = SourceReviewLoadPhase.ready;
    } catch (error) {
      if (!current()) return;
      item.error = error;
      item.phase = SourceReviewLoadPhase.failed;
    } finally {
      if (current()) {
        _active--;
        notifyListeners();
        _pump();
      }
    }
  }

  @override
  void dispose() {
    reset();
    _disposed = true;
    super.dispose();
  }
}
