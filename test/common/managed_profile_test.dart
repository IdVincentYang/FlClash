import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/models/managed_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/compile_managed_profile.dart' show writeManagedProfile;

Map<String, dynamic> fixture() =>
    jsonDecode(
          File('test/fixtures/managed_profile/policy.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

String compile(Map<String, dynamic> input) =>
    compileManagedProfile(ManagedPolicy.fromJson(input));

void main() {
  test('same ordered domain providers feed both consumers and defaults', () {
    final input = fixture();
    final output = compile(input);
    expect(compile(input), output);
    final config = loadYaml(output) as YamlMap;
    final providers = config['rule-providers'] as YamlMap;
    final dns = config['dns'] as YamlMap;
    final policy = dns['nameserver-policy'] as YamlMap;
    expect(policy.keys, providers.keys.map((key) => 'rule-set:$key'));
    expect((config['rules'] as YamlList).last, 'MATCH,REJECT');
    expect(config['rules'], [
      r'SUB-RULE,(DOMAIN-REGEX,^.+$),fc-managed-domain',
      r'SUB-RULE,(NOT,((DOMAIN-REGEX,^.+$))),fc-managed-ip',
      'MATCH,REJECT',
    ]);
    expect(policy.values.first, ['tcp://127.0.0.1:5301#fc-managed-group-a']);
    expect(policy.values.last, ['tcp://127.0.0.1:5302#fc-managed-group-b']);
    expect(dns['direct-nameserver-follow-policy'], true);
    expect(dns['fallback'], isEmpty);
    expect(dns['use-system-hosts'], false);
    expect((config['sub-rules']['fc-managed-ip'] as YamlList).take(2), [
      'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
      'IP-CIDR6,::1/128,DIRECT,no-resolve',
    ]);
    final entries = input['domainRules'] as List;
    final first = entries.removeAt(0);
    entries.insert(1, first);
    final reordered = loadYaml(compile(input));
    expect(
      reordered['dns']['nameserver-policy'].keys.first,
      'rule-set:fc-managed-domain-exact',
    );
  });

  test('empty policy with explicit rejection needs no proxy nodes', () {
    final input = fixture()
      ..['domainRules'] = []
      ..['domainDefault'] = {
        'target': {'kind': 'reject'},
      }
      ..['ipRules'] = []
      ..['proxies'] = <String, dynamic>{}
      ..['groups'] = <String, dynamic>{};
    final config = loadYaml(compile(input));
    expect(config['sub-rules']['fc-managed-domain'], ['MATCH,REJECT']);
    expect(config['sub-rules']['fc-managed-ip'], ['MATCH,REJECT']);
    expect(config['dns']['nameserver'], ['rcode://refused']);
    expect(config['proxies'], isEmpty);
  });

  final badInputs = <String, void Function(Map<String, dynamic>)>{
    'unknown root field': (p) => p['rawRules'] = ['MATCH,DIRECT'],
    'unknown version': (p) => p['schemaVersion'] = 2,
    'float version': (p) => p['schemaVersion'] = 1.0,
    'missing default': (p) => p.remove('domainDefault'),
    'unknown action': (p) => p['ipDefault'] = {'kind': 'PASS'},
    'empty group': (p) => p['groups']['a'] = [],
    'nested group': (p) => p['groups']['a'] = ['b'],
    'unknown target': (p) => p['domainDefault']['target']['group'] = 'missing',
    'unknown service': (p) => p['domainDefault']['dnsService'] = 'missing',
    'duplicate ID': (p) => p['domainRules'][1]['id'] = 'wide',
    'mixed predicate': (p) => p['domainRules'][0]['type'] = 'AND',
    'unsupported regex': (p) => p['domainRules'][0]['type'] = 'DOMAIN-REGEX',
    'invalid domain': (p) => p['domainRules'][0]['value'] = 'a.test,DIRECT',
    'invalid CIDR': (p) => p['ipRules'][0]['cidr'] = '127.0.0.1/33',
    'source condition': (p) => p['ipRules'][0]['src'] = true,
    'domain proxy': (p) => p['proxies']['nodeA']['address'] = 'node.test',
    'reserved member': (p) => p['groups']['a'] = ['DIRECT'],
    'unsupported proxy': (p) => p['proxies']['nodeA']['type'] = 'direct',
    'plaintext public DNS': (p) =>
        p['dnsServices']['dnsA']['address'] = '192.0.2.1',
    'unsupported UDP DNS': (p) => p['dnsServices']['dnsA']['protocol'] = 'udp',
    'reject with upstream': (p) => p['domainRules'][3]['dnsService'] = 'dnsA',
    'domain DNS endpoint': (p) =>
        p['bootstrapDns']['address'] = 'resolver.test',
    'TLS bypass': (p) => p['dnsServices']['dnsA']['skip-cert-verify'] = true,
    'node DNS bypass': (p) => p['proxies']['nodeA']['dns'] = 'system',
    'same listener ports': (p) => p['listeners']['dnsPort'] = 17890,
    'bad listener': (p) => p['listeners']['mixedPort'] = 0,
    'half authentication': (p) => p['proxies']['nodeA']['username'] = 'secret',
  };
  for (final entry in badInputs.entries) {
    test('rejects ${entry.key}', () {
      final input = fixture();
      entry.value(input);
      expect(() => compile(input), throwsFormatException);
    });
  }

  for (final protocol in ['https', 'http', 'h3', 'doh', 'system']) {
    for (final bootstrap in [false, true]) {
      test('rejects $protocol including bootstrap=$bootstrap', () {
        final input = fixture();
        (bootstrap
                ? input['bootstrapDns']
                : input['dnsServices']['dnsA'])['protocol'] =
            protocol;
        expect(() => compile(input), throwsFormatException);
      });
    }
  }

  test('model freezes caller-owned collections', () {
    final input = fixture();
    final model = ManagedPolicy.fromJson(input);
    final original = compileManagedProfile(model);
    input['groups']['a'].clear();
    input['domainRules'].clear();
    expect(compileManagedProfile(model), original);
    expect(() => model.groups['a']!.clear(), throwsUnsupportedError);
    expect(() => model.domainRules.clear(), throwsUnsupportedError);
  });

  test('reference diagnostics identify the source field without its value', () {
    final input = fixture();
    input['domainDefault']['target']['group'] = 'private_missing_group';
    expect(
      () => compile(input),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'location',
          allOf(
            contains('policy.domainDefault.target'),
            isNot(contains('private_missing_group')),
          ),
        ),
      ),
    );
  });

  test(
    'addresses normalize without adding DNS and IP prefixes stay explicit',
    () {
      final input = fixture();
      input['ipRules'][0]['cidr'] = '127.1.2.3/8';
      input['ipRules'][1]['cidr'] = 'fd12:3456::ab/64';
      input['domainRules'][0]['value'] = 'EXAMPLE.TEST';
      final model = ManagedPolicy.fromJson(input);
      expect(model.ipRules[0].cidr, '127.0.0.0/8');
      expect(model.ipRules[1].cidr, 'fd12:3456::/64');
      expect(model.domainRules[0].value, 'example.test');
    },
  );

  test('authentication round-trips without leaking rejected values', () {
    for (final password in ['x' * 255, '雪' * 85, r'a: # "quote" \\ value']) {
      final input = fixture();
      input['proxies']['nodeA']['username'] = 'synthetic';
      input['proxies']['nodeA']['password'] = password;
      final config = loadYaml(compile(input));
      expect(config['proxies'][0]['password'], password);
    }
    for (final password in [
      '',
      'x' * 256,
      '雪' * 86,
      'private\ntext',
      'secret\u0000',
      '\uD800',
    ]) {
      final input = fixture();
      input['proxies']['nodeA']['username'] = 'synthetic';
      input['proxies']['nodeA']['password'] = password;
      try {
        compile(input);
        fail('invalid authentication accepted');
      } on FormatException catch (error) {
        expect(error.source, isNull);
        if (password.length > 1) {
          expect(error.message, isNot(contains(password)));
        }
      }
    }
  });

  test('local writer replaces atomically with private permissions', () async {
    final directory = await Directory.systemTemp.createTemp('managed-writer-');
    addTearDown(() => directory.delete(recursive: true));
    final output = File('${directory.path}/config.yaml');
    await output.writeAsString('previous');
    final yaml = compile(fixture());
    await writeManagedProfile(output.path, yaml);
    expect(await output.readAsString(), yaml);
    expect((await output.stat()).mode & 0x1ff, 0x180);
    expect(await directory.list().length, 1);
  }, skip: Platform.isWindows);

  test(
    'macOS writer removes inherited ACL while preserving parent ACL',
    () async {
      final directory = await Directory.systemTemp.createTemp('managed-acl-');
      addTearDown(() => directory.delete(recursive: true));
      const ace =
          'everyone allow read,execute,readattr,readextattr,readsecurity,'
          'file_inherit,directory_inherit';
      final seed = await Process.run('/bin/chmod', ['+a', ace, directory.path]);
      expect(seed.exitCode, 0);
      Future<List<String>> aclEntries(String path) async {
        final result = await Process.run('/bin/ls', ['-lde', path]);
        expect(result.exitCode, 0);
        return (result.stdout as String)
            .split('\n')
            .where((line) => RegExp(r'^\s*\d+:').hasMatch(line))
            .toList();
      }

      final parentAcl = await aclEntries(directory.path);
      expect(parentAcl, isNotEmpty);
      final output = await File(
        '${directory.path}/config.yaml',
      ).writeAsString('old-synthetic');
      await Process.run('/bin/chmod', ['600', output.path]);
      expect((await output.stat()).mode & 0x1ff, 0x180);
      expect(await aclEntries(output.path), isNotEmpty);
      await writeManagedProfile(output.path, 'new-synthetic-secret');
      expect(await output.readAsString(), 'new-synthetic-secret');
      expect((await output.stat()).mode & 0x1ff, 0x180);
      expect(await aclEntries(output.path), isEmpty);
      expect(await aclEntries(directory.path), parentAcl);
      expect(await directory.list().length, 1);
    },
    skip: !Platform.isMacOS,
  );

  test('permission and rename failures preserve old destination', () async {
    final directory = await Directory.systemTemp.createTemp('managed-io-');
    addTearDown(() => directory.delete(recursive: true));
    final output = File('${directory.path}/previous.yaml');
    await output.writeAsString('previous');
    await Process.run('/bin/chmod', ['500', directory.path]);
    try {
      await expectLater(
        writeManagedProfile(output.path, 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await output.readAsString(), 'previous');
    } finally {
      await Process.run('/bin/chmod', ['700', directory.path]);
    }
    final target = await Directory('${directory.path}/occupied').create();
    final sentinel = await File(
      '${target.path}/previous',
    ).writeAsString('previous');
    await expectLater(
      writeManagedProfile(target.path, 'new'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await sentinel.readAsString(), 'previous');
    expect(await directory.list().length, 2);
  }, skip: Platform.isWindows);
}
