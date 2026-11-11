import 'dart:convert';

import 'connection_observation.dart';
import 'common.dart';

String applicationActivityKey(ApplicationIdentity identity) {
  final package = identity.packageName;
  if (package != null) return 'package:$package';
  return jsonEncode([
    identity.status,
    identity.userScope,
    identity.uid,
    identity.packages,
  ]);
}

String activityHostKey(TrackerInfo info) {
  final host = info.metadata.host.trim().toLowerCase().replaceFirst(
    RegExp(r'\.$'),
    '',
  );
  if (host.isNotEmpty) return 'host:$host';
  final ip = info.metadata.destinationIP;
  return ip.isEmpty ? 'unknown:' : 'ip:$ip';
}

class ActivityConnection {
  const ActivityConnection({
    required this.info,
    required this.activityAt,
    required this.revision,
    this.active,
    this.upload = 0,
    this.download = 0,
  });

  final TrackerInfo info;
  final DateTime activityAt;
  final int revision, upload, download;
  final bool? active;

  ApplicationIdentity get application =>
      info.observation?.application ?? const ApplicationIdentity();
  String get appKey => applicationActivityKey(application);
  String get hostKey => activityHostKey(info);

  ActivityConnection observed(TrackerInfo next, DateTime at, {bool? active}) =>
      ActivityConnection(
        info: info,
        activityAt: next.upload > upload || next.download > download
            ? at
            : activityAt,
        revision: revision,
        active: active,
        upload: next.upload,
        download: next.download,
      );

  ActivityConnection withActive(bool? active) => ActivityConnection(
    info: info,
    activityAt: activityAt,
    revision: revision,
    active: active,
    upload: upload,
    download: download,
  );
}

class ActivityTotals {
  ActivityTotals(
    Iterable<ActivityConnection> connections, {
    required this.fresh,
  }) : connections = List.unmodifiable(connections);

  final List<ActivityConnection> connections;
  final bool fresh;

  int get connectionCount => connections.length;
  int get confirmedActiveCount =>
      fresh ? connections.where((item) => item.active == true).length : 0;
  int? get activeCount =>
      !fresh || connections.any((item) => item.active == null)
      ? null
      : confirmedActiveCount;
  DateTime get lastActivity => connections
      .map((item) => item.activityAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  Set<(String, String)> get rules => Set.unmodifiable(
    connections.map((item) => (item.info.rule, item.info.rulePayload)),
  );
  List<List<String>> get exitPaths {
    final paths = <String, List<String>>{};
    for (final item in connections) {
      paths[jsonEncode(item.info.chains)] = item.info.chains;
    }
    return List.unmodifiable(paths.values);
  }
}

class AppActivity {
  const AppActivity({
    required this.key,
    required this.application,
    required this.totals,
  });
  final String key;
  final ApplicationIdentity application;
  final ActivityTotals totals;
}

class HostActivity {
  const HostActivity({required this.key, required this.totals});
  final String key;
  final ActivityTotals totals;
  String get target => key.substring(key.indexOf(':') + 1);
}

class ApplicationActivityState {
  const ApplicationActivityState({
    this.runtimeEpoch = '',
    this.since,
    this.connections = const [],
    this.observing = false,
    this.hasSnapshot = false,
    this.snapshotFailed = false,
    this.interrupted = false,
    this.truncated = false,
    this.capacity = 4096,
  });

  final String runtimeEpoch;
  final DateTime? since;
  final List<ActivityConnection> connections;
  final bool observing, hasSnapshot, snapshotFailed, interrupted, truncated;
  final int capacity;
  bool get fresh => observing && hasSnapshot && !snapshotFailed;

  List<AppActivity> _apps(Iterable<ActivityConnection> records) {
    final groups = <String, List<ActivityConnection>>{};
    for (final record in records) {
      (groups[record.appKey] ??= []).add(record);
    }
    final result = [
      for (final entry in groups.entries)
        AppActivity(
          key: entry.key,
          application: entry.value.first.application,
          totals: ActivityTotals(entry.value, fresh: fresh),
        ),
    ];
    result.sort(
      (a, b) => b.totals.lastActivity.compareTo(a.totals.lastActivity),
    );
    return List.unmodifiable(result);
  }

  List<AppActivity> get apps => _apps(connections);

  List<HostActivity> hostsForApp(String appKey) {
    final groups = <String, List<ActivityConnection>>{};
    for (final record in connections.where((item) => item.appKey == appKey)) {
      (groups[record.hostKey] ??= []).add(record);
    }
    final result = [
      for (final entry in groups.entries)
        HostActivity(
          key: entry.key,
          totals: ActivityTotals(entry.value, fresh: fresh),
        ),
    ];
    result.sort(
      (a, b) => b.totals.lastActivity.compareTo(a.totals.lastActivity),
    );
    return List.unmodifiable(result);
  }

  List<AppActivity> appsForHost(String hostKey) =>
      _apps(connections.where((item) => item.hostKey == hostKey));
}
