import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/config_input.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/failing_preferences.dart';
import '../helpers/policy_core_bridge.dart';
import '../helpers/test_policy_drafts.dart';

class _Native extends Mock implements Service {}

class _Core extends Mock implements CoreHandlerInterface {}

class _FailRollbackSetting extends AppSetting {
  int writes = 0;
  @override
  set value(AppSettingProps next) {
    if (++writes == 2) throw StateError('synthetic-publication-secret');
    super.value = next;
  }
}

class _Inputs extends ApplicationInputAction {
  _Inputs(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _Selections extends PolicySelectionAction {
  _Selections(this.client);
  final Request client;
  @override
  Request get requestClient => client;
  @override
  bool get supportsManaged => true;
}

class _Fixture {
  _Fixture(this.bridge, this.db, this.client, this.draft, this.raw, this.home);
  final PolicyCoreBridge bridge;
  final Database db;
  final Request client;
  final PolicyDraftDocument draft;
  final String raw;
  final String home;
  late final ProviderContainer container;
  final failures = <ConfigApplyResult>[];
  final failurePayloads = <Map<String, Object?>>[];
  Future<void> Function()? afterComplete;
  final inputs = <ConfigInput>[];

  static Future<_Fixture> open(
    String executable, {
    bool failRollbackPublication = false,
  }) async {
    final home = await appPath.homeDirPath;
    await Directory(home).create(recursive: true);
    final bridge = PolicyCoreBridge(
      await Process.start(
        executable,
        [r'-test.run=^TestApplicationInputBridge$'],
        workingDirectory: Directory('core').absolute.path,
        environment: {
          'FLCLASH_APPLICATION_INPUT_BRIDGE_HOME': home,
          'FLCLASH_MANAGED_PROFILE_COMPILER':
              '${File(executable).parent.path}/managed_profile_compiler',
        },
      ),
    );
    final draft = PolicyDraftDocument.decode(
      jsonEncode({'draftVersion': 1, 'policy': await bridge.call('fixture')}),
    );
    final raw = selectPolicyDraft(
      draft,
      maintenanceProxyTarget: {'kind': 'group', 'id': 'a'},
    );
    final db = Database(NativeDatabase.memory());
    database = db;
    await db.profilesDao.putAll([
      draftTestProfile(1)
          .copyWith(
            selectedMap: {'fc-managed-group-a': 'fc-managed-proxy-nodeA'},
          )
          .toCompanion(),
      draftTestProfile(2).toCompanion(),
    ]);
    for (final id in [1, 2]) {
      await db.profilePolicyDraftsDao.compareAndWrite(
        id,
        expectedRaw: null,
        rawContent: draft.encode(),
      );
      await db.profilePolicySelectionsDao.compareAndWrite(
        id,
        expected: null,
        selection: ProfilePolicySelection(profileId: id, rawContent: raw),
      );
    }
    final native = _Native();
    final client = Request.scoped(native: native, isAndroid: true);
    final fixture = _Fixture(bridge, db, client, draft, raw, home);
    when(() => native.requestControl(any())).thenAnswer((call) async {
      final value = Map<String, Object?>.from(
        call.positionalArguments.first as Map,
      );
      final response = await bridge.call('control', value);
      if (value['action'] == 'complete' && fixture.afterComplete != null) {
        final action = fixture.afterComplete!;
        fixture.afterComplete = null;
        await action();
      }
      return response;
    });
    when(native.getRequestState).thenAnswer((_) => bridge.call('nativeState'));
    final core = _Core();
    when(
      core.getConfigState,
    ).thenAnswer((_) async => ConfigFact.fromJson(await bridge.call('fact')));
    when(() => core.failConfigBuild(any())).thenAnswer((call) async {
      final payload = Map<String, Object?>.from(
        call.positionalArguments.first as Map,
      );
      fixture.failurePayloads.add(payload);
      final result = ConfigApplyResult.fromJson(
        await bridge.call('fail', payload),
      );
      fixture.failures.add(result);
      return result;
    });
    fixture.container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        applicationInputActionProvider.overrideWith(() => _Inputs(client)),
        policySelectionActionProvider.overrideWith(() => _Selections(client)),
        if (failRollbackPublication)
          appSettingProvider.overrideWith(_FailRollbackSetting.new),
      ],
    );
    fixture.container.listen(configProvider, (_, _) {});
    client.attach(fixture.container);
    await client.ready();
    return fixture;
  }

  Future<ConfigInput> input(int id) async {
    final finalProfile = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '$home/profiles',
        profileId: id,
        rawConfig: {
          'mode': 'direct',
          'rules': ['MATCH,DIRECT'],
        },
        realPatchConfig: const PatchClashConfig(),
        overrideDns: true,
        overrideNtp: true,
        appendSystemDns: true,
        proxyGroups: [],
        rules: [],
        addedRules: [],
        defaultUA: 'synthetic',
        policySelection: ProfilePolicySelection(profileId: id, rawContent: raw),
      ),
    );
    final fact = ConfigFact.fromJson(await bridge.call('fact'));
    final input = await client.mutate(
      () async => ConfigInput.write(
        home: home,
        yaml: finalProfile.yaml,
        runtimeEpoch: fact.runtimeEpoch,
        profileId: id,
        profileName: 'Synthetic profile $id',
        selectedMap: {},
        testUrl: container.read(appSettingProvider).testUrl,
        managedPolicy: SelectedPolicy.decode(raw).descriptor,
        sources: [
          await client.captureSource('profile:$id'),
          await client.captureSource('application-config'),
        ],
      ),
    );
    inputs.add(input);
    return input;
  }

  Future<ConfigApplyResult> apply(
    ConfigInput input,
    ConfigFact expected,
  ) async {
    final registered = await bridge.call(
      'register',
      input.toRequest(active: true, expectedConfig: expected.fence),
    );
    final prepared = ConfigApplyResult.fromJson(
      await bridge.call('prepare', registered),
    );
    expect(prepared.status, 'prepared');
    final installed = ConfigApplyResult.fromJson(
      await bridge.call('install', prepared.receipt),
    );
    expect(installed.status, 'installed');
    final accepted = ConfigApplyResult.fromJson(
      await bridge.call('activate', installed.receipt),
    );
    expect(accepted.status, 'activated');
    return accepted;
  }

  Future<ConfigFact> activate() async {
    final candidate = await input(1);
    return (await apply(
      candidate,
      ConfigFact.fromJson(await bridge.call('fact')),
    )).fact;
  }

  Future<void> expectClosed(Map<String, Object?> before) async {
    expect(
      ConfigFact.fromJson(await bridge.call('fact')).businessActive,
      isFalse,
    );
    final after = await bridge.call(
      'probe',
      'unique-after-mutation-failure.example.test',
    );
    expect(after['businessFailed'], isTrue);
    expect(after['dnsFailed'], isTrue);
    expect(after['dnsCounts'], before['dnsCounts']);
    expect(after['proxyCounts'], before['proxyCounts']);
  }

  Future<void> close() async {
    await client.clearPartialCommit();
    for (final input in inputs) {
      await input.releaseMarker();
    }
    await client.detach();
    container.dispose();
    await bridge.close();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final executable = Platform.environment['FLCLASH_APPLICATION_INPUT_BRIDGE'];
  late Directory root;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.isInit;
    await AppLocalizations.load(const Locale('en'));
    root = await Directory.systemTemp.createTemp('policy-mutation-failure-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
  });
  tearDownAll(() => root.delete(recursive: true));

  for (final first in [
    PreferenceWrite.failAfterWrite,
    PreferenceWrite.throwAfterWrite,
  ]) {
    for (final compensation in [
      PreferenceWrite.pass,
      PreferenceWrite.fail,
      PreferenceWrite.throwError,
    ]) {
      test(
        'settings failure closes its revoked input; $first / $compensation',
        () async {
          final fixture = await _Fixture.open(executable!);
          addTearDown(fixture.close);
          await fixture.activate();
          final before = await fixture.bridge.call(
            'probe',
            'before-failure.example.test',
          );
          expect(before['body'], 'A');
          final previous = fixture.container.read(appSettingProvider).testUrl;
          final originalCompleter = preferences.sharedPreferencesCompleter;
          final actual = (await originalCompleter.future)!;
          final failing = FailingPreferences(actual, [first, compensation]);
          preferences.sharedPreferencesCompleter =
              Completer<SharedPreferences?>()..complete(failing);
          Object? failure;
          try {
            await fixture.container
                .read(applicationInputActionProvider.notifier)
                .updateAppSetting(
                  (value) => value.copyWith(
                    testUrl: 'https://synthetic-preference-secret.test',
                  ),
                );
          } catch (error) {
            failure = error;
          } finally {
            preferences.sharedPreferencesCompleter = originalCompleter;
          }
          final partial = compensation != PreferenceWrite.pass;
          expect(failure, isA<RequestUnavailable>());
          expect(
            (failure as RequestUnavailable).code,
            partial ? 'request_partial_commit' : 'preferences_save_failed',
          );
          expect(
            failure.toString(),
            isNot(contains('synthetic-preference-secret')),
          );
          expect(failing.writes, 2);
          expect(fixture.container.read(appSettingProvider).testUrl, previous);
          expect(fixture.client.partialCommit, partial);
          expect(
            await File('${fixture.home}/request-recovery-required').exists(),
            partial,
          );
          final persisted = Config.fromJson(
            jsonDecode(actual.getString(configKey)!) as Map<String, dynamic>,
          );
          expect(
            persisted.appSettingProps.testUrl,
            partial ? 'https://synthetic-preference-secret.test' : previous,
          );
          expect(fixture.failures.single.status, 'blocked');
          await fixture.expectClosed(before);
        },
        skip: executable == null,
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }

  test(
    'rollback publication failure retains recovery marker and closes revoked input',
    () async {
      final fixture = await _Fixture.open(
        executable!,
        failRollbackPublication: true,
      );
      addTearDown(fixture.close);
      await fixture.activate();
      final before = await fixture.bridge.call(
        'probe',
        'before-publication-failure.example.test',
      );
      final originalCompleter = preferences.sharedPreferencesCompleter;
      final actual = (await originalCompleter.future)!;
      final failing = FailingPreferences(actual, [
        PreferenceWrite.failAfterWrite,
      ]);
      preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
        ..complete(failing);
      try {
        await expectLater(
          fixture.container
              .read(applicationInputActionProvider.notifier)
              .updateAppSetting(
                (value) => value.copyWith(testUrl: 'https://changed.test'),
              ),
          throwsA(
            isA<RequestUnavailable>()
                .having((e) => e.code, 'code', 'request_partial_commit')
                .having(
                  (e) => e.toString().contains('synthetic-'),
                  'contains secret',
                  isFalse,
                ),
          ),
        );
      } finally {
        preferences.sharedPreferencesCompleter = originalCompleter;
      }
      expect(failing.writes, 1);
      expect(
        fixture.container.read(appSettingProvider).testUrl,
        'https://changed.test',
      );
      expect(
        Config.fromJson(
          jsonDecode(actual.getString(configKey)!) as Map<String, dynamic>,
        ).appSettingProps.testUrl,
        'https://changed.test',
      );
      expect(fixture.client.partialCommit, isTrue);
      expect(
        await File('${fixture.home}/request-recovery-required').exists(),
        isTrue,
      );
      expect(fixture.failures.single.status, 'blocked');
      await fixture.expectClosed(before);
    },
    skip: executable == null,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  for (final mode in ['selection SQL', 'picks SQL', 'newer owner']) {
    test(
      'selection failure converges conditionally: $mode',
      () async {
        final fixture = await _Fixture.open(executable!);
        addTearDown(fixture.close);
        final observed = await fixture.activate();
        final before = await fixture.bridge.call(
          'probe',
          'before-selection-failure.example.test',
        );
        expect(before['body'], 'A');
        ConfigApplyResult? newer;
        if (mode == 'newer owner') {
          final second = await fixture.input(2);
          fixture.afterComplete = () async {
            for (final source in second.sources) {
              expect(await fixture.client.configSourceCurrent(source), isTrue);
            }
            newer = await fixture.apply(
              second,
              ConfigFact.fromJson(await fixture.bridge.call('fact')),
            );
          };
        }
        final table = mode == 'picks SQL'
            ? 'profiles'
            : 'profile_policy_selections';
        final operation = mode == 'picks SQL' ? 'UPDATE' : 'INSERT';
        await fixture.db.customStatement(
          "CREATE TRIGGER fail_selection_write BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'synthetic-sql-secret'); END",
        );
        Object? failure;
        try {
          await fixture.container
              .read(policySelectionActionProvider.notifier)
              .selectConfirmed(
                1,
                expected: ProfilePolicySelection(
                  profileId: 1,
                  rawContent: fixture.raw,
                ),
                draftRaw: fixture.draft.encode(),
                selectionRaw: selectPolicyDraft(
                  fixture.draft,
                  maintenanceProxyTarget: {'kind': 'group', 'id': 'b'},
                ),
              );
        } catch (error) {
          failure = error;
        }
        expect(failure, isA<RequestUnavailable>());
        expect(failure.toString(), isNot(contains('synthetic-sql-secret')));
        expect(
          (await fixture.db.profilePolicySelectionsDao.query(1).getSingle())
              .rawContent,
          fixture.raw,
        );
        expect(
          fixture.failurePayloads.single['registeredToken'],
          observed.token,
        );
        expect(
          (fixture.failurePayloads.single['expected'] as Map)['owner'],
          observed.owner,
        );
        if (mode == 'newer owner') {
          expect(newer!.fact.owner, isNot(observed.owner));
          expect(fixture.failures.single.status, 'superseded');
          final fact = ConfigFact.fromJson(await fixture.bridge.call('fact'));
          expect(fact.owner, newer!.fact.owner);
          expect(fact.businessActive, isTrue);
          final result = await fixture.bridge.call(
            'probe',
            'new-owner-survives.example.test',
          );
          expect(result['body'], 'A');
          expect(result['dnsFailed'], isFalse);
        } else {
          expect(fixture.failures.single.status, 'blocked');
          await fixture.expectClosed(before);
        }
      },
      skip: executable == null,
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
