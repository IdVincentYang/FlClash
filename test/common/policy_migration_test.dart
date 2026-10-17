import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/policy_draft.dart';
import 'package:fl_clash/common/policy_migration.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_policy_drafts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('policy-capture-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    db = Database(NativeDatabase.memory());
    database = db;
    await db.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
    File(await appPath.getProfilePath('1'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'rules:\n  - DOMAIN,source.test,DIRECT\n  - MATCH,REJECT\n',
      );
  });
  tearDown(() => db.close());

  Future<PolicyDraftDocument> capture() => captureProfilePolicyDraft(
    1,
    applicationSettings: () => {
      'patch': {
        'mode': 'rule',
        'dns': {'synthetic': true},
      },
      'overrideDns': false,
    },
  );

  Future<void> link(
    Rule rule,
    int? profile,
    RuleScene? scene,
    String order,
  ) async {
    await db.into(db.rules).insertOnConflictUpdate(rule.toCompanion());
    await db
        .into(db.profileRuleLinks)
        .insert(
          ProfileRuleLink(
            profileId: profile,
            ruleId: rule.id,
            scene: scene,
            order: order,
          ).toCompanion(),
        );
  }

  final badResources = <String, void Function(Map<String, dynamic>)>{
    'hostname server': (p) => p['proxies'][0]['server'] = 'synthetic.test',
    'missing server': (p) => (p['proxies'][0] as Map).remove('server'),
    'missing port': (p) => (p['proxies'][0] as Map).remove('port'),
    'out of range port': (p) => p['proxies'][0]['port'] = 65536,
    'unpaired credentials': (p) => (p['proxies'][0] as Map).remove('password'),
    'invalid credentials': (p) => p['proxies'][0]['password'] = '',
    'invalid UDP value': (p) => p['proxies'][0]['udp'] = 'yes',
    'null UDP value': (p) => p['proxies'][0]['udp'] = null,
    'empty select group': (p) => p['proxy-groups'][0]['proxies'] = [],
    'duplicate select members': (p) =>
        p['proxy-groups'][0]['proxies'] = ['node', 'node'],
    'non-list proxy material': (p) => p['proxies'] = 42,
    'non-list group material': (p) => p['proxy-groups'] = 42,
  };
  for (final entry in badResources.entries) {
    test(
      'captured ${entry.key} stays blocked after candidate repairs',
      () async {
        final source = <String, dynamic>{
          'rules': ['MATCH,REJECT'],
          'proxies': [
            <String, dynamic>{
              'name': 'node',
              'type': 'socks5',
              'server': '127.0.0.1',
              'port': 1080,
              'username': 'synthetic-legacy-user',
              'password': 'synthetic-legacy-secret',
            },
          ],
          'proxy-groups': [
            {
              'name': 'group',
              'type': 'select',
              'proxies': ['node'],
            },
          ],
        };
        entry.value(source);
        final raw = jsonEncode(source);
        File(await appPath.getProfilePath('1')).writeAsStringSync(raw);
        final draft = await capture();
        final snapshot = jsonEncode(draft.migration);
        final issues = policyMigrationIssues(draft.migration);
        expect(issues.any((i) => i.code == 'resources'), isTrue);
        expect(
          issues.map((i) => i.location).join(),
          matches(r'proxies|groups'),
        );
        expect(issues.toString(), isNot(contains('synthetic-legacy')));
        expect(utf8.decode(base64Decode(draft.migration!['sourceBytes'])), raw);
        draft.policy
          ..clear()
          ..addAll(completePolicyDraft().policy);
        expect(policyDraftInputProblem(draft), 'migration');
        draft.policy
          ..['domainRules'] = []
          ..['ipRules'] = []
          ..['domainDefault'] = {
            'target': {'kind': 'reject'},
          }
          ..['ipDefault'] = {'kind': 'reject'}
          ..['proxies'] = <String, dynamic>{}
          ..['groups'] = <String, dynamic>{};
        expect(jsonEncode(draft.migration), snapshot);
        await db.profilePolicyDraftsDao.compareAndWrite(
          1,
          expectedRaw: null,
          rawContent: draft.encode(),
        );
        final row = await db.profilePolicyDraftsDao.query(1).getSingle();
        final reopened = PolicyDraftDocument.decode(row.rawContent);
        expect(jsonEncode(reopened.migration), snapshot);
        expect(
          () => previewPolicyDraft(reopened),
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
  }

  test(
    'real standard DAO orders profile before global, filters disabled, retains source and raw snapshot',
    () async {
      await link(
        Rule.parse('DOMAIN,global.test,DIRECT', id: 1),
        null,
        null,
        'a',
      );
      await link(
        Rule.parse('DOMAIN,profile.test,REJECT', id: 2),
        1,
        RuleScene.added,
        'z',
      );
      await link(
        Rule.parse('IP-CIDR,10.0.0.0/8,REJECT', id: 3),
        null,
        null,
        'b',
      );
      await db
          .into(db.profileRuleLinks)
          .insert(
            const ProfileRuleLink(
              profileId: 1,
              ruleId: 3,
              scene: RuleScene.disabled,
            ).toCompanion(),
          );
      final draft = await capture();
      final analysis = analyzePolicyMigration(draft.migration);
      expect(analysis.rules, [
        'DOMAIN,profile.test,REJECT',
        'DOMAIN,global.test,DIRECT',
        'DOMAIN,source.test,DIRECT',
        'MATCH,REJECT',
      ]);
      expect(analysis.origins, ['profile', 'global', 'source', 'source']);
      expect(analysis.issues, isEmpty);
      expect(draft.migration!['links'], hasLength(4));
      expect(
        utf8.decode(base64Decode(draft.migration!['sourceBytes'])),
        File(await appPath.getProfilePath('1')).readAsStringSync(),
      );
      expect(
        draft.migration!['applicationSettings']['patch']['dns']['synthetic'],
        isTrue,
      );
      expect(await db.profilePolicyDraftsDao.query().get(), isEmpty);
    },
  );

  test(
    'custom IP REJECT remains active despite a same-ID disabled link',
    () async {
      await db.profilesDao.putAll([
        draftTestProfile(
          1,
        ).copyWith(overwriteType: OverwriteType.custom).toCompanion(),
      ]);
      await link(
        Rule.parse('IP-CIDR,10.0.0.0/8,REJECT,no-resolve', id: 4),
        1,
        RuleScene.custom,
        'a',
      );
      await db
          .into(db.profileRuleLinks)
          .insert(
            const ProfileRuleLink(
              profileId: 1,
              ruleId: 4,
              scene: RuleScene.disabled,
            ).toCompanion(),
          );
      final analysis = analyzePolicyMigration((await capture()).migration);
      expect(analysis.rules, ['IP-CIDR,10.0.0.0/8,REJECT,no-resolve']);
      expect(analysis.origins, ['custom']);
      expect(analysis.issues.any((i) => i.code == 'ip'), isTrue);
    },
  );

  test(
    'script is stored as bytes without evaluation; missing source is never created',
    () async {
      await db.profilesDao.putAll([
        draftTestProfile(1)
            .copyWith(overwriteType: OverwriteType.script, scriptId: 9)
            .toCompanion(),
      ]);
      final script = File(await appPath.getScriptPath('9'))
        ..createSync(recursive: true)
        ..writeAsStringSync('throw new Error("must not execute");');
      final draft = await capture();
      expect(
        base64Decode(draft.migration!['scriptBytes']),
        script.readAsBytesSync(),
      );
      expect(policyMigrationIssues(draft.migration).single.code, 'script');
      final file = File(await appPath.getProfilePath('1'));
      await file.delete();
      await expectLater(capture(), throwsA(isA<FileSystemException>()));
      expect(await file.exists(), isFalse);
      expect(await db.profilePolicyDraftsDao.query().get(), isEmpty);
    },
  );
}
