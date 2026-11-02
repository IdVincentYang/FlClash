import 'dart:async';

import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/common/android_service_state.dart';

import 'config_state.dart';
import 'state.dart';
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

final runControlProvider = Provider<bool>((ref) {
  if (!system.isAndroid) return ref.watch(isStartProvider);
  return androidRunRequested(ref.watch(nativeRequestStateProvider));
});

final androidServiceStatusProvider = Provider<AndroidServiceStatus>((ref) {
  return androidServiceStatus(
    ref.watch(nativeRequestStateProvider),
    ref.watch(configStateProvider).fact,
  );
});
