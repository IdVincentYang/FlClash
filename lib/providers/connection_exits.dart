import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config_state.dart';
import 'package:fl_clash/common/connection_address.dart';
import 'core.dart';
import 'routed_probe.dart';
import 'route_state.dart';

@immutable
class ConnectionExitTarget {
  const ConnectionExitTarget(this.node, this.entry, this.configuration);
  final String node, entry, configuration;
  @override
  bool operator ==(Object other) =>
      other is ConnectionExitTarget &&
      node == other.node &&
      entry == other.entry &&
      configuration == other.configuration;
  @override
  int get hashCode => Object.hash(node, entry, configuration);
}

ConnectionExitTarget? connectionExitTarget(
  TrackerInfo info,
  String configuration,
) {
  if (configuration.isEmpty ||
      info.observation?.configuration.status != 'known' ||
      info.observation?.configuration.inputId != configuration ||
      info.chains.isEmpty ||
      const {
        'DIRECT',
        'COMPATIBLE',
        'REJECT',
        'REJECT-DROP',
        'PASS',
      }.contains(info.chains.first.toUpperCase())) {
    return null;
  }
  return ConnectionExitTarget(
    info.chains.first,
    connectionProxyServerIp(info) ?? '',
    configuration,
  );
}

@immutable
class ConnectionExitEntry {
  const ConnectionExitEntry(
    this.phase, {
    this.value,
    this.reason,
    this.completed,
  });
  final ProbePhase phase;
  final IpInfo? value;
  final String? reason;
  final Duration? completed;
  ConnectionExitEntry.pending(this.phase, ConnectionExitEntry? previous)
    : value = previous?.value,
      reason = previous?.reason,
      completed = previous?.completed;

  bool get busy => phase == ProbePhase.queued || phase == ProbePhase.probing;
}

enum ExitRefreshResult { accepted, coalesced, throttled, unavailable }

final connectionExitsProvider =
    NotifierProvider<
      ConnectionExits,
      Map<ConnectionExitTarget, ConnectionExitEntry>
    >(ConnectionExits.new);

class ConnectionExits
    extends Notifier<Map<ConnectionExitTarget, ConnectionExitEntry>> {
  static const cacheAge = Duration(minutes: 10);
  static const failureAge = Duration(minutes: 1);
  static const manualInterval = Duration(seconds: 5);
  static const startInterval = Duration(seconds: 1);
  static const cacheLimit = 256;
  final _clock = Stopwatch()..start();
  final _watchers = <ConnectionExitTarget, int>{};
  final _automatic = <ConnectionExitTarget, int>{};
  final _queue = <ConnectionExitTarget>{};
  final _manual = <ConnectionExitTarget>{};
  final _lastStart = <ConnectionExitTarget, Duration>{};
  ConnectionExitTarget? _running;
  int _sequence = 0;
  Duration? _lastLaunch;
  Timer? _wake;
  bool _scheduled = false, _holdingRoute = false;
  late RouteTracker _tracker;
  RouteState _route = const RouteState();

  @protected
  Request get requestClient => request;
  @protected
  Duration get elapsed => _clock.elapsed;

  @override
  Map<ConnectionExitTarget, ConnectionExitEntry> build() {
    _tracker = ref.read(routeTrackerProvider.notifier);
    _route = ref.read(routeTrackerProvider);
    ref.listen(routeTrackerProvider, (previous, next) {
      final changed =
          previous != null &&
          (previous.coreEpoch != next.coreEpoch ||
              previous.hostEpoch != next.hostEpoch ||
              previous.proxied != next.proxied);
      _route = next;
      if (changed) {
        _invalidate();
      } else if (!next.live) {
        _cancelWork();
      }
      _schedule();
    });
    ref.listen(
      configStateProvider.select((value) => value.fact.inputId),
      (_, _) => _invalidate(),
    );
    ref.listen(groupsProvider, (_, _) => _schedule());
    ref.listen(appVisibleProvider, (_, visible) {
      if (!visible) _cancelWork();
      _schedule();
    });
    ref.onDispose(() {
      _wake?.cancel();
      _clock.stop();
      if (_running case final target?) {
        requestClient.cancelKey(_requestKey(target));
      }
      if (_holdingRoute) scheduleMicrotask(_tracker.detach);
    });
    return const {};
  }

  bool _current(ConnectionExitTarget target) =>
      ref.read(configStateProvider).fact.inputId == target.configuration &&
      localGroupNodes(
        ref.read(groupsProvider),
      ).any((node) => node.name == target.node);
  bool get _available =>
      ref.read(appVisibleProvider) &&
      ref.read(initProvider) &&
      _route.live &&
      _route.proxied;
  bool _fresh(ConnectionExitEntry? entry) =>
      entry?.completed != null &&
      elapsed - entry!.completed! <
          (entry.value == null ? failureAge : cacheAge);
  bool isExpired(ConnectionExitTarget target) => !_fresh(state[target]);
  String _requestKey(ConnectionExitTarget target) =>
      'connectionExit:${jsonEncode([target.node, target.entry, target.configuration])}';

  void watch(ConnectionExitTarget target, {required bool automatic}) {
    if (!ref.mounted) return;
    _watchers[target] = (_watchers[target] ?? 0) + 1;
    if (automatic) _automatic[target] = (_automatic[target] ?? 0) + 1;
    if (!_holdingRoute) {
      _holdingRoute = true;
      _tracker.attach();
    }
    _schedule();
  }

  void unwatch(ConnectionExitTarget target, {required bool automatic}) {
    if (!ref.mounted) return;
    void remove(Map<ConnectionExitTarget, int> values) {
      final count = values[target] ?? 0;
      if (count <= 1) {
        values.remove(target);
      } else {
        values[target] = count - 1;
      }
    }

    remove(_watchers);
    if (automatic) remove(_automatic);
    if (!_watchers.containsKey(target)) {
      _queue.remove(target);
      _manual.remove(target);
      if (_running == target) {
        _sequence++;
        _running = null;
        requestClient.cancelKey(_requestKey(target));
      }
      final entry = state[target];
      if (entry?.busy == true) _restore(target);
    }
    if (_watchers.isEmpty && _holdingRoute) {
      _holdingRoute = false;
      _tracker.detach();
    }
    _schedule();
  }

  ExitRefreshResult refresh(ConnectionExitTarget target) {
    if (!ref.mounted ||
        !_available ||
        !_current(target) ||
        !_watchers.containsKey(target)) {
      return ExitRefreshResult.unavailable;
    }
    if (_running == target) return ExitRefreshResult.coalesced;
    final last = _lastStart[target];
    if (last != null && elapsed - last < manualInterval) {
      return ExitRefreshResult.throttled;
    }
    _manual.add(target);
    _queue.add(target);
    state = {
      ...state,
      target: ConnectionExitEntry.pending(ProbePhase.queued, state[target]),
    };
    _schedule();
    return ExitRefreshResult.accepted;
  }

  ConnectionExitEntry? _retained(ConnectionExitEntry entry) =>
      entry.completed == null
      ? null
      : ConnectionExitEntry(
          entry.value == null ? ProbePhase.failed : ProbePhase.fresh,
          value: entry.value,
          reason: entry.reason,
          completed: entry.completed,
        );

  void _restore(ConnectionExitTarget target) {
    final entry = state[target];
    final keep = entry == null ? null : _retained(entry);
    final next = {...state}..remove(target);
    if (keep != null) next[target] = keep;
    state = next;
  }

  void _discard(ConnectionExitTarget target, int sequence) {
    if (!ref.mounted || _sequence != sequence || _running != target) return;
    _running = null;
    _restore(target);
    _schedule();
  }

  void _cancelWork() {
    _wake?.cancel();
    _queue.clear();
    _manual.clear();
    _sequence++;
    if (_running case final target?) {
      requestClient.cancelKey(_requestKey(target));
    }
    _running = null;
    final kept = <ConnectionExitTarget, ConnectionExitEntry>{};
    for (final entry in state.entries) {
      final value = entry.value.busy ? _retained(entry.value) : entry.value;
      if (value != null) kept[entry.key] = value;
    }
    state = kept;
  }

  void _invalidate() {
    _cancelWork();
    state = const {};
    _lastStart.clear();
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !ref.mounted) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (ref.mounted) _pump();
    });
  }

  void _pump() {
    _wake?.cancel();
    if (!_available) return;
    if (_running case final target? when !_current(target)) {
      requestClient.cancelKey(_requestKey(target));
      _discard(target, _sequence);
    }
    for (final target in _automatic.keys) {
      if (_watchers.containsKey(target) &&
          _current(target) &&
          !_fresh(state[target]) &&
          _running != target &&
          _queue.add(target)) {
        state = {
          ...state,
          target: ConnectionExitEntry.pending(ProbePhase.queued, state[target]),
        };
      }
    }
    _queue.removeWhere((target) {
      final removed = !_watchers.containsKey(target) || !_current(target);
      if (removed) _manual.remove(target);
      return removed;
    });
    if (_running != null) return;
    if (_queue.isNotEmpty) {
      final remaining = _lastLaunch == null
          ? Duration.zero
          : startInterval - (elapsed - _lastLaunch!);
      if (remaining > Duration.zero) {
        _wake = Timer(remaining, _schedule);
        return;
      }
      ConnectionExitTarget? target;
      Duration? retry;
      for (final candidate in _queue) {
        final last = _lastStart[candidate];
        final left = last == null
            ? Duration.zero
            : manualInterval - (elapsed - last);
        if (left <= Duration.zero) {
          target = candidate;
          break;
        }
        if (retry == null || left < retry) retry = left;
      }
      if (target == null) {
        _wake = Timer(retry ?? startInterval, _schedule);
        return;
      }
      _queue.remove(target);
      _running = target;
      _lastLaunch = elapsed;
      _lastStart[target] = elapsed;
      state = {
        ...state,
        target: ConnectionExitEntry.pending(ProbePhase.probing, state[target]),
      };
      unawaited(
        _run(target, ++_sequence, _route, manual: _manual.remove(target)),
      );
      return;
    }
    Duration? wake;
    for (final target in _automatic.keys) {
      final entry = state[target];
      if (!_current(target) || entry?.completed == null) continue;
      final remaining =
          (entry!.phase == ProbePhase.failed ? failureAge : cacheAge) -
          (elapsed - entry.completed!);
      if (remaining > Duration.zero && (wake == null || remaining < wake)) {
        wake = remaining;
      }
    }
    if (wake != null) _wake = Timer(wake, _schedule);
    if (_lastStart.length > cacheLimit) {
      for (final target in _lastStart.keys.toList()) {
        if (_lastStart.length <= cacheLimit) break;
        if (!_watchers.containsKey(target)) _lastStart.remove(target);
      }
    }
    if (state.length > cacheLimit) {
      final keep = {...state};
      for (final target in state.keys) {
        if (keep.length <= cacheLimit) break;
        if (!_watchers.containsKey(target)) {
          keep.remove(target);
          _lastStart.remove(target);
        }
      }
      state = keep;
    }
  }

  Future<void> _run(
    ConnectionExitTarget target,
    int sequence,
    RouteState route, {
    required bool manual,
  }) async {
    IpInfo? value;
    String? reason;
    bool current() =>
        ref.mounted &&
        _sequence == sequence &&
        _running == target &&
        _available &&
        _current(target) &&
        _watchers.containsKey(target) &&
        _route.coreEpoch == route.coreEpoch &&
        _route.hostEpoch == route.hostEpoch;
    try {
      final result = await withIpSession(
        client: requestClient,
        key: _requestKey(target),
        url: outboundIpUrl,
        timeout: const Duration(seconds: 6),
        automatic: !manual,
        explicitTarget: target.node,
        current: current,
        action: (_, remaining) => lookupOutboundIp(
          ref.read(coreHandlerProvider),
          target.node,
          timeout: remaining,
        ),
      );
      if (!current()) {
        _discard(target, sequence);
        return;
      }
      final stamp = RouteStamp(
        coreEpoch: result?.coreEpoch ?? -1,
        picksVersion: result?.picksVersion ?? -1,
        hostEpoch: route.hostEpoch,
        proxied: route.proxied,
        chains: result?.chains ?? const [],
      );
      if (result?.error != null) {
        reason = result!.error;
      } else if (result == null ||
          result.chains.isEmpty ||
          result.chains.first != target.node ||
          !_route.isFresh(stamp)) {
        reason = 'route-changed';
      } else {
        value = parseOutboundIp(result);
        reason = value == null ? result.error ?? 'invalid-response' : null;
      }
    } catch (_) {
      reason = 'probe-failed';
    }
    if (!current()) {
      _discard(target, sequence);
      return;
    }
    _running = null;
    state = {
      ...state,
      target: ConnectionExitEntry(
        value == null ? ProbePhase.failed : ProbePhase.fresh,
        value: value,
        reason: reason,
        completed: elapsed,
      ),
    };
    _schedule();
  }
}
