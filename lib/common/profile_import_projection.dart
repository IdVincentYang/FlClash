import 'dart:convert';

import 'package:collection/collection.dart';

String? loadedNodesProfile(Iterable<Map<String, Object?>> documents) {
  final nodes = <String, Map<String, Object?>>{};
  final conflicts = <String>{};
  Map<String, Object?>? firstIndependent;
  for (final document in documents) {
    for (final raw in document['proxies'] as List? ?? const []) {
      if (raw is! Map) continue;
      final node = Map<String, Object?>.from(raw);
      final name = node['name'];
      final type = node['type'];
      if (name is! String || name.isEmpty || type is! String || type.isEmpty) {
        continue;
      }
      if (const {
            'DIRECT',
            'REJECT',
            'REJECT-DROP',
            'PASS',
            'COMPATIBLE',
            'GLOBAL',
          }.contains(name) ||
          const {
            'direct',
            'reject',
            'reject-drop',
            'pass',
            'compatible',
          }.contains(type.toLowerCase())) {
        continue;
      }
      if (node['dialer-proxy'] == null ||
          node['dialer-proxy'] == '' ||
          node['dialer-proxy'] == 'DIRECT') {
        firstIndependent ??= node;
      }
      final previous = nodes[name];
      if (previous != null &&
          !const DeepCollectionEquality().equals(previous, node)) {
        conflicts.add(name);
      }
      nodes[name] = node;
    }
  }
  for (final name in conflicts) {
    nodes.remove(name);
  }
  final supported = <String, bool>{};
  for (final name in nodes.keys) {
    final path = <String>{};
    var current = name;
    var valid = false;
    while (true) {
      if (supported.containsKey(current)) {
        valid = supported[current]!;
        break;
      }
      final node = nodes[current];
      if (node == null || !path.add(current)) break;
      final dependency = node['dialer-proxy'];
      if (dependency == null || dependency == '' || dependency == 'DIRECT') {
        valid = true;
        break;
      }
      if (dependency is! String) break;
      current = dependency;
    }
    for (final member in path) {
      supported[member] = valid;
    }
  }
  final retained = {
    for (final entry in nodes.entries)
      if (supported[entry.key] == true) entry.key: entry.value,
  };
  if (retained.isEmpty && firstIndependent != null) {
    retained[firstIndependent['name'] as String] = firstIndependent;
  }
  if (retained.isEmpty) return null;
  var group = 'Imported nodes';
  for (var suffix = 2; retained.containsKey(group); suffix++) {
    group = 'Imported nodes $suffix';
  }
  final result = jsonEncode({
    'proxies': retained.values.toList(),
    'proxy-groups': [
      {'name': group, 'type': 'select', 'proxies': retained.keys.toList()},
    ],
    'rules': ['MATCH,$group'],
  });
  return utf8.encode(result).length <= 16 * 1024 * 1024 ? result : null;
}
