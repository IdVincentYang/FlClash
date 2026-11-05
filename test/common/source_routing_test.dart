import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  MakeRealProfileState input({String? target = 'REJECT'}) =>
      MakeRealProfileState(
        profilesPath: '/source-routing-fixture',
        profileId: 7,
        rawConfig: {
          'rules': ['DOMAIN,source.invalid,DIRECT', 'MATCH,DIRECT'],
          'sub-rules': {
            'source': ['MATCH,DIRECT'],
          },
          'listeners': [
            {'name': 'source', 'port': 19080, 'proxy': 'DIRECT'},
          ],
          'tunnels': [
            {'network': 'tcp', 'proxy': 'DIRECT'},
          ],
        },
        realPatchConfig: const PatchClashConfig(),
        overrideDns: false,
        overrideNtp: false,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'source-routing-fixture',
        sourceRoutingDenied: true,
        matchTarget: target,
      );

  test(
    'empty own rules keep the explicit default and exclude source entries',
    () async {
      final result = await makeRealProfileTask(input());
      final config = loadYaml(result.yaml) as YamlMap;
      expect(config['rules'], ['MATCH,REJECT']);
      for (final field in ['sub-rules', 'listeners', 'tunnels']) {
        expect(config.containsKey(field), isFalse);
      }
    },
  );

  test(
    'own rules use the explicit default after their real ordered entries',
    () async {
      final state = input(target: 'DIRECT').copyWith(
        rules: const [
          Rule(
            ruleAction: RuleAction.DOMAIN,
            content: 'own.invalid',
            ruleTarget: 'REJECT',
          ),
        ],
      );
      final result = await makeRealProfileTask(state);
      expect((loadYaml(result.yaml) as YamlMap)['rules'], [
        'DOMAIN,own.invalid,REJECT',
        'MATCH,DIRECT',
      ]);
    },
  );

  test(
    'missing and fall-through defaults cannot silently select direct',
    () async {
      for (final target in [null, '', 'PASS', 'REMATCH', 'COMPATIBLE']) {
        await expectLater(
          makeRealProfileTask(input(target: target)),
          throwsFormatException,
        );
      }
    },
  );

  test('conflicting or repeated terminal decisions are rejected', () async {
    for (final rules in [
      const [Rule(ruleAction: RuleAction.MATCH, ruleTarget: 'DIRECT')],
      const [
        Rule(ruleAction: RuleAction.MATCH, ruleTarget: 'REJECT'),
        Rule(ruleAction: RuleAction.MATCH, ruleTarget: 'REJECT'),
      ],
    ]) {
      await expectLater(
        makeRealProfileTask(input().copyWith(rules: rules)),
        throwsFormatException,
      );
    }
  });

  test(
    'the final node override cannot restore rematch after the source check',
    () async {
      final state = input().copyWith(
        proxies: const [
          CustomProxy(id: 1, definition: {'name': 'bypass', 'type': 'rematch'}),
        ],
      );
      await expectLater(makeRealProfileTask(state), throwsFormatException);
    },
  );
}
