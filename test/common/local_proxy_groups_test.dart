import 'dart:convert';

import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const local = LocalProxyGroup(
    id: 7,
    name: 'Mine',
    nodes: ['a'],
    parent: 'Main',
  );
  Map<String, dynamic> document() => {
    'proxies': [
      {'name': 'a', 'type': 'socks5', 'server': '127.0.0.1', 'port': 9},
    ],
    'proxy-groups': [
      {
        'name': 'Main',
        'type': 'select',
        'proxies': ['a'],
      },
    ],
    'rules': ['MATCH,Main'],
    'dns': {
      'nameserver': ['1.1.1.1'],
    },
  };
  test(
    'local groups append while preserving source nodes rules DNS and input',
    () {
      final input = document();
      final original = jsonEncode(input);
      final next = mergeLocalProxyGroups(input, [local]);
      expect(jsonEncode(input), original);
      expect(next['proxies'], input['proxies']);
      expect(next['rules'], input['rules']);
      expect(next['dns'], input['dns']);
      expect((next['proxy-groups'] as List).first['proxies'], ['a', 'Mine']);
      expect((next['proxy-groups'] as List).last['proxies'], ['a']);
    },
  );
  test('disabled definitions do not change effective groups', () {
    final input = document();
    expect(
      mergeLocalProxyGroups(input, [local.copyWith(enabled: false)]),
      input,
    );
  });
  test('provider nodes are selected with exact escaped names', () {
    final input = document()..remove('proxies');
    const name = r'a.b$[x](1)+|?`-';
    final result = mergeLocalProxyGroups(input, [
      local.copyWith(nodes: [name]),
    ]);
    final definition = (result['proxy-groups'] as List).last as Map;
    expect(definition['proxies'], isEmpty);
    expect(definition['include-all-providers'], isTrue);
    expect(RegExp(definition['filter'] as String).hasMatch(name), isTrue);
    expect(
      RegExp(definition['filter'] as String).hasMatch('prefix$name'),
      isFalse,
    );
    expect(RegExp(definition['filter'] as String).hasMatch('$name\n'), isFalse);
  });
  test(
    'profile JSON and local definitions round trip including disabled groups',
    () {
      final profile = Profile.normal(
        label: 'fixture',
      ).copyWith(localGroups: [local.copyWith(enabled: false)]);
      final next = Profile.fromJson(
        jsonDecode(jsonEncode(profile)) as Map<String, dynamic>,
      );
      expect(next, profile);
      expect(next.localGroups.single.enabled, isFalse);
    },
  );
  for (final type in [GroupType.URLTest, GroupType.Fallback]) {
    test('automatic group $type has a bounded test interval', () {
      final result = mergeLocalProxyGroups(document(), [
        local.copyWith(type: type, testUrl: 'https://example.invalid/probe'),
      ]);
      expect((result['proxy-groups'] as List).last['interval'], 300);
    });
  }
  for (final invalid in [
    local.copyWith(name: 'Main'),
    local.copyWith(name: 'DIRECT'),
    local.copyWith(name: 'a'),
    local.copyWith(nodes: []),
    local.copyWith(parent: 'missing'),
    local.copyWith(type: GroupType.Relay),
    local.copyWith(type: GroupType.URLTest),
  ]) {
    test('invalid local definition is rejected: $invalid', () {
      expect(
        () => mergeLocalProxyGroups(document(), [invalid]),
        throwsA(isA<LocalProxyGroupProblem>()),
      );
    });
  }
}
