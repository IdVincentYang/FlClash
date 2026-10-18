import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/profile_refresh.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Bridge {
  _Bridge(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final response = jsonDecode(line) as Map;
          if (response.containsKey('id')) {
            _pending.remove(response['id'])?.complete(response['result']);
          }
        });
    process.stderr.drain<void>();
  }
  final Process process;
  final _pending = <int, Completer<Object?>>{};
  int sequence = 0;
  Future<Object?> call(String method, [Object? arguments]) {
    final id = ++sequence;
    final result = _pending[id] = Completer<Object?>();
    process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'arguments': arguments}),
    );
    return result.future.timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
}

class _Core extends CoreHandlerInterface {
  _Core(this.native, this.bridge);
  final Service native;
  final _Bridge bridge;
  int failures = 0;
  @override
  Future<ConfigFact> getConfigState() async => ConfigFact.fromJson(
    Map<String, dynamic>.from(
      (await bridge.call('snapshot') as Map)['fact'] as Map,
    ),
  );
  @override
  Future<ConfigApplyResult> failConfigBuild(Map<String, Object?> input) async {
    failures++;
    return ConfigApplyResult.fromJson(
      Map<String, dynamic>.from(await native.failConfigBuild(input)),
    );
  }

  @override
  Future<String> validateConfig(String path) async => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Requests extends Request {
  _Requests(this.native, this.bridge, this.cleanupFailure)
    : super.scoped(native: native, isAndroid: false);
  final Service native;
  final _Bridge bridge;
  final String cleanupFailure;
  int datasetInvalidations = 0;
  @override
  Future<Map<String, Object?>?> captureNativeRunState() =>
      native.getRequestState();
  @override
  Future<void> invalidate(String key) async {
    await super.invalidate(key);
    await bridge.call('revokeCleanupFixture', cleanupFailure);
  }

  @override
  Future<void> invalidateDataset({String? committingId}) async {
    datasetInvalidations++;
    await super.invalidateDataset(committingId: committingId);
  }
}

class _StoredProfiles extends TestProfiles {
  _StoredProfiles(this.reject);
  final bool reject;
  @override
  Future<Profile> persistRefresh(Profile profile, {required bool importing}) {
    if (reject) throw StateError('synthetic persistence failure');
    return super.persistRefresh(profile, importing: importing);
  }
}

class _Profiles extends ProfilesAction {
  _Profiles(this.requests);
  final Request requests;
  @override
  Request get requestClient => requests;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final classpath = Platform.environment['L2_JVM_BRIDGE_CLASSPATH'];
  late Directory root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('refresh-cleanup-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
    );
  });
  tearDownAll(() => root.delete(recursive: true));

  for (final mode in ['false', 'throw']) {
    for (final newerOwner in [false, true]) {
      test(
        'JVM cleanup $mode preserves recovery across ${newerOwner ? 'a newer Owner' : 'its own superseded retry'} and gates automatic successors',
        () async {
          final saved = mode != 'throw' || newerOwner;
          SharedPreferences.setMockInitialValues({});
          final bridge = _Bridge(
            await Process.start(Platform.environment['L2_JAVA'] ?? 'java', [
              '-cp',
              classpath!,
              'com.follow.clash.ConfigApplyBridge',
            ]),
          );
          final native = Service();
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            native.methodChannel,
            (call) => bridge.call(call.method, call.arguments),
          );
          final store = Database(NativeDatabase.memory());
          database = store;
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final entered = Completer<void>(), release = Completer<void>();
          final received = <String>[];
          server.listen((request) async {
            received.add(request.uri.path);
            if (!entered.isCompleted) entered.complete();
            await release.future;
            request.response.write('mode: rule\nrules: ["MATCH,DIRECT"]\n');
            await request.response.close();
          });
          final requests = _Requests(native, bridge, mode);
          final core = _Core(native, bridge);
          final b = Profile(
            id: 2,
            label: 'B',
            url: 'http://127.0.0.1:${server.port}/2',
            requestMode: RequestMode.direct,
            autoUpdate: false,
            autoUpdateDuration: const Duration(days: 1),
          );
          final c = b.copyWith(
            id: 3,
            label: 'C',
            url: 'http://127.0.0.1:${server.port}/3',
            autoUpdate: true,
          );
          await store.profilesDao.putAll([b.toCompanion(), c.toCompanion()]);
          final container = ProviderContainer(
            overrides: [
              profilesProvider.overrideWith(() => _StoredProfiles(!saved)),
              profilesActionProvider.overrideWith(() => _Profiles(requests)),
              setupActionProvider.overrideWith(
                () => SetupAction.scoped(
                  isAndroid: true,
                  native: native,
                  requests: requests,
                ),
              ),
              coreHandlerProvider.overrideWithValue(
                CoreController.scoped(core),
              ),
              currentProfileIdProvider.overrideWithBuild((_, _) => 1),
            ],
          );
          globalState.container = container;
          container.listen(configProvider, (_, _) {});
          container.read(initProvider.notifier).value = true;
          requests.attach(container);
          final marker = File(
            '${await appPath.homeDirPath}/request-recovery-required',
          );
          try {
            expect(await bridge.call('startCleanupFixture'), true);
            final setup = container.read(setupActionProvider.notifier);
            final original = (await setup.captureConfigFailure(requests))!;
            final action = container.read(profilesActionProvider.notifier);
            final refresh = action.updateProfile(b);
            final settled = refresh.then<Object>(
              (result) => result,
              onError: (Object error) => error,
            );
            await entered.future;
            await action.autoUpdateProfiles();
            release.complete();
            final result = await settled.timeout(const Duration(seconds: 5));
            if (saved) {
              expect(result, isA<ProfileRefreshResult>());
              final refreshResult = result as ProfileRefreshResult;
              expect(refreshResult.materialSaved, true);
              expect(
                refreshResult.application,
                ProfileApplicationOutcome.failed,
              );
              expect(refreshResult.failure, 'profile_saved_recovery_required');
            } else {
              expect(
                result,
                isA<RequestUnavailable>().having(
                  (e) => e.code,
                  'code',
                  'request_partial_commit',
                ),
              );
            }
            expect(core.failures, 1);
            expect(requests.partialCommit, true);
            expect(await marker.exists(), true);
            expect(
              (await store.profilesDao.query().get())
                  .getProfile(2)!
                  .lastUpdateDate,
              saved ? isNotNull : isNull,
            );
            expect((await core.getConfigState()).replayEligible, false);
            if (newerOwner) {
              expect(await bridge.call('startCleanupFixture'), true);
            }
            final beforeRetry = await bridge.call('snapshot') as Map;
            final retry = await native.failConfigBuild({
              'expected': original.fact.fence,
              'expectedRun': original.nativeRun,
              'registeredToken': original.registeredToken,
            });
            expect(retry['status'], 'superseded');
            await setup.finishConfigFailure(original, requests: requests);
            final afterRetry = await bridge.call('snapshot') as Map;
            expect(afterRetry['stops'], beforeRetry['stops']);
            expect(
              (afterRetry['fact'] as Map)['owner'],
              (beforeRetry['fact'] as Map)['owner'],
            );
            if (newerOwner) {
              expect((afterRetry['fact'] as Map)['businessActive'], true);
            }
            expect(requests.partialCommit, true);
            expect(await marker.exists(), true);
            expect(requests.datasetInvalidations, 0);
            await action.autoUpdateProfiles();
            await pumpEventQueue();
            expect(received, ['/2']);
            final reattached = Request.scoped(native: native, isAndroid: true)
              ..attach(container);
            await reattached.ready();
            expect(reattached.partialCommit, true);
            await reattached.detach();
          } finally {
            if (!release.isCompleted) release.complete();
            container.dispose();
            await requests.detach();
            await server.close(force: true);
            await store.close();
            await bridge.close();
            messenger.setMockMethodCallHandler(native.methodChannel, null);
            await for (final entry in root.list()) {
              await entry.delete(recursive: true);
            }
          }
        },
        skip: classpath == null
            ? 'Requires the compiled JVM bridge classpath.'
            : false,
      );
    }
  }
}
