import 'dart:convert';

import 'package:fl_clash/common/profile_import_projection.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> node(
  String name, [
  Map<String, Object?> extra = const {},
]) => {
  'name': name,
  'type': 'socks5',
  'server': '127.0.0.1',
  'port': 9,
  ...extra,
};

void main() {
  test('snapshot freezes nodes and uses one explicit proxy exit', () {
    final a = node('a');
    final b = node('b');
    final original = <String, Object?>{
      'proxies': [a],
      'rules': ['MATCH,DIRECT'],
      'dns': {
        'nameserver': ['source.invalid'],
      },
      'listeners': [{}],
      'tunnels': [{}],
      'rule-providers': {'failed': {}},
      'proxy-providers': {'later': {}},
    };
    final output =
        jsonDecode(
              loadedNodesProfile([
                original,
                {
                  'proxies': [a, b],
                },
              ])!,
            )
            as Map;
    expect(output.keys.toSet(), {'proxies', 'proxy-groups', 'rules'});
    expect(output['proxies'], [a, b]);
    expect(output['proxy-groups'], [
      {
        'name': 'Imported nodes',
        'type': 'select',
        'proxies': ['a', 'b'],
      },
    ]);
    expect(output['rules'], ['MATCH,Imported nodes']);
    expect(original['rules'], ['MATCH,DIRECT']);
  });

  test(
    'ambiguous names and unavailable or cyclic dependencies are excluded',
    () {
      final a = node('a');
      final output =
          jsonDecode(
                loadedNodesProfile([
                  {
                    'proxies': [
                      a,
                      node('a', {'port': 10}),
                      node('bad', {'dialer-proxy': 'a'}),
                      node('missing', {'dialer-proxy': 'Source group'}),
                      node('cycle-a', {'dialer-proxy': 'cycle-b'}),
                      node('cycle-b', {'dialer-proxy': 'cycle-a'}),
                      node('safe'),
                      node('dependent', {'dialer-proxy': 'safe'}),
                      node('DIRECT'),
                      node('implicit', {'type': 'direct'}),
                    ],
                  },
                ])!,
              )
              as Map;
      expect((output['proxies'] as List).map((n) => n['name']), [
        'safe',
        'dependent',
      ]);
    },
  );

  test(
    'empty material cannot offer a node snapshot and names cannot collide',
    () {
      expect(loadedNodesProfile([{}]), isNull);
      expect(
        loadedNodesProfile([
          {
            'proxies': [
              node('a', {'dialer-proxy': 'no'}),
            ],
          },
        ]),
        isNull,
      );
      final output =
          jsonDecode(
                loadedNodesProfile([
                  {
                    'proxies': [node('Imported nodes')],
                  },
                ])!,
              )
              as Map;
      expect(output['rules'], ['MATCH,Imported nodes 2']);
    },
  );
  test('long dependency chains are processed without recursive traversal', () {
    final result =
        jsonDecode(
              loadedNodesProfile([
                {
                  'proxies': [
                    for (var i = 0; i < 10000; i++)
                      node('n$i', {if (i < 9999) 'dialer-proxy': 'n${i + 1}'}),
                  ],
                },
              ])!,
            )
            as Map;
    expect(result['proxies'], hasLength(10000));
  });
}
