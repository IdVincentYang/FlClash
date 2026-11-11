import 'dart:async';

import 'package:fl_clash/common/android_service_state.dart';
import 'package:fl_clash/common/application_activity.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'action.dart';
import 'app.dart';
import 'config_state.dart';
import 'core.dart';
import 'request_state.dart';

final applicationActivityProvider =
    NotifierProvider<ApplicationActivity, ApplicationActivityState>(
      ApplicationActivity.new,
    );

class ApplicationActivity extends Notifier<ApplicationActivityState>
    with CoreEventListener {
  final _store = ApplicationActivityStore();
  Timer? _pollTimer, _publishTimer;
  int _generation = 0;
  bool _polling = false;
  bool _ready = false;
  bool _listening = false;
  Object? _context;

  @override
  ApplicationActivityState build() {
    ref.onDispose(() {
      coreEventManager.removeListener(this);
      _pollTimer?.cancel();
      _publishTimer?.cancel();
    });
    ref.listen(initProvider, (_, ready) => _setReady(ready));
    ref.listen(appVisibleProvider, (_, visible) {
      if (!visible && _store.snapshot().observing) {
        _store.markUncertain(interrupted: true);
      }
      _generation++;
      _pollTimer?.cancel();
      _publish();
      if (visible) unawaited(refresh());
    });
    scheduleMicrotask(() {
      if (ref.mounted) _setReady(ref.read(initProvider));
    });
    return const ApplicationActivityState();
  }

  void _setReady(bool ready) {
    if (!ref.mounted || _ready == ready) return;
    _ready = ready;
    if (!ready) {
      _generation++;
      _pollTimer?.cancel();
      _store.setContext(
        _store.runtimeEpoch,
        observing: false,
        now: DateTime.now(),
      );
      _publish();
      return;
    }
    if (!_listening) {
      _listening = true;
      coreEventManager.addListener(this);
      ref.listen(configStateProvider, (_, _) => _syncContext());
      ref.listen(nativeRequestStateProvider, (_, _) => _syncContext());
    }
    _syncContext();
  }

  void _syncContext() {
    if (!ref.mounted || !_ready) return;
    final fact = ref.read(configStateProvider).fact;
    final native = ref.read(nativeRequestStateProvider);
    final observing =
        androidServiceStatus(native, fact) == AndroidServiceStatus.vpnActive;
    final context = (
      fact.runtimeEpoch,
      native['serviceId'],
      native['protectGeneration'],
      observing,
    );
    if (context == _context) return;
    if (_context != null &&
        fact.runtimeEpoch == _store.runtimeEpoch &&
        (_store.snapshot().observing || observing)) {
      _store.markUncertain(interrupted: true);
    }
    _context = context;
    _generation++;
    _pollTimer?.cancel();
    _store.setContext(
      fact.runtimeEpoch,
      observing: observing,
      now: DateTime.now(),
    );
    if (observing) {
      for (final info in ref.read(requestsProvider).list) {
        _store.addEvent(info);
      }
    }
    _publish();
    if (observing && ref.read(appVisibleProvider)) unawaited(refresh());
  }

  void _publish() {
    if (!ref.mounted) return;
    _publishTimer?.cancel();
    _publishTimer = null;
    state = _store.snapshot();
  }

  @override
  void onRequest(TrackerInfo connection) {
    if (!ref.mounted) return;
    _store.addEvent(connection);
    _publishTimer ??= Timer(const Duration(milliseconds: 200), _publish);
  }

  Future<void> refresh() async {
    if (_polling ||
        !ref.mounted ||
        !ref.read(appVisibleProvider) ||
        !_store.snapshot().observing) {
      return;
    }
    _pollTimer?.cancel();
    _polling = true;
    final generation = _generation;
    final revision = _store.revision;
    try {
      final connections = await ref
          .read(coreHandlerProvider)
          .getConnections()
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted || generation != _generation) return;
      _store.applySnapshot(
        connections,
        startedRevision: revision,
        now: DateTime.now(),
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        _store.markUncertain(failed: true);
      }
    } finally {
      _polling = false;
      if (ref.mounted) {
        _publish();
        if (ref.read(appVisibleProvider) && _store.snapshot().observing) {
          _pollTimer = Timer(
            const Duration(seconds: 2),
            () => unawaited(refresh()),
          );
        }
      }
    }
  }

  void clear() {
    _generation++;
    _store.clear(DateTime.now());
    _publish();
  }
}

class ApplicationCatalogue {
  const ApplicationCatalogue({
    required this.packages,
    required this.accessible,
  });
  final List<Package> packages;
  final bool accessible;
}

final applicationCatalogueProvider = FutureProvider<ApplicationCatalogue>((
  ref,
) async {
  final cached = ref.watch(
    packagesProvider.select((value) => value.isEmpty ? null : value),
  );
  if (cached != null) {
    return ApplicationCatalogue(packages: cached, accessible: true);
  }
  final action = ref.read(systemActionProvider.notifier);
  final packages = await action.getPackages();
  final accessible =
      packages.isNotEmpty || await action.isInstalledAppsPermissionGranted();
  return ApplicationCatalogue(packages: packages, accessible: accessible);
});
