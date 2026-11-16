import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/backup.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('empty-archive-');
    source = Database(NativeDatabase(File('${root.path}/source.sqlite')));
    await source.customSelect('SELECT 1').get();
  });
  tearDown(() async {
    await source.close();
    await root.delete(recursive: true);
  });

  Future<MigrationData> parse() async {
    final snapshot = '${root.path}/snapshot.sqlite';
    await source.customStatement('VACUUM INTO ?', [snapshot]);
    final archive = '${root.path}/backup.zip';
    await writeBackupArchive(
      archivePath: archive,
      configMap: {'version': 1, 'currentProfileId': 42},
      databaseSnapshotPath: snapshot,
      homeDirPath: root.path,
      entries: [],
    );
    return readBackupArchive(
      archivePath: archive,
      stagingDirPath: '${root.path}/staging',
    );
  }

  for (final revisionOnly in [false, true]) {
    test(
      'empty archive is Config-only with routing metadata $revisionOnly',
      () async {
        if (revisionOnly) {
          await source.writeApplicationRouting(
            const ApplicationRoutingSettings(),
          );
          expect((await source.readApplicationRouting()).revision, 1);
        }
        final data = await parse();
        expect(data.configMap!['currentProfileId'], 42);
        expect(data.profiles, isEmpty);
        expect(data.globalGroups, isNull);
        expect(data.applicationRouting, isNull);
      },
    );
  }

  test('a global group without profiles is business data', () async {
    const group = LocalProxyGroup(id: 7, name: 'Kept', nodes: ['node']);
    await source.writeGlobalGroups([group]);
    final data = await parse();
    expect(data.profiles, isEmpty);
    expect(data.globalGroups, [group]);
  });

  test('a disabled App rule without profiles is business data', () async {
    const rule = ApplicationRouteRule(packageName: 'fixture.app');
    await source.writeApplicationRouting(
      const ApplicationRoutingSettings(rules: {'fixture.app': rule}),
    );
    final data = await parse();
    expect(data.profiles, isEmpty);
    expect(data.applicationRouting!.rules, {'fixture.app': rule});
  });

  test('shared targets without App rules are business data', () async {
    const target = ApplicationRouteTarget(
      name: 'Kept',
      kind: ApplicationTargetKind.node,
    );
    await source.writeApplicationRouting(
      const ApplicationRoutingSettings(sharedTargets: {42: target}),
    );
    final data = await parse();
    expect(data.applicationRouting!.rules, isEmpty);
    expect(data.applicationRouting!.sharedTargets, {42: target});
  });

  test('Host rules without App rules are business data', () async {
    const rule = Rule(
      id: 7,
      ruleAction: RuleAction.DOMAIN,
      content: 'fixture.test',
      ruleTarget: 'DIRECT',
      hostBinding: HostRuleBinding(),
    );
    await source.rulesDao.putGlobalRule(rule);
    final data = await parse();
    expect(data.applicationRouting!.rules, isEmpty);
    expect(data.applicationRouting!.hostRules.single.id, 7);
    expect(data.rules.single.hostBinding, const HostRuleBinding());
  });

  test(
    'malformed routing in an otherwise empty database is not normalized',
    () async {
      await source.customStatement(
        "INSERT INTO application_routing_libraries(id, settings) VALUES (1, '{invalid')",
      );
      await expectLater(parse(), throwsFormatException);
    },
  );
}
