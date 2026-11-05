import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  MakeRealProfileState input() => MakeRealProfileState(
    profilesPath: '/source-ledger-fixture',
    profileId: 7,
    rawConfig: {
      'rules': ['DOMAIN,source.invalid,DIRECT', 'MATCH,DIRECT'],
      'sub-rules': {
        'source': ['MATCH,REJECT'],
      },
    },
    realPatchConfig: const PatchClashConfig(),
    overrideDns: false,
    overrideNtp: false,
    appendSystemDns: false,
    proxyGroups: const [],
    rules: const [],
    addedRules: [Rule.parse('DOMAIN,local.invalid,REJECT')],
    defaultUA: 'synthetic-ledger',
  );
  const origins = {
    'profileKey': 'profile:7',
    'profileRevision': 'accepted-profile-revision',
  };

  test(
    'ledger follows actual local prefix and source composition ranges',
    () async {
      final composition = await makeProfileCompositionTask(
        input(),
        origins: origins,
      );
      final config = loadYaml(composition.yaml) as YamlMap;
      expect(config['rules'], [
        'DOMAIN,local.invalid,REJECT',
        'DOMAIN,source.invalid,DIRECT',
        'MATCH,DIRECT',
      ]);
      final ranges = (composition.ledger['lists'] as Map)['rules'] as List;
      expect(ranges[0]['origin'], 'application-rules');
      expect([ranges[0]['start'], ranges[0]['end']], [0, 1]);
      expect(ranges[1]['origin'], 'profile:7');
      expect([ranges[1]['start'], ranges[1]['end']], [1, 3]);
      expect(ranges[1]['revision'], 'accepted-profile-revision');
      expect(
        ranges[1]['rulesDigest'],
        '9f47a36f9a7381f56d9ba57ab56d49459b300a882b39bd74f358ed03448e32fb',
      );
    },
  );

  test(
    'script output remains ambiguous even when rule text matches a profile',
    () async {
      final composition = await makeProfileCompositionTask(
        input(),
        origins: {...origins, 'scriptKey': 'script:9'},
      );
      final lists = composition.ledger['lists'] as Map;
      final ranges = lists['rules'] as List;
      expect(ranges[0]['origin'], 'application-rules');
      expect(ranges[1].containsKey('origin'), isFalse);
      expect(ranges[1]['candidates'], ['profile:7', 'script:9']);
      expect((lists['sub-rules:source'] as List).single['candidates'], [
        'profile:7',
        'script:9',
      ]);
    },
  );

  test('explicit empty own routing records the local default origin', () async {
    final composition = await makeProfileCompositionTask(
      input().copyWith(
        sourceRoutingDenied: true,
        addedRules: const [],
        matchTarget: 'REJECT',
      ),
      origins: origins,
    );
    final lists = composition.ledger['lists'] as Map;
    expect(lists.containsKey('sub-rules:source'), isFalse);
    final range = (lists['rules'] as List).single;
    expect(
      [range['start'], range['end'], range['origin']],
      [0, 1, 'override:7'],
    );
    expect((loadYaml(composition.yaml) as YamlMap)['rules'], ['MATCH,REJECT']);
  });
}
