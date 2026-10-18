import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/config_input.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/policy_core_bridge.dart';
import '../helpers/test_policy_drafts.dart';

class _Native extends Mock implements Service {}

class _Core extends Mock implements CoreHandlerInterface {}

class _Inputs extends ApplicationInputAction {
  _Inputs(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

void main() {
  final executable = Platform.environment['FLCLASH_APPLICATION_INPUT_BRIDGE'];
  testWidgets(
    'real General testUrl action revokes a final written managed input before Core prepare',
    (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp(
          'application-input-bridge-',
        );
        AppPath.supportDirectory = () async => root;
        AppPath.temporaryDirectory = () async => root;
        AppPath.cacheDirectory = () async => root;
        final home = await appPath.homeDirPath;
        final bridge = PolicyCoreBridge(
          await Process.start(
            executable!,
            [r'-test.run=^TestApplicationInputBridge$'],
            workingDirectory: Directory('core').absolute.path,
            environment: {
              'FLCLASH_APPLICATION_INPUT_BRIDGE_HOME': home,
              'FLCLASH_MANAGED_PROFILE_COMPILER':
                  Platform.environment['FLCLASH_MANAGED_PROFILE_COMPILER'] ??
                  '${File(executable).parent.path}/managed_profile_compiler',
            },
          ),
        );
        final store = Database(NativeDatabase.memory());
        database = store;
        final draft = PolicyDraftDocument.decode(
          jsonEncode({
            'draftVersion': 1,
            'policy': await bridge.call('fixture'),
          }),
        );
        final raw = selectPolicyDraft(draft);
        await store.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
        await store.profilePolicySelectionsDao.compareAndWrite(
          1,
          expected: null,
          selection: ProfilePolicySelection(profileId: 1, rawContent: raw),
        );
        final native = _Native();
        when(() => native.requestControl(any())).thenAnswer(
          (call) => bridge.call('control', call.positionalArguments.first),
        );
        when(
          native.getRequestState,
        ).thenAnswer((_) => bridge.call('nativeState'));
        final core = _Core();
        when(core.getConfigState).thenAnswer(
          (_) async => ConfigFact.fromJson(await bridge.call('fact')),
        );
        when(() => core.failConfigBuild(any())).thenAnswer(
          (call) async => ConfigApplyResult.fromJson(
            await bridge.call('fail', call.positionalArguments.first),
          ),
        );
        final client = Request.scoped(native: native, isAndroid: true);
        final container = ProviderContainer(
          overrides: [
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            applicationInputActionProvider.overrideWith(() => _Inputs(client)),
            currentProfileIdProvider.overrideWithBuild((_, _) => 1),
          ],
        );
        globalState.container = container;
        container.listen(configProvider, (_, _) {});
        container.read(viewSizeProvider.notifier).value = const Size(800, 600);
        client.attach(container);
        await client.ready();
        try {
          final selection = SelectedPolicy.decode(raw);
          final finalProfile = await makeRealProfileTask(
            MakeRealProfileState(
              profilesPath: '$home/profiles',
              profileId: 1,
              rawConfig: {
                'mode': 'direct',
                'rules': ['MATCH,DIRECT'],
                'dns': {
                  'nameserver': ['system'],
                },
                'proxy-providers': {
                  'untrusted': {'type': 'http', 'url': 'https://invalid.test'},
                },
                'external-controller': '0.0.0.0:9090',
              },
              realPatchConfig: const PatchClashConfig(),
              overrideDns: true,
              overrideNtp: true,
              appendSystemDns: true,
              proxyGroups: [],
              rules: [],
              addedRules: [],
              defaultUA: 'synthetic',
              policySelection: ProfilePolicySelection(
                profileId: 1,
                rawContent: raw,
              ),
            ),
          );
          final before = ConfigFact.fromJson(await bridge.call('fact'));
          final input = await client.mutate(
            () async => ConfigInput.write(
              home: home,
              yaml: finalProfile.yaml,
              runtimeEpoch: before.runtimeEpoch,
              profileId: 1,
              profileName: 'synthetic',
              selectedMap: {},
              testUrl: container.read(appSettingProvider).testUrl,
              sources: [
                await client.captureSource('profile:1'),
                await client.captureSource('application-config'),
              ],
              managedPolicy: selection.descriptor,
            ),
          );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const TestApp(
                locale: Locale('en'),
                child: CommonScaffold(title: 'General', body: TestUrlItem()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(container.read(appSettingProvider).testUrl),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).last,
            'https://changed.test',
          );
          await tester.tap(find.text('Submit').last);
          await tester.pumpAndSettle();
          await dataMutations.run(() async {});
          expect(
            container.read(appSettingProvider).testUrl,
            'https://changed.test',
          );
          final after = ConfigFact.fromJson(await bridge.call('fact'));
          expect(
            after.version,
            before.version,
            reason: 'No Core hot write occurred',
          );
          final registered = await bridge.call(
            'register',
            input.toRequest(expectedConfig: before.fence),
          );
          final prepared = ConfigApplyResult.fromJson(
            await bridge.call('prepare', registered),
          );
          expect(prepared.status, 'superseded');
          expect(prepared.fact.owner, 0);
          await input.releaseMarker();

          final current = ConfigFact.fromJson(await bridge.call('fact'));
          final fresh = await client.mutate(
            () async => ConfigInput.write(
              home: home,
              yaml: finalProfile.yaml,
              runtimeEpoch: current.runtimeEpoch,
              profileId: 1,
              profileName: 'synthetic',
              selectedMap: {},
              testUrl: 'https://changed.test',
              sources: [
                await client.captureSource('profile:1'),
                await client.captureSource('application-config'),
              ],
              managedPolicy: selection.descriptor,
            ),
          );
          final next = await bridge.call(
            'register',
            fresh.toRequest(expectedConfig: current.fence),
          );
          final p = ConfigApplyResult.fromJson(
            await bridge.call('prepare', next),
          );
          expect(p.status, 'prepared');
          expect(
            ConfigApplyResult.fromJson(
              await bridge.call('install', p.receipt),
            ).status,
            'installed',
          );
          final accepted = ConfigApplyResult.fromJson(
            await bridge.call('activate', p.receipt),
          );
          expect(accepted.status, 'installedInactive');
          await container
              .read(applicationInputActionProvider.notifier)
              .updateAppSetting(
                (value) => value.copyWith(testUrl: 'https://later.test'),
              );
          final pending = ConfigFact.fromJson(await bridge.call('fact'));
          expect(pending.inputId, accepted.fact.inputId);
          expect(pending.phase, 'ready');
          expect(pending.replayEligible, isFalse);
          expect(
            container.read(appSettingProvider).testUrl,
            'https://later.test',
          );
          await fresh.releaseMarker();
          final live = await client.mutate(
            () async => ConfigInput.write(
              home: home,
              yaml: finalProfile.yaml,
              runtimeEpoch: pending.runtimeEpoch,
              profileId: 1,
              profileName: 'synthetic final task',
              selectedMap: {},
              testUrl: 'https://later.test',
              managedPolicy: selection.descriptor,
              sources: [
                await client.captureSource('profile:1'),
                await client.captureSource('application-config'),
              ],
            ),
          );
          final liveRegistered = await bridge.call(
            'register',
            live.toRequest(active: true, expectedConfig: pending.fence),
          );
          final livePrepared = ConfigApplyResult.fromJson(
            await bridge.call('prepare', liveRegistered),
          );
          expect(livePrepared.status, 'prepared');
          final liveInstalled = ConfigApplyResult.fromJson(
            await bridge.call('install', livePrepared.receipt),
          );
          expect(liveInstalled.status, 'installed');
          final liveAccepted = ConfigApplyResult.fromJson(
            await bridge.call('activate', liveInstalled.receipt),
          );
          expect(liveAccepted.status, 'activated');
          expect(liveAccepted.fact.policySha256, selection.digest);
          for (final entry in {
            'wide.example.test': 'A',
            'unmatched.other.test': 'B',
            'positive.lan.test': 'DIRECT',
            '127.0.0.1': 'DIRECT',
          }.entries) {
            final result = await bridge.call('probe', entry.key);
            expect(result['businessFailed'], isFalse, reason: entry.key);
            expect(result['body'], entry.value, reason: entry.key);
            expect(result['dnsFailed'], isFalse, reason: entry.key);
          }
          final rejected = await bridge.call('probe', 'blocked.denied.test');
          expect(rejected['businessFailed'], isTrue);
          expect(rejected['rcode'], 5);
          await bridge.call('stop');
          final stopped = await bridge.call(
            'probe',
            'new-after-stop.example.test',
          );
          expect(stopped['businessFailed'], isTrue);
          expect(stopped['dnsFailed'], isTrue);
          expect(stopped['dnsCounts'], rejected['dnsCounts']);
          await live.releaseMarker();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await bridge.close();
          container.dispose();
          await store.close();
          await root.delete(recursive: true);
        }
      });
    },
    skip: executable == null,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
