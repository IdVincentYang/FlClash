import 'dart:convert';

import 'package:fl_clash/common/managed_material.dart';
import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/common/policy_draft.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_managed_materials.dart';
import '../helpers/test_policy_drafts.dart';

void main() {
  MaterialPolicy resolve(
    Map<String, dynamic> material, {
    PolicyDraftDocument? draft,
  }) => resolveMaterialPolicy(
    (draft ?? materialDraft()).policy,
    material: material,
    identity: testMaterialIdentity(),
    profileId: 1,
    rawSha256: materialDigest(material),
  );

  test(
    'version 2 draft survives round trip and has no usable static policy',
    () {
      final draft = materialDraft();
      expect(PolicyDraftDocument.decode(draft.encode()).isReadOnly, false);
      expect(policyDraftInputProblem(draft), isNull);
      final selected = SelectedPolicy.decode(selectPolicyDraft(draft));
      expect(selected.usesMaterials, true);
      expect(() => selected.policy, throwsA(isA<PolicyDraftProblem>()));
      expect(() => selected.picks({}), throwsA(isA<PolicyDraftProblem>()));
      expect(
        () => previewPolicyDraft(draft),
        throwsA(isA<PolicyDraftProblem>()),
      );
    },
  );

  test(
    'A to B expands actual credentials members and ordered domain and IP rows',
    () {
      final a = resolve(testMaterial());
      final b = resolve(testMaterial(updated: true));
      expect(a.policy.proxies['nodeA']!.password, 'pass-a');
      expect(b.policy.proxies['nodeA']!.password, 'pass-b');
      expect(a.policy.groups['b'], isNot(b.policy.groups['b']));
      expect(a.policy.domainRules.map((r) => r.value).take(3), [
        'example.test',
        'ordered.test',
        'exact.example.test',
      ]);
      expect(b.policy.domainRules.first.value, 'updated.test');
      expect(b.policy.ipRules.map((r) => r.cidr), [
        '127.0.0.0/8',
        '::1/128',
        '::1/128',
      ]);
      expect(a.receipt!['rawSha256'], isNot(b.receipt!['rawSha256']));
      expect(jsonEncode(b.receipt), isNot(contains('source-select')));
      expect(jsonEncode(b.receipt), isNot(contains('pass-b')));
      final yaml = compileManagedProfile(b.policy);
      expect(yaml, contains('pass-b'));
      expect(yaml, isNot(contains('source-select')));
    },
  );

  test(
    'dynamic pick removal selects a real new member and static invalid picks fail',
    () {
      final template = SelectedPolicy.decode(
        selectPolicyDraft(materialDraft()),
      );
      SelectedPolicy selected(bool update) => template.resolve(
        material: testMaterial(updated: update),
        identity: testMaterialIdentity(),
        profileId: 1,
        rawSha256: materialDigest(update),
      );
      final a = selected(false), b = selected(true);
      final key = managedGroupName('b');
      expect(b.picks({key: managedProxyName(a.policy.groups['b']!.first)}), {
        key: managedProxyName(b.policy.groups['b']!.first),
      });
      expect(
        () => b.picks({managedGroupName('a'): 'DIRECT'}),
        throwsA(isA<PolicyDraftProblem>()),
      );
    },
  );

  test('v1 manual nodes never bind by source name', () {
    final selected = SelectedPolicy.decode(
      selectPolicyDraft(completePolicyDraft()),
    );
    final resolved = selected.resolve(
      material: testMaterial(updated: true),
      identity: testMaterialIdentity(),
      profileId: 1,
      rawSha256: materialDigest('b'),
    );
    expect(resolved.policy.proxies['nodeA']!.port, 1081);
    expect(resolved.materials, isNull);
  });

  test('identity changes and unknown schema cannot materialize', () {
    expect(
      () => resolveMaterialPolicy(
        materialDraft().policy,
        material: testMaterial(),
        identity: testMaterialIdentity(2),
        profileId: 2,
        rawSha256: materialDigest('a'),
      ),
      throwsFormatException,
    );
    final mismatch = materialDraft();
    mismatch.policy['materialSource']['profileId'] = 2;
    expect(
      () => resolve(testMaterial(), draft: mismatch),
      throwsFormatException,
    );
    final draft = materialDraft();
    draft.policy['schemaVersion'] = 99;
    expect(PolicyDraftDocument.decode(draft.encode()).isReadOnly, true);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing node': (m) => (m['proxies'] as List).removeAt(0),
    'node and group collision': (m) => m['proxy-groups'].add({
      'name': 'source-a',
      'type': 'select',
      'proxies': ['source-b'],
    }),
    'duplicate node': (m) => (m['proxies'] as List).add(m['proxies'][0]),
    'domain endpoint': (m) => m['proxies'][0]['server'] = 'proxy.example.test',
    'other protocol': (m) => m['proxies'][0]['type'] = 'http',
    'unknown node field': (m) => m['proxies'][0]['tls'] = true,
    'automatic group': (m) => m['proxy-groups'][0]['type'] = 'url-test',
    'direct member': (m) => m['proxy-groups'][0]['proxies'] = ['DIRECT'],
    'missing selected member': (m) =>
        m['proxy-groups'][0]['proxies'] = ['gone'],
    'duplicate member': (m) =>
        m['proxy-groups'][0]['proxies'] = ['source-b', 'source-b'],
    'remote provider': (m) =>
        m['rule-providers']['source-domains']['type'] = 'http',
    'unknown provider field': (m) =>
        m['rule-providers']['source-domains']['path'] = '../outside',
    'empty collection': (m) =>
        m['rule-providers']['source-domains']['payload'] = [],
    'mixed collection': (m) =>
        m['rule-providers']['source-domains']['payload'] = [
          'IP-CIDR,127.0.0.1/32',
        ],
    'duplicate normalized domain': (m) =>
        m['rule-providers']['source-domains']['payload'] = [
          'DOMAIN,A.test',
          'DOMAIN,a.test',
        ],
    'duplicate normalized IP': (m) =>
        m['rule-providers']['source-addresses']['payload'] = [
          '127.0.0.1/8',
          '127.1.0.1/8',
        ],
    'too many rules': (m) => m['rule-providers']['source-domains']['payload'] =
        List.generate(10001, (i) => 'DOMAIN,d$i.test'),
    'too many members': (m) =>
        m['proxy-groups'][0]['proxies'] = List.generate(1025, (i) => 'n$i'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key} without leaking source material', () {
      final material = testMaterial();
      entry.value(material);
      expect(
        () => resolve(material),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'safe error',
            isNot(contains('pass-a')),
          ),
        ),
      );
    });
  }

  test(
    'document qualification rejects alias amplification before native parsing',
    () {
      final levels = ['root: &n0 [one, two]'];
      for (var i = 1; i < 20; i++) {
        levels.add('n$i: &n$i [*n${i - 1}, *n${i - 1}]');
      }
      expect(
        () => validateMaterialDocument(utf8.encode(levels.join('\n'))),
        throwsFormatException,
      );
      expect(
        () => validateMaterialDocument(utf8.encode('root: &root [*root]')),
        throwsFormatException,
      );
    },
  );

  test('input byte budget accounts for escaped strings before copying', () {
    expect(
      () =>
          boundedMaterialCopy({'x': '\u0000' * (managedMaterialMaxBytes ~/ 6)}),
      throwsFormatException,
    );
    expect(
      () => boundedMaterialCopy({'x': 'a' * managedMaterialMaxBytes}),
      throwsFormatException,
    );
  });
}
