import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/method.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';

import 'app.dart';
import 'route_state.dart';

enum ProbePhase { empty, queued, probing, fresh, failed }

class ProbeSchedule {
  const ProbeSchedule({required this.minimumInterval, required this.maxAge});
  final Duration minimumInterval;
  final Duration maxAge;
}

@immutable
class ProbeEntry<V> {
  const ProbeEntry({
    required this.phase,
    this.value,
    this.stamp,
    this.expired = false,
    this.reason,
  });

  final ProbePhase phase;
  final V? value;
  final RouteStamp? stamp;
  final bool expired;
  final String? reason;

  bool get isLoading =>
      phase == ProbePhase.probing || phase == ProbePhase.queued;

  @override
  bool operator ==(Object other) =>
      other is ProbeEntry<V> &&
      other.phase == phase &&
      other.value == value &&
      other.stamp == stamp &&
      other.expired == expired &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(phase, value, stamp, expired, reason);
}

@immutable
class RoutedProbeState<K, V> {
  const RoutedProbeState([this.entries = const {}]);

  final Map<K, ProbeEntry<V>> entries;

  ProbeEntry<V> entryOf(K target) =>
      entries[target] ?? ProbeEntry<V>(phase: ProbePhase.empty);

  V? valueOf(K target) => entries[target]?.value;

  bool isLoading(K target) => entryOf(target).isLoading;

  @override
  bool operator ==(Object other) =>
      other is RoutedProbeState<K, V> && mapEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAllUnordered(
    entries.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// One probe answer before it is stamped. The counters are the Core's at
/// launch and stay null when the Core gave no answer at all.
class ProbeAnswer<V> {
  const ProbeAnswer({
    this.value,
    this.reason,
    this.coreEpoch,
    this.picksVersion,
    this.chains = const [],
  });

  final V? value;
  final String? reason;
  final int? coreEpoch;
  final int? picksVersion;
  final List<String> chains;
}

/// Keeps one answer per target and only ever shows one that still describes
/// the current route. State changes are deferred to a microtask, so a widget
/// may watch a target from its build.
mixin RoutedProbe<K, V>
    on AnyNotifier<RoutedProbeState<K, V>, RoutedProbeState<K, V>> {
  final Map<K, int> _watchers = {};
  final Map<K, int> _automaticWatchers = {};
  final Map<K, Duration> _launchedAt = {};
  final Map<K, Duration> _completedAt = {};
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _wake;
  bool _routeHeld = false;
  late RouteTracker _tracker;

  @protected
  Duration get monotonicElapsed => _clock.elapsed;

  @protected
  ProbeSchedule? get probeSchedule => null;

  @protected
  bool get waitsForRoute => true;

  @protected
  bool get sharedInterval => false;

  Duration? _lastLaunch(K target) =>
      sharedInterval ? _sourceLaunchedAt : _launchedAt[target];
  Duration? _sourceLaunchedAt;

  @protected
  bool Function() captureProbeGuard(K target) {
    final run = _inFlight[target]?.id;
    return () =>
        run != null &&
        ref.mounted &&
        _inFlight[target]?.id == run &&
        isEligible(target) &&
        _route.live &&
        ref.read(appVisibleProvider);
  }

  @protected
  bool isEligible(K target) => true;

  @protected
  bool isManualProbe(K target) =>
      _inFlight[target]?.forced == true || _due[target]?.forced == true;

  @protected
  bool allowsAutomatic(K target) => true;

  @protected
  bool cancelManualOnUnwatch(K target) => !allowsAutomatic(target);

  bool _automatic(K target) =>
      (_automaticWatchers[target] ?? 0) > 0 &&
      allowsAutomatic(target) &&
      isEligible(target);

  bool _expired(K target) {
    final completed = _completedAt[target];
    final schedule = probeSchedule;
    return schedule != null &&
        completed != null &&
        monotonicElapsed - completed >= schedule.maxAge;
  }

  void _holdRoute() {
    final wanted =
        _watchers.keys.any(isEligible) ||
        probeSchedule != null && (_due.isNotEmpty || _inFlight.isNotEmpty);
    if (wanted == _routeHeld || !ref.mounted) return;
    _routeHeld = wanted;
    if (wanted) {
      _tracker.attach();
    } else {
      _tracker.detach();
    }
  }

  void _armWake() {
    _wake?.cancel();
    _wake = null;
    final schedule = probeSchedule;
    if (schedule == null || !ref.mounted || !ref.read(appVisibleProvider)) {
      return;
    }
    Duration? next;
    void consider(Duration value) {
      if (next == null || value < next!) next = value;
    }

    for (final target in _due.keys) {
      if (!isEligible(target)) continue;
      final last = _lastLaunch(target);
      if (last != null) {
        final left = schedule.minimumInterval - (monotonicElapsed - last);
        if (left > Duration.zero) consider(left);
      }
    }
    for (final target in _watchers.keys) {
      final completed = _completedAt[target];
      if (!isEligible(target) || completed == null || _expired(target)) {
        continue;
      }
      consider(schedule.maxAge - (monotonicElapsed - completed));
    }
    if (next != null) _wake = Timer(next!, _onWake);
  }

  void _onWake() {
    if (!ref.mounted) return;
    final entries = Map<K, ProbeEntry<V>>.of(state.entries);
    for (final target in _watchers.keys) {
      if (!isEligible(target) || !_expired(target)) continue;
      final entry = entries[target];
      if (entry != null) {
        entries[target] = ProbeEntry(
          phase: entry.phase,
          value: entry.value,
          stamp: entry.stamp,
          expired: true,
        );
      }
      if (_automatic(target) && !_inFlight.containsKey(target)) {
        _mark(target, keepValue: true);
      }
    }
    state = RoutedProbeState(entries);
    if (_due.isNotEmpty) _schedule();
    _armWake();
  }

  void cancel(Iterable<K> targets) {
    if (!ref.mounted) return;
    final entries = Map<K, ProbeEntry<V>>.of(state.entries);
    for (final target in targets.toList()) {
      _due.remove(target);
      _inFlight.remove(target);
      _completedAt.remove(target);
      _staleUnder.remove(target);
      cancelProbe(target);
      entries.remove(target);
    }
    state = RoutedProbeState(entries);
    _holdRoute();
    _armWake();
  }

  @protected
  void reconcileEligibility() {
    if (!ref.mounted) return;
    cancel(
      {
        ..._due.keys,
        ..._inFlight.keys,
        ...state.entries.keys,
      }.where((target) => !isEligible(target)),
    );
    for (final target in _watchers.keys) {
      if (_automatic(target) &&
          (_entryOf(target).phase != ProbePhase.fresh || _expired(target))) {
        _mark(target);
      }
    }
    _holdRoute();
  }

  final Map<K, ({bool keepValue, bool forced, bool supersede})> _due = {};
  final Map<K, ({int id, bool forced})> _inFlight = {};
  int _runs = 0;
  final Map<K, RouteState> _staleUnder = {};
  bool _scheduled = false;
  RouteState _route = const RouteState();

  /// May also answer targets it was not asked for; a fresh one of those is
  /// taken in place of its own lookup.
  @protected
  Future<Map<K, ProbeAnswer<V>>> probe(K target, RouteState route);

  @protected
  void cancelProbe(K target) {}

  @protected
  bool isFailure(V value) => false;

  @protected
  RoutedProbeState<K, V> buildProbe() {
    _clock.start();
    _tracker = ref.read(routeTrackerProvider.notifier);
    final tracker = _tracker;
    ref.onDispose(() {
      _wake?.cancel();
      _wake = null;
      _clock.stop();
      if (_routeHeld) scheduleMicrotask(tracker.detach);
      _routeHeld = false;
      for (final target in _inFlight.keys.toList()) {
        cancelProbe(target);
      }
      _inFlight.clear();
      _due.clear();
      _completedAt.clear();
      _staleUnder.clear();
    });
    _route = ref.read(routeTrackerProvider);
    ref.listen(routeTrackerProvider, _onRoute);
    ref.listen(appVisibleProvider, (_, visible) {
      if (!visible && probeSchedule != null) {
        _wake?.cancel();
        cancel({..._due.keys, ..._inFlight.keys});
      } else if (!visible) {
        final entries = Map<K, ProbeEntry<V>>.of(state.entries);
        for (final target in _inFlight.keys.toList()) {
          _inFlight.remove(target);
          _invalidate(target, entries);
        }
        state = RoutedProbeState(entries);
      }
      if (visible) {
        if (probeSchedule != null) {
          _onWake();
          for (final target in _watchers.keys) {
            if (_automatic(target) &&
                (_entryOf(target).phase != ProbePhase.fresh ||
                    _expired(target))) {
              _mark(target, keepValue: true);
            }
          }
        }
        if (_due.isNotEmpty) _schedule();
        _armWake();
      }
    });
    scheduleMicrotask(() {
      if (!ref.mounted) return;
      _holdRoute();
      _armWake();
    });
    return RoutedProbeState<K, V>();
  }

  void watch(K target, {bool automatic = true}) {
    final wasAutomatic = _automatic(target);
    _watchers[target] = (_watchers[target] ?? 0) + 1;
    if (automatic) {
      _automaticWatchers[target] = (_automaticWatchers[target] ?? 0) + 1;
    }
    _holdRoute();
    if (automatic &&
        !wasAutomatic &&
        _automatic(target) &&
        (_entryOf(target).phase != ProbePhase.fresh || _expired(target))) {
      _mark(target);
    }
    if (_expired(target)) {
      scheduleMicrotask(() {
        if (ref.mounted) _onWake();
      });
    }
    _armWake();
  }

  void unwatch(K target, {bool automatic = true}) {
    if (!ref.mounted) return;
    final count = _watchers[target];
    if (count == null) return;
    if (automatic) {
      final count = _automaticWatchers[target] ?? 0;
      if (count <= 1) {
        _automaticWatchers.remove(target);
      } else {
        _automaticWatchers[target] = count - 1;
      }
    }
    if (count > 1) {
      _watchers[target] = count - 1;
    } else {
      _watchers.remove(target);
    }
    if (probeSchedule == null) {
      if (!_watchers.containsKey(target)) cancelProbe(target);
    } else {
      final closed =
          cancelManualOnUnwatch(target) && !_watchers.containsKey(target);
      final run = _inFlight[target];
      if (closed || run != null && !run.forced && !_automatic(target)) {
        _inFlight.remove(target);
        cancelProbe(target);
        scheduleMicrotask(() => _forget(target));
      }
      if (closed) {
        _due.remove(target);
      }
    }
    final due = _due[target];
    if (due != null && !due.forced && !_automatic(target)) {
      _due.remove(target);
      scheduleMicrotask(() => _forget(target));
    }
    _holdRoute();
    _armWake();
  }

  /// A re-probe dropped before it launched would leave its entry loading
  /// with nothing left to settle it.
  void _forget(K target) {
    if (!ref.mounted ||
        _automatic(target) ||
        _due.containsKey(target) ||
        _inFlight.containsKey(target) ||
        !_entryOf(target).isLoading) {
      return;
    }
    _completedAt.remove(target);
    state = RoutedProbeState(Map.of(state.entries)..remove(target));
  }

  void retry(K target) {
    if (_entryOf(target).phase == ProbePhase.failed) {
      _mark(target);
    }
  }

  /// A refresh is the user asking, so it runs for targets nobody watches
  /// too; the answer lands in the cache and stays until the route moves.
  void refresh(Iterable<K> targets) {
    for (final target in targets) {
      _mark(target, keepValue: true, forced: true);
    }
  }

  ProbeEntry<V> _entryOf(K target) => state.entryOf(target);

  void _mark(K target, {bool keepValue = false, bool forced = false}) {
    if (probeSchedule != null && !ref.read(appVisibleProvider)) return;
    if (!isEligible(target) || !forced && !_automatic(target)) {
      return;
    }
    final run = _inFlight[target];
    if (run != null) {
      if (forced) _inFlight[target] = (id: run.id, forced: true);
      return;
    }
    final previous = _due[target];
    _due[target] = (
      keepValue: keepValue || (previous?.keepValue ?? false),
      forced: forced || (previous?.forced ?? false),
      supersede: previous?.supersede ?? false,
    );
    _holdRoute();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    scheduleMicrotask(_launch);
  }

  void _launch() {
    _scheduled = false;
    if (!ref.mounted) return;
    if (!_route.live || !ref.read(appVisibleProvider)) {
      if (probeSchedule != null && ref.read(appVisibleProvider)) {
        final entries = Map<K, ProbeEntry<V>>.of(state.entries);
        for (final target in _due.keys.where(isEligible)) {
          entries[target] = ProbeEntry(
            phase: waitsForRoute ? ProbePhase.queued : ProbePhase.failed,
            reason: waitsForRoute ? null : 'route-unavailable',
          );
        }
        state = RoutedProbeState(entries);
        if (!waitsForRoute) {
          _due.clear();
          _holdRoute();
          _armWake();
        }
      }
      return;
    }
    final route = _route;
    final targets = <K, bool>{};
    final entries = Map<K, ProbeEntry<V>>.of(state.entries);
    final waiting = <K, ({bool keepValue, bool forced, bool supersede})>{};
    for (final MapEntry(key: target, value: due) in _due.entries) {
      final wanted = isEligible(target) && (due.forced || _automatic(target));
      if (!wanted || (_inFlight.containsKey(target) && !due.supersede)) {
        continue;
      }
      final last = sharedInterval && targets.isNotEmpty
          ? monotonicElapsed
          : _lastLaunch(target);
      final interval = probeSchedule?.minimumInterval ?? Duration.zero;
      if (last != null && monotonicElapsed - last < interval) {
        waiting[target] = due;
        entries[target] = ProbeEntry(
          phase: ProbePhase.queued,
          value: due.keepValue ? entries[target]?.value : null,
          stamp: due.keepValue ? entries[target]?.stamp : null,
          expired: entries[target]?.expired ?? false,
        );
        continue;
      }
      targets[target] = due.forced;
      entries[target] = ProbeEntry(
        phase: ProbePhase.probing,
        value: due.keepValue ? entries[target]?.value : null,
        expired: entries[target]?.expired ?? false,
      );
    }
    _due
      ..clear()
      ..addAll(waiting);
    state = RoutedProbeState(entries);
    _armWake();
    if (targets.isEmpty) {
      _holdRoute();
      return;
    }
    final run = ++_runs;
    for (final MapEntry(key: target, value: forced) in targets.entries) {
      _inFlight[target] = (id: run, forced: forced);
      if (sharedInterval) {
        _sourceLaunchedAt = monotonicElapsed;
      } else {
        _launchedAt[target] = monotonicElapsed;
      }
    }
    _holdRoute();
    _armWake();
    for (final target in targets.keys) {
      unawaited(_run(target, route, run));
    }
  }

  /// A target a newer route asked again belongs to that run from then on.
  Future<void> _run(K target, RouteState route, int run) async {
    var answers = <K, ProbeAnswer<V>>{};
    try {
      answers = await probe(target, route);
    } catch (error) {
      commonPrint.log(
        probeSchedule == null
            ? 'probe failed: $error'
            : 'service probe incomplete',
        logLevel: coreFailureLogLevel(error),
      );
    }
    if (!ref.mounted ||
        _inFlight[target]?.id != run ||
        !isEligible(target) ||
        !ref.read(appVisibleProvider) ||
        !_route.live) {
      return;
    }
    _inFlight.remove(target);
    _completedAt[target] = monotonicElapsed;
    final current = _route;
    final entries = Map<K, ProbeEntry<V>>.of(state.entries);
    final answer = answers[target] ?? const ProbeAnswer();
    final stamp = _stampOf(answer, route);
    final fresh = current.isFresh(stamp);
    final behind = !fresh && current.isBehind(stamp);
    if (!fresh) {
      // Stale twice under one route: the Core and host disagree, stop asking.
      if (_staleUnder[target] != current) {
        _staleUnder[target] = current;
        _invalidate(target, entries);
      } else if (_watchers.containsKey(target)) {
        entries[target] = ProbeEntry(phase: ProbePhase.failed, stamp: stamp);
      } else {
        entries.remove(target);
      }
    } else {
      _staleUnder.remove(target);
      final value = answer.value;
      final failed = value == null || isFailure(value);
      entries[target] = ProbeEntry(
        phase: failed ? ProbePhase.failed : ProbePhase.fresh,
        reason: answer.reason,
        value: value,
        stamp: stamp,
      );
    }
    for (final MapEntry(key: other, value: answer) in answers.entries) {
      final value = answer.value;
      if (!isEligible(other) ||
          other == target ||
          value == null ||
          isFailure(value)) {
        continue;
      }
      final stamp = _stampOf(answer, route);
      if (!current.isFresh(stamp)) {
        continue;
      }
      _inFlight.remove(other);
      _due.remove(other);
      entries[other] = ProbeEntry(
        phase: ProbePhase.fresh,
        value: value,
        stamp: stamp,
      );
    }
    state = RoutedProbeState(entries);
    if (behind) {
      ref.read(routeTrackerProvider.notifier).resync();
    }
    if (_due.isNotEmpty) _schedule();
    _holdRoute();
    _armWake();
  }

  RouteStamp _stampOf(ProbeAnswer<V> answer, RouteState route) => RouteStamp(
    coreEpoch: answer.coreEpoch ?? route.coreEpoch,
    picksVersion: answer.picksVersion ?? route.picksVersion,
    hostEpoch: route.hostEpoch,
    proxied: route.proxied,
    chains: answer.chains,
  );

  void _onRoute(RouteState? previous, RouteState next) {
    _route = next;
    final entries = Map<K, ProbeEntry<V>>.of(state.entries);
    final resumed = previous != null && next.resumes != previous.resumes;
    // Picks flip whenever any url-test or fallback group re-picks, often
    // faster than a probe finishes; restarting on them would never let one
    // land. An answer's chain tells when it went through a group that moved.
    final moved =
        previous != null &&
        (next.coreEpoch != previous.coreEpoch ||
            next.hostEpoch != previous.hostEpoch ||
            next.proxied != previous.proxied ||
            !next.live);
    for (final MapEntry(key: target, value: entry) in state.entries.entries) {
      final picksMoved =
          previous != null && next.picksVersion != previous.picksVersion;
      if (probeSchedule != null &&
          !allowsAutomatic(target) &&
          previous?.synced == true &&
          (moved || picksMoved) &&
          (_due.containsKey(target) || _inFlight.containsKey(target))) {
        _invalidate(target, entries);
        continue;
      }
      if (_inFlight.containsKey(target)) {
        if (moved) {
          _invalidate(target, entries);
        }
        continue;
      }
      final stamp = entry.stamp;
      if (stamp == null) {
        continue;
      }
      if (!next.isFresh(stamp)) {
        _invalidate(target, entries);
      } else if (resumed &&
          entry.phase == ProbePhase.failed &&
          _automatic(target)) {
        _due[target] = (keepValue: false, forced: false, supersede: false);
      }
    }
    if (!mapEquals(entries, state.entries)) {
      state = RoutedProbeState(entries);
    }
    if (_due.isNotEmpty) {
      _schedule();
    }
    _holdRoute();
    _armWake();
  }

  /// A stale entry is asked again while someone watches it and forgotten
  /// otherwise; either way its old value is never shown.
  void _invalidate(K target, Map<K, ProbeEntry<V>> entries) {
    cancelProbe(target);
    _inFlight.remove(target);
    if (_automatic(target)) {
      entries[target] = ProbeEntry(phase: ProbePhase.probing);
      _due[target] = (keepValue: false, forced: false, supersede: true);
    } else {
      _inFlight.remove(target);
      _due.remove(target);
      _completedAt.remove(target);
      if (probeSchedule != null && _watchers.containsKey(target)) {
        entries[target] = ProbeEntry(phase: ProbePhase.failed, expired: true);
      } else {
        entries.remove(target);
      }
    }
  }
}
