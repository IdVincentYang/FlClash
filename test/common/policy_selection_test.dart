import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/common/policy_draft.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/test_policy_drafts.dart';

void main() {
  test('selection binds exact content and explicit maintenance target', () {
    final draft = completePolicyDraft(credentials: true);
    final raw = selectPolicyDraft(
      draft,
      maintenanceProxyTarget: {'kind': 'proxy', 'id': 'nodeA'},
    );
    final selected = SelectedPolicy.decode(raw);
    expect(selected.digest, sha256.convert(utf8.encode(raw)).toString());
    expect(selected.maintenanceProxy, managedProxyName('nodeA'));
    expect(
      SelectedPolicy.decode(selectPolicyDraft(draft)).maintenanceProxy,
      isNull,
    );
    expect(selected.toString(), isNot(contains('synthetic-password')));
    for (final broken in [
      null,
      'broken',
      '{"selectionVersion":99}',
      jsonEncode({
        ...jsonDecode(raw),
        'maintenanceProxyTarget': {'kind': 'group', 'id': 'gone'},
      }),
    ]) {
      expect(
        () => SelectedPolicy.decode(broken),
        throwsA(isA<PolicyDraftProblem>()),
      );
    }
  });

  test(
    'owned invalid picks reject; historical GLOBAL and unrelated groups are excluded',
    () {
      final selected = SelectedPolicy.decode(
        selectPolicyDraft(completePolicyDraft()),
      );
      final group = selected.policy.groups.entries.first;
      final name = managedGroupName(group.key);
      final member = managedProxyName(group.value.first);
      expect(
        selected.picks({'GLOBAL': 'DIRECT', 'old': 'DIRECT', name: member}),
        {name: member},
      );
      for (final invalid in ['DIRECT', 'REJECT', '', 'GLOBAL', 'gone']) {
        expect(
          () => selected.picks({name: invalid}),
          throwsA(isA<PolicyDraftProblem>()),
        );
      }
    },
  );

  MakeRealProfileState candidate({bool safeMode = false}) =>
      MakeRealProfileState(
        profilesPath: '/synthetic/profiles',
        profileId: 1,
        rawConfig: {
          'mode': 'direct',
          'rules': ['MATCH,DIRECT'],
          'proxy-providers': {
            'untrusted': {'type': 'http', 'url': 'https://invalid.test'},
          },
          'sub-rules': {
            'untrusted': ['MATCH,DIRECT'],
          },
          'external-controller': '0.0.0.0:9090',
          'dns': {
            'nameserver': ['system'],
          },
          'listeners': [
            {'type': 'socks', 'port': 8888},
          ],
          'unrecognized-root': true,
        },
        realPatchConfig: const PatchClashConfig(
          mode: Mode.direct,
          mixedPort: 9999,
          logLevel: LogLevel.warning,
          interfaceNameMode: InterfaceNameMode.custom,
          interfaceName: 'synthetic0',
          tun: Tun(enable: true),
        ),
        overrideDns: true,
        overrideNtp: true,
        appendSystemDns: true,
        proxyGroups: [],
        rules: [],
        addedRules: [],
        defaultUA: 'synthetic',
        authentication: ['synthetic-user:synthetic-inbound-password'],
        safeMode: safeMode,
        policySelection: ProfilePolicySelection(
          profileId: 1,
          rawContent: selectPolicyDraft(completePolicyDraft(credentials: true)),
        ),
      );

  test(
    'real final encoding uses the compiler closure and frozen integration allowlist',
    () async {
      final data = candidate();
      final result = await makeRealProfileTask(data);
      final output = loadYaml(result.yaml) as YamlMap;
      final expected = loadYaml(
        compileManagedProfile(
          SelectedPolicy.decode(data.policySelection!.rawContent).policy,
        ),
      );
      for (final key in [
        'rules',
        'sub-rules',
        'rule-providers',
        'proxies',
        'proxy-groups',
        'dns',
      ]) {
        expect(
          jsonDecode(jsonEncode(output[key])),
          jsonDecode(jsonEncode(expected[key])),
          reason: key,
        );
      }
      expect(output['mode'], 'rule');
      expect(output['mixed-port'], isNot(9999));
      expect(output['external-controller'], '');
      expect(output['proxy-providers'], isNull);
      expect(output['listeners'], isNull);
      expect(output['unrecognized-root'], isNull);
      expect(output['authentication'], data.authentication);
      expect(output['skip-auth-prefixes'], isEmpty);
      expect(output['log-level'], 'warning');
      expect(output['interface-name'], 'synthetic0');
      expect(output['tun']['enable'], isTrue);
      final masked = maskedPolicyConfig(result.yaml);
      for (final secret in [
        'synthetic-user',
        'synthetic-password',
        'synthetic-inbound-password',
      ]) {
        expect(masked, isNot(contains(secret)));
      }
      final safe = loadYaml(
        (await makeRealProfileTask(candidate(safeMode: true))).yaml,
      );
      expect(safe['tun']['enable'], isFalse);
      expect(safe['dns']['listen'], '');
    },
  );
}
