import 'dart:async';

import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core.dart';
import 'request_state.dart';

final configStateProvider = NotifierProvider<ConfigState, ConfigViewState>(
  ConfigState.new,
);

class ConfigViewState {
  const ConfigViewState({
    this.fact = const ConfigFact(),
    this.buildFailed = false,
  });
  final ConfigFact fact;
  final bool buildFailed;
}

class ConfigState extends Notifier<ConfigViewState> with CoreEventListener {
  int _refreshSequence = 0;
  @override
  ConfigViewState build() {
    coreEventManager.addListener(this);
    ref.onDispose(() => coreEventManager.removeListener(this));
    ref.listen(nativeRequestStateProvider, (_, _) => unawaited(refresh()));
    unawaited(refresh());
    return const ConfigViewState();
  }

  Future<void> refresh() async {
    final sequence = ++_refreshSequence;
    try {
      final fact = await ref.read(coreHandlerProvider).getConfigState();
      if (ref.mounted && sequence == _refreshSequence) {
        accept(fact, authoritative: true);
      }
    } catch (_) {
      if (ref.mounted && sequence == _refreshSequence) {
        state = const ConfigViewState();
      }
    }
  }

  void accept(ConfigFact fact, {bool authoritative = false}) {
    if (!ref.mounted || fact.runtimeEpoch.isEmpty) return;
    if (!authoritative &&
        state.fact.runtimeEpoch.isNotEmpty &&
        state.fact.runtimeEpoch != fact.runtimeEpoch) {
      return;
    }
    if (state.fact.runtimeEpoch == fact.runtimeEpoch &&
        state.fact.version > fact.version) {
      return;
    }
    state = ConfigViewState(
      fact: fact,
      buildFailed: state.buildFailed && state.fact.token == fact.token,
    );
  }

  void markBuildFailure() {
    state = ConfigViewState(fact: state.fact, buildFailed: true);
  }

  @override
  void onConfigState(ConfigFact fact) => accept(fact);

  @override
  void onCrash(String message) {
    _refreshSequence++;
    state = const ConfigViewState();
  }
}
