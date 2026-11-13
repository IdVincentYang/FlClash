import 'dart:convert';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const localProxyGroupsLimit = 64;
const localProxyGroupMembersLimit = 1024;

List<Proxy> localGroupNodes(List<Group> groups) {
  final names = groups.map((group) => group.name).toSet();
  final nodes = <String, Proxy>{};
  for (final group in groups) {
    for (final proxy in group.all) {
      if (!names.contains(proxy.name) &&
          !const {
            'DIRECT',
            'REJECT',
            'REJECT-DROP',
            'PASS',
            'COMPATIBLE',
          }.contains(proxy.name) &&
          !GroupType.values.any(
            (type) => type.name.toLowerCase() == proxy.type.toLowerCase(),
          )) {
        nodes[proxy.name] = proxy;
      }
    }
  }
  return nodes.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

String _localNodePattern(String name) => name
    .split('')
    .map(
      (character) => character == '`'
          ? r'\x60'
          : r'\.+*?()|[]{}^$'.contains(character)
          ? '\\$character'
          : character,
    )
    .join();

class LocalProxyGroupProblem implements Exception {
  const LocalProxyGroupProblem(this.code, [this.name = '']);
  final String code, name;
}

Map<String, dynamic> mergeLocalProxyGroups(
  Map<String, dynamic> document,
  List<LocalProxyGroup> groups,
) {
  if (groups.isEmpty) return document;
  if (groups.length > localProxyGroupsLimit) {
    throw const LocalProxyGroupProblem('limit');
  }
  final result = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
  final definitions = [
    for (final item in result['proxy-groups'] as List? ?? const [])
      Map<String, dynamic>.from(item as Map),
  ];
  final inlineNodes = {
    for (final node in result['proxies'] as List? ?? const [])
      '${node['name']}',
  };
  final names = <String>{
    'GLOBAL',
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'PASS-RULE',
    'COMPATIBLE',
    for (final group in definitions) '${group['name']}',
    for (final node in result['proxies'] as List? ?? const [])
      '${node['name']}',
  };
  for (final group in groups) {
    if (!group.enabled) continue;
    if (group.name.trim().isEmpty ||
        group.name.length > 128 ||
        group.name.runes.any((rune) => rune < 32 || rune == 127) ||
        !names.add(group.name)) {
      throw LocalProxyGroupProblem('name', group.name);
    }
    if (!const {
          GroupType.Selector,
          GroupType.URLTest,
          GroupType.Fallback,
        }.contains(group.type) ||
        group.effectiveNodes.isEmpty && group.regex.isEmpty && !group.global ||
        group.effectiveNodes.length > localProxyGroupMembersLimit ||
        group.effectiveNodes.toSet().length != group.effectiveNodes.length ||
        group.effectiveNodes.any(
          (node) => node.isEmpty || node == group.name,
        )) {
      throw LocalProxyGroupProblem('members', group.name);
    }
    for (final entrance in group.entrances) {
      final parent = definitions
          .where((item) => item['name'] == entrance)
          .firstOrNull;
      if (parent == null || parent['type'] != 'select') {
        throw LocalProxyGroupProblem('parent', group.name);
      }
      parent['proxies'] = [
        ...(parent['proxies'] as List? ?? const []),
        group.name,
      ];
    }
    final uri = Uri.tryParse(group.testUrl);
    if (group.type != GroupType.Selector &&
        (uri == null ||
            !const {'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty)) {
      throw LocalProxyGroupProblem('testUrl', group.name);
    }
    definitions.add({
      'name': group.name,
      'type': group.type.value,
      'proxies':
          group.effectiveNodes.isEmpty &&
              (group.regex.isNotEmpty || group.global)
          ? ['REJECT']
          : group.effectiveNodes.where(inlineNodes.contains).toList(),
      if (group.regex.isNotEmpty || group.global) 'empty-fallback': 'REJECT',
      if (group.effectiveNodes.any((name) => !inlineNodes.contains(name))) ...{
        'include-all-providers': true,
        'filter':
            '^(?:${group.effectiveNodes.map(_localNodePattern).join('|')})\$(?![\\s\\S])',
      },
      if (group.type != GroupType.Selector) ...{
        'url': group.testUrl,
        'interval': 300,
      },
    });
  }
  result['proxy-groups'] = definitions;
  return result;
}
