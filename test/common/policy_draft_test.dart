import 'dart:convert';

import 'package:fl_clash/common/policy_draft.dart';
import 'package:fl_clash/common/policy_migration.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/test_policy_drafts.dart';

void main() {
  test(
    'new incomplete drafts keep both defaults absent and cannot preview',
    () {
      final draft = PolicyDraftDocument.decode(
        PolicyDraftDocument.empty().encode(),
      );
      expect(draft.isReadOnly, isFalse);
      expect(draft.policy['domainDefault'], isNull);
      expect(draft.policy['ipDefault'], isNull);
      expect(
        () => previewPolicyDraft(draft),
        throwsA(isA<PolicyDraftProblem>()),
      );
    },
  );

  test(
    'unknown versions, unknown fields and non-renderable shapes remain opaque',
    () {
      for (final raw in [
        'broken',
        '{"draftVersion":99}',
        jsonEncode({
          'draftVersion': 1,
          'policy': {
            'schemaVersion': 1,
            'proxies': {
              'a': {'type': 'http'},
            },
          },
        }),
        jsonEncode({
          'draftVersion': 1,
          'policy': {'schemaVersion': 2},
        }),
        jsonEncode({
          'draftVersion': 1,
          'policy': {'schemaVersion': 1, 'future': true},
        }),
        jsonEncode({
          'draftVersion': 1,
          'policy': {
            'schemaVersion': 1,
            'proxies': {
              'a': {
                'port': {'unknown': 'value'},
              },
            },
          },
        }),
      ]) {
        expect(PolicyDraftDocument.decode(raw).isReadOnly, isTrue);
      }
    },
  );

  test(
    'real compiler produces masked preview while preserving full UTF8 credentials',
    () {
      final draft = completePolicyDraft(credentials: true);
      final preview = previewPolicyDraft(draft);
      final full = loadYaml(preview.fullYaml);
      final masked = loadYaml(preview.maskedYaml);
      expect(full['proxies'][0]['username'], 'synthetic-user-测试');
      expect(full['proxies'][0]['password'], 'synthetic-password-🙂');
      expect(masked['proxies'][0]['password'], '••••••');
      expect(preview.maskedYaml, isNot(contains('synthetic-password')));
      expect(preview.maskedYaml, isNot(contains('synthetic-user')));
      expect(preview.toString(), isNot(contains('synthetic-password')));
      expect(draft.toString(), isNot(contains('synthetic-password')));
      expect(
        MigrationData(
          policyDrafts: [
            ProfilePolicyDraft(profileId: 1, rawContent: draft.encode()),
          ],
        ).toString(),
        isNot(contains('synthetic-password')),
      );
    },
  );

  test(
    'validation reports known field paths without attacker-controlled map IDs',
    () {
      final draft = completePolicyDraft();
      draft.policy['proxies'] = {
        'synthetic-secret-map-key!': {
          'type': 'socks5',
          'address': '127.0.0.1',
          'port': 1080,
          'udp': false,
        },
      };
      try {
        previewPolicyDraft(draft);
        fail('expected validation failure');
      } on PolicyDraftProblem catch (problem) {
        expect(problem.location, 'policy.proxies');
        expect(problem.toString(), isNot(contains('synthetic-secret')));
      }
    },
  );

  test(
    'resource references cover row and explicit defaults without replacing them',
    () {
      final draft = completePolicyDraft();
      expect(
        policyDraftResourceReferences(draft, 'groups', 'b'),
        containsAll(['domainRules[1].target', 'domainDefault.target']),
      );
      expect(
        policyDraftResourceReferences(draft, 'dnsServices', 'dnsB'),
        contains('domainDefault.dnsService'),
      );
      expect(policyDraftResourceReferences(draft, 'proxies', 'nodeA'), [
        'groups[0]',
      ]);
    },
  );

  test(
    'legacy helper retains reverse nonempty MATCH target search and explicit override',
    () {
      final added = [Rule.parse('DOMAIN,added.test,MATCH')];
      final source = ['MATCH,REJECT', 'MATCH,DIRECT'];
      expect(
        composeProfileRules(
          sourceRules: source,
          customRules: [],
          addedRules: added,
        ),
        ['DOMAIN,added.test,DIRECT', ...source],
      );
      expect(
        composeProfileRules(
          sourceRules: source,
          customRules: [],
          addedRules: added,
          matchTarget: 'REJECT',
        ).first,
        'DOMAIN,added.test,REJECT',
      );
      expect(
        composeProfileRules(
          sourceRules: 42,
          customRules: [Rule.parse('MATCH,REJECT')],
          addedRules: added,
        ),
        ['MATCH,REJECT'],
      );
    },
  );

  test(
    'intermediate MATCH cannot be skipped, cleared by defaults or by deleting candidate rows',
    () {
      final snapshot = migrationSnapshot([
        'MATCH,REJECT',
        'DOMAIN,secret.test,DIRECT',
      ]);
      final analysis = analyzePolicyMigration(snapshot);
      expect(analysis.rules, ['MATCH,REJECT', 'DOMAIN,secret.test,DIRECT']);
      expect(
        analysis.issues.any(
          (p) => p.code == 'intermediate_match' && p.index == 0,
        ),
        isTrue,
      );
      final draft = policyDraftFromSnapshot(snapshot);
      draft.policy.addAll(completePolicyDraft().policy);
      draft.policy['domainDefault'] = {
        'target': {'kind': 'reject'},
      };
      draft.policy['ipDefault'] = {'kind': 'reject'};
      draft.policy['domainRules'] = [];
      expect(
        () => previewPolicyDraft(draft),
        throwsA(
          isA<PolicyDraftProblem>().having(
            (p) => p.location,
            'location',
            'migration',
          ),
        ),
      );
    },
  );

  test(
    'MATCH after proxy retains later rules rather than assuming UDP cannot continue',
    () {
      final snapshot = migrationSnapshot([
        'MATCH,ordinary',
        'DOMAIN,later.test,REJECT',
      ]);
      snapshot['sourceBytes'] = base64Encode(
        utf8.encode(
          jsonEncode({
            'rules': ['MATCH,ordinary', 'DOMAIN,later.test,REJECT'],
            'proxies': [
              {
                'name': 'node',
                'type': 'socks5',
                'server': '127.0.0.1',
                'port': 1080,
                'udp': false,
              },
            ],
            'proxy-groups': [
              {
                'name': 'ordinary',
                'type': 'select',
                'proxies': ['node'],
              },
            ],
          }),
        ),
      );
      expect(analyzePolicyMigration(snapshot).rules, hasLength(2));
      expect(
        policyMigrationIssues(
          snapshot,
        ).any((p) => p.code == 'intermediate_match'),
        isTrue,
      );
    },
  );

  test('IP REJECT with and without no-resolve blocks the domain split', () {
    for (final flag in ['', ',no-resolve']) {
      final snapshot = migrationSnapshot([
        'IP-CIDR,10.0.0.0/8,REJECT$flag',
        'DOMAIN,allowed.test,DIRECT',
        'MATCH,REJECT',
      ]);
      expect(
        policyMigrationIssues(
          snapshot,
        ).any((p) => p.code == 'ip' && p.index == 0),
        isTrue,
      );
    }
  });

  test(
    'custom nonempty replaces source while empty falls back; script stays opaque',
    () {
      final source = ['DOMAIN,source.test,DIRECT', 'MATCH,REJECT'];
      final custom = migrationSnapshot(
        source,
        mode: 'custom',
        custom: [Rule.parse('DOMAIN,custom.test,REJECT')],
      );
      expect(analyzePolicyMigration(custom).rules, [
        'DOMAIN,custom.test,REJECT',
      ]);
      expect(
        analyzePolicyMigration(migrationSnapshot(source, mode: 'custom')).rules,
        source,
      );
      expect(
        policyMigrationIssues(
          migrationSnapshot(source, mode: 'script'),
        ).single.code,
        'script',
      );
    },
  );

  test(
    'strict migration blocks mixed, Geo, unknown tokens and unsupported snapshot material',
    () {
      for (final raw in [
        'AND,((DOMAIN,a.test),(NETWORK,UDP)),DIRECT',
        'GEOIP,CN,DIRECT',
        'WHAT,a.test,DIRECT',
        'DOMAIN,a.test,DIRECT,unknown',
      ]) {
        expect(
          policyMigrationIssues(
            migrationSnapshot([raw]),
          ).any((p) => p.code == 'rule'),
          isTrue,
        );
      }
      expect(
        policyMigrationIssues({'formatVersion': 1}).single.code,
        'snapshot',
      );
    },
  );
}
