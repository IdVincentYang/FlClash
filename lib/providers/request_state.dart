import 'dart:async';

import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final nativeRequestStateProvider =
    NotifierProvider<NativeRequestState, Map<String, Object?>>(
      NativeRequestState.new,
    );

class NativeRequestState extends Notifier<Map<String, Object?>>
    with ServiceListener {
  NativeRequestState() : _native = null;
  NativeRequestState.scoped(Service native) : _native = native;
  final Service? _native;
  @override
  Map<String, Object?> build() {
    final native = _native ?? service;
    native?.addListener(this);
    ref.onDispose(() => native?.removeListener(this));
    if (native != null) {
      unawaited(
        native
            .getRequestState()
            .then((value) {
              if (ref.mounted) onRequestState(value);
            })
            .catchError((Object error) {}),
      );
    }
    return const {};
  }

  @override
  void onRequestState(Map<String, Object?> state) {
    if (!ref.mounted) return;
    final previous = this.state;
    if (previous['processEpoch'] == state['processEpoch'] &&
        (previous['revision'] as int? ?? -1) >=
            (state['revision'] as int? ?? 0)) {
      return;
    }
    this.state = Map.unmodifiable(state);
  }
}
