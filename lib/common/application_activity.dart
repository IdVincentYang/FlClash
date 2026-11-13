import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/common.dart';

class ApplicationActivityStore {
  ApplicationActivityStore({this.capacity = 4096}) : assert(capacity > 0);
  final int capacity;
  final _connections = <String, ActivityConnection>{};
  String _epoch = '';
  DateTime? _since, _clearBefore;
  int _revision = 0;
  bool _observing = false, _hasSnapshot = false, _failed = false;
  bool _interrupted = false, _truncated = false;

  int get revision => _revision;
  String get runtimeEpoch => _epoch;

  void setContext(
    String epoch, {
    required bool observing,
    required DateTime now,
  }) {
    if (epoch.isNotEmpty && epoch != _epoch) {
      _connections.clear();
      _epoch = epoch;
      _since = now;
      _clearBefore = null;
      _hasSnapshot = _failed = _interrupted = _truncated = false;
      _revision++;
    }
    if (_observing && !observing) markUncertain();
    _observing = observing && _epoch.isNotEmpty;
  }

  void markUncertain({bool interrupted = false, bool failed = false}) {
    for (final entry in _connections.entries.toList()) {
      _connections[entry.key] = entry.value.withActive(null);
    }
    _hasSnapshot = false;
    _interrupted |= interrupted;
    _failed |= failed;
  }

  bool _belongs(TrackerInfo info, {required bool snapshot}) {
    if (_isInternal(info)) return false;
    final epoch = info.observation?.runtimeEpoch ?? '';
    if (_epoch.isEmpty || epoch.isNotEmpty && epoch != _epoch) return false;
    if (epoch.isEmpty && !snapshot) {
      _interrupted = true;
      return false;
    }
    return _clearBefore == null || info.start.isAfter(_clearBefore!);
  }

  bool _isInternal(TrackerInfo info) => info.metadata.inboundType == 'Inner';

  void _insert(TrackerInfo info, {required bool snapshot}) {
    if (!_belongs(info, snapshot: snapshot)) return;
    final previous = _connections[info.id];
    if (previous != null) return;
    if (_connections.length == capacity) {
      _connections.remove(_connections.keys.first);
      _truncated = true;
    }
    _connections[info.id] = ActivityConnection(
      info: info,
      activityAt: info.start,
      revision: ++_revision,
      upload: info.upload,
      download: info.download,
    );
  }

  void addEvent(TrackerInfo info) {
    if (!_observing) return;
    _insert(info, snapshot: false);
  }

  void applySnapshot(
    List<TrackerInfo> infos, {
    required int startedRevision,
    required DateTime now,
  }) {
    if (!_observing) return;
    final applicationInfos = infos.where((info) => !_isInternal(info));
    if (applicationInfos.any(
      (item) =>
          item.observation?.runtimeEpoch.isNotEmpty == true &&
          item.observation!.runtimeEpoch != _epoch,
    )) {
      markUncertain(failed: true);
      return;
    }
    final present = <String>{};
    for (final info in applicationInfos) {
      if (!_belongs(info, snapshot: true)) continue;
      present.add(info.id);
      _insert(info, snapshot: true);
      final previous = _connections[info.id];
      if (previous != null) {
        _connections[info.id] = previous.observed(info, now, active: true);
      }
    }
    for (final entry in _connections.entries.toList()) {
      if (!present.contains(entry.key) &&
          entry.value.revision <= startedRevision) {
        _connections[entry.key] = entry.value.withActive(false);
      }
    }
    _hasSnapshot = true;
    _failed = false;
  }

  void clear(DateTime now) {
    _connections.clear();
    _since = _clearBefore = now;
    _hasSnapshot = _failed = _interrupted = _truncated = false;
    _revision++;
  }

  ApplicationActivityState snapshot() => ApplicationActivityState(
    runtimeEpoch: _epoch,
    since: _since,
    connections: List.unmodifiable(_connections.values),
    observing: _observing,
    hasSnapshot: _hasSnapshot,
    snapshotFailed: _failed,
    interrupted: _interrupted,
    truncated: _truncated,
    capacity: capacity,
  );
}
