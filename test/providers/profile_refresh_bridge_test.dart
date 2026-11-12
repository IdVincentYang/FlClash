import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/local_proxy_groups.dart';
import 'package:fl_clash/common/profile_import.dart';
import 'package:fl_clash/common/config_input.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/source_review_loading.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/common/managed_material.dart';
import 'package:fl_clash/common/policy_draft.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml_writer/yaml_writer.dart';
import 'package:yaml/yaml.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/profile_refresh.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/source_review.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/policy_core_bridge.dart';
import '../plugins/code_forge/support.dart' show initEditorNative;
import '../helpers/boot_fixture.dart';
import '../helpers/test_profiles.dart';
import '../helpers/test_app.dart';

class _Native extends Mock implements Service {}

class _RecoverySetup extends SetupAction {
  _RecoverySetup(Service native, Request client)
    : super.scoped(isAndroid: true, native: native, requests: client);
  Completer<void>? postEntered, postGate;
  final outcomes = <ProfileApplicationOutcome>[];
  @override
  Future<ProfileApplicationOutcome> applyRefreshedProfile({
    required Future<bool> Function() isCurrent,
    required ConfigFact previous,
    Future<bool> Function()? canSubmit,
    bool allowSourceReview = true,
  }) async {
    postEntered?.complete();
    await postGate?.future;
    final result = await super.applyRefreshedProfile(
      isCurrent: isCurrent,
      previous: previous,
      canSubmit: canSubmit,
      allowSourceReview: allowSourceReview,
    );
    outcomes.add(result);
    return result;
  }
}

class _Selection extends PolicySelectionAction {
  _Selection(this.client);
  final Request client;
  @override
  bool get supportsManaged => true;
  @override
  Request get requestClient => client;
}

class _Backup extends BackupAction {
  _Backup(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _Shared extends Fake implements SharedState {}

class _StoredProfiles extends TestProfiles {
  _StoredProfiles(this.requests);
  final Request requests;
  @override
  Future<Profile> persist(
    Profile profile, {
    Iterable<int> renameIn = const [],
    bool networkResult = false,
  }) async {
    // Replace the global edit owner with the scoped Request in this fixture.
    if (!networkResult) await requests.invalidate('profile:${profile.id}');
    return super.persist(
      profile,
      renameIn: renameIn,
      networkResult: networkResult,
    );
  }

  int? failProfile;
  bool failPublication = false;
  Completer<void>? commitEntered, commitGate;
  @override
  Future<Profile> persistRefresh(
    Profile profile, {
    required bool importing,
  }) async {
    final gate = commitGate;
    commitGate = null;
    if (gate != null) {
      commitEntered?.complete();
      await gate.future;
    }
    if (profile.id == failProfile) throw StateError('synthetic DB failure');
    return super.persistRefresh(profile, importing: importing);
  }

  @override
  Future<void> publishRefresh() {
    if (failPublication) throw StateError('synthetic publication failure');
    return super.publishRefresh();
  }
}

class _Profiles extends ProfilesAction {
  _Profiles(this.client);
  final Request client;
  Completer<void>? materialDemandEntered;
  SourceConfirmation? reviewConfirmation;
  @override
  Request get requestClient => client;
  @override
  Future<void> presentSourceReview(
    Profile profile,
    Future<void> Function(SourceConfirmation, bool Function()) work,
  ) => reviewConfirmation == null
      ? super.presentSourceReview(profile, work)
      : work(reviewConfirmation!, () => true);
  @override
  Future<Profile?> ensureFile(
    Profile profile, {
    Future<bool> Function()? isCurrent,
  }) {
    final entered = materialDemandEntered;
    if (profile.id == 1 && entered != null && !entered.isCompleted) {
      entered.complete();
    }
    return super.ensureFile(profile, isCurrent: isCurrent);
  }
}

class _Scripts extends ScriptsAction {
  _Scripts(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _BridgeCore extends CoreHandlerInterface {
  _BridgeCore(this.bridge);
  final PolicyCoreBridge bridge;
  final calls = <CoreMethod>[];
  final sourceReviews = <Map<String, Object?>>[];
  Map<String, Object?>? pendingReviewInput;
  String? pendingReviewCandidate;
  final sourceActions = <String>[];
  Completer<void>? registerEntered, registerGate;
  Completer<void>? failureEntered, failureGate;
  Completer<void>? projectionEntered, projectionGate;
  Completer<void>? readEntered, readGate;
  String? nativeAfterActivation;
  String? inlineRejection;
  Map<String, dynamic> Function(Map<String, dynamic>)? materialReadOverride;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<T?> invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async {
    calls.add(method);
    final sourceAction = method == CoreMethod.sourceAcceptance
        ? (arguments as Map)['action']
        : null;
    if (sourceAction is String) sourceActions.add(sourceAction);
    if (sourceAction == 'adoptInline' && inlineRejection != null) {
      return {
            'status': 'deferred',
            'message': inlineRejection,
            'fact': await bridge.call('fact'),
          }
          as T;
    }

    if ((method == CoreMethod.getConfig || sourceAction == 'project') &&
        readGate != null) {
      final gate = readGate!;
      readGate = null;
      readEntered?.complete();
      await gate.future;
    }

    if (method == CoreMethod.failConfigBuild && failureGate != null) {
      final gate = failureGate!;
      failureGate = null;
      failureEntered?.complete();
      await gate.future;
    }
    if (method == CoreMethod.registerConfigInput && registerGate != null) {
      registerEntered?.complete();
      await registerGate!.future;
      registerGate = null;
    }
    if (method == CoreMethod.getTraffic ||
        method == CoreMethod.getTotalTraffic) {
      return {'up': 0, 'down': 0} as T;
    }
    final operation = switch (method) {
      CoreMethod.getConfigState => 'fact',
      CoreMethod.registerConfigInput => 'register',
      CoreMethod.prepareConfig => 'prepare',
      CoreMethod.installConfig => 'install',
      CoreMethod.activateConfig => 'activate',
      CoreMethod.failConfigBuild => 'fail',
      CoreMethod.validateConfig => 'refreshValidate',
      CoreMethod.getConfig => 'refreshRead',
      CoreMethod.releaseConfigInput => 'refreshRelease',
      CoreMethod.getProxies => 'refreshGroups',
      CoreMethod.getExternalProviders => 'refreshProviders',
      CoreMethod.sourceAcceptance => 'source',
      _ => throw UnsupportedError(method.name),
    };
    final response = await bridge.call(operation, arguments);
    if ((method == CoreMethod.activateConfig &&
                response['status'] == 'activated' ||
            sourceAction == 'adoptInline' &&
                (response['result'] as Map?)?['status'] == 'applied') &&
        nativeAfterActivation != null) {
      final native = await bridge.call('nativeState');
      native['revision'] = (native['revision'] as num).toInt() + 1;
      if (nativeAfterActivation == 'stop') {
        native['intentRevision'] =
            (native['intentRevision'] as num).toInt() + 1;
        native['intentRunning'] = false;
        native['phase'] = 'stopped';
        native['reason'] = 'userStop';
      }
      await bridge.call('control', {'action': 'publish', 'state': native});
    }
    if (method == CoreMethod.getProxies && projectionGate != null) {
      final gate = projectionGate!;
      projectionGate = null;
      projectionEntered?.complete();
      await gate.future;
    }
    if (response['error'] != null) {
      if (method == CoreMethod.sourceAcceptance) {
        final error = response['error'] as Map;
        throw CoreMethodException(
          code: error['code'] as String,
          message: error['message'] as String,
          details: error['details'],
        );
      }
      throw StateError('Synthetic Core request failed');
    }
    if (method == CoreMethod.sourceAcceptance) {
      final result = Map<String, dynamic>.from(response['result'] as Map);
      if (sourceAction == 'review' && result['status'] == 'reviewRequired') {
        pendingReviewInput = Map<String, Object?>.from(arguments as Map);
        pendingReviewCandidate = result['candidate'] as String;
      }
      if (sourceAction == 'review') {
        sourceReviews.add({
          'key': (arguments as Map)['key'],
          'status': result['status'],
          'reasons': result['reasons'],
        });
      }
      if (sourceAction == 'project' && materialReadOverride != null) {
        result['document'] = materialReadOverride!(
          Map<String, dynamic>.from(result['document'] as Map),
        );
      }
      return result as T;
    }
    if (method == CoreMethod.getConfig && materialReadOverride != null) {
      return materialReadOverride!(
            Map<String, dynamic>.from(response['value'] as Map),
          )
          as T?;
    }
    if (method == CoreMethod.prepareConfig ||
        method == CoreMethod.installConfig ||
        method == CoreMethod.activateConfig) {
      sourceReviews.add({
        'step': method.name,
        'status': response['status'],
        'message': response['message'],
      });
    }
    return (response.containsKey('value') ? response['value'] : response) as T?;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final executable = Platform.environment['FLCLASH_APPLICATION_INPUT_BRIDGE'];
  late Directory root;
  late Database store;
  late HttpServer server;
  late PolicyCoreBridge bridge;
  late _BridgeCore core;
  late Request client;
  late ProviderContainer container;
  var containerDisposed = false;
  var interactiveReview = false;
  SourceConfirmation? reviewOverride;
  late ProfilesAction profiles;
  late SetupAction setup;
  late _Native native;
  final received = <String>[];
  final confirmations = <SourceReview>[];
  final holds = <String, Completer<void>>{};
  final responses = <String, String>{};
  final statuses = <String, int>{};
  final controls = <Map<String, Object?>>[];
  String? ackFault;
  Completer<void>? nextNativeRead;
  const yaml =
      'mixed-port: 0\nmode: rule\ndns: {enable: false, nameserver: ["127.0.0.1:1"]}\nrules: ["MATCH,DIRECT"]\n';

  setUpAll(() async {
    registerFallbackValue(_Shared());
    feature = const Feature(customProviders: true);
    root = await Directory.systemTemp.createTemp('refresh-core-');
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
  tearDownAll(() {
    feature = const Feature();
    return root.delete(recursive: true);
  });
  setUp(() async {
    containerDisposed = false;
    interactiveReview = false;
    reviewOverride = null;
    SharedPreferences.setMockInitialValues({});
    received.clear();
    confirmations.clear();
    holds.clear();
    responses.clear();
    statuses.clear();
    controls.clear();
    ackFault = null;
    nextNativeRead = null;
    bridge = PolicyCoreBridge(
      await Process.start(
        executable!,
        [r'-test.run=^TestApplicationInputBridge$'],
        workingDirectory: Directory('core').absolute.path,
        environment: {'FLCLASH_APPLICATION_INPUT_BRIDGE_HOME': root.path},
      ),
    );
    await bridge.call('sourceState');
    core = _BridgeCore(bridge);
    store = Database(NativeDatabase.memory());
    database = store;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.path;
      received.add(name);
      try {
        if (holds[name] case final gate?) await gate.future;
        request.response.headers.noFolding('subscription-userinfo');
        request.response.headers.add(
          'subscription-userinfo',
          'upload=bad; broken;',
        );
        request.response.headers.add(
          'subscription-userinfo',
          'upload=10; download=20; expire=999999999999999999999',
        );
        request.response.statusCode = statuses[name] ?? 200;
        request.response.write(responses[name] ?? yaml);
        await request.response.close();
      } catch (_) {}
    });
    native = _Native();
    when(() => native.requestControl(any())).thenAnswer((call) async {
      final command = Map<String, Object?>.from(
        call.positionalArguments.first as Map,
      );
      controls.add(command);
      if (command['action'] == 'complete' && ackFault == 'before') {
        throw StateError('synthetic ack failure');
      }
      final result = await bridge.call('control', command);
      if (command['action'] == 'complete' && ackFault == 'after') {
        throw StateError('synthetic ack loss');
      }
      return result;
    });
    when(native.getRequestState).thenAnswer((_) async {
      final state = await bridge.call('nativeState');
      final observed = nextNativeRead;
      nextNativeRead = null;
      observed?.complete();
      return state;
    });
    when(native.getRunTime).thenAnswer((_) async => DateTime(2026));
    when(() => native.syncState(any())).thenAnswer((_) async => '');
    client = Request.scoped(native: native, isAndroid: true);
    container = ProviderContainer(
      overrides: [
        sourceConfirmationProvider.overrideWith(
          (ref) => (review) async {
            confirmations.add(review);
            if (reviewOverride != null) return reviewOverride!(review);
            if (interactiveReview) return confirmSourceReview(ref, review);
            return SourceReviewDecision(
              automatic: review.kind != 'script',
              routing: 'source',
            );
          },
        ),
        profilesActionProvider.overrideWith(() => _Profiles(client)),
        backupActionProvider.overrideWith(() => _Backup(client)),
        scriptsActionProvider.overrideWith(() => _Scripts(client)),
        policySelectionActionProvider.overrideWith(() => _Selection(client)),
        setupActionProvider.overrideWith(() => _RecoverySetup(native, client)),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesProvider.overrideWith(() => _StoredProfiles(client)),
        nativeRequestStateProvider.overrideWith(
          () => NativeRequestState.scoped(native),
        ),
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(testUrl: 'http://127.0.0.1/'),
        ),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => const PatchClashConfig(
            mixedPort: 0,
            tun: Tun(enable: false),
            dns: Dns(enable: false, nameserver: ['127.0.0.1:1']),
          ),
        ),
      ],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    client.attach(container);
    await client.ready();
    profiles = container.read(profilesActionProvider.notifier);
    setup = container.read(setupActionProvider.notifier);
  });
  tearDown(() async {
    for (final gate in holds.values) {
      if (!gate.isCompleted) gate.complete();
    }
    if (!containerDisposed) container.dispose();
    await client.detach();
    await server.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await bridge.close();
    await store.close();
    await for (final entry in root.list()) {
      await entry.delete(recursive: true);
    }
  });
  Profile profile(int id, {OverwriteType type = OverwriteType.standard}) =>
      Profile(
        id: id,
        label: 'P$id',
        url: 'http://127.0.0.1:${server.port}/$id',
        requestMode: RequestMode.direct,
        autoUpdate: false,
        autoUpdateDuration: const Duration(days: 1),
        overwriteType: type,
      );
  Future<void> put(List<Profile> entries, {bool files = true}) async {
    await store.profilesDao.putAll(entries.map((p) => p.toCompanion()));
    (container.read(profilesProvider.notifier) as TestProfiles).replace(
      entries,
    );
    if (files) {
      for (final entry in entries) {
        final file = File(await appPath.getProfilePath('${entry.id}'));
        await file.parent.create(recursive: true);
        await file.writeAsString(yaml);
      }
    }
  }

  Future<void> until(
    Future<bool> Function() condition, {
    Object Function()? evidence,
  }) async {
    final clock = Stopwatch()..start();
    while (!await condition()) {
      if (clock.elapsed > const Duration(seconds: 5)) {
        fail(
          'consumer did not finish${evidence == null ? '' : ': ${evidence()}'}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> existingService() async {
    await put([profile(1)]);
    expect(
      await setup.applyProfile(force: true, allowSourceReview: true),
      true,
    );
    await bridge.call('refreshRunning');
    expect(
      await setup.setRunning(true, initialize: true, preparedRequestId: 2),
      true,
    );
    when(
      () => native.initializeRequestState(any(), recovery: true),
    ).thenAnswer((_) async => false);
  }

  Future<void> enableAutomatic({
    Duration delay = Duration.zero,
    bool notify = true,
  }) async {
    final entry = profile(1).copyWith(
      autoUpdate: true,
      autoUpdateDuration: delay == Duration.zero
          ? const Duration(days: 1)
          : delay,
      // Match Drift's persisted second precision before scheduling the timer.
      lastUpdateDate: delay == Duration.zero
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
            ),
    );
    if (notify) {
      await put([entry]);
    } else {
      await store.profilesDao.putAll([entry.toCompanion()]);
    }
  }

  for (final newerCandidate in [false, true]) {
    testWidgets(
      'cancelled subscription inspection keeps status accurate: newer=$newerCandidate',
      (tester) async {
        final entry = profile(2);
        const original =
            '${yaml}proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n'
            'proxy-groups: [{name: Main, type: select, proxies: [a]}]\n';
        late ConfigFact before;
        late List<int> permissions;
        await tester.runAsync(() async {
          await put([entry]);
          await File(await appPath.getProfilePath('2')).writeAsString(original);
          container.read(currentProfileIdProvider.notifier).value = 2;
          expect(
            await setup.applyProfile(force: true, allowSourceReview: true),
            true,
          );
          expect(
            await profiles.sourceReviewStatus(entry),
            SourceReviewStatus.ready,
          );
          before = await core.getConfigState();
          permissions = await File(
            '${root.path}/source-acceptance/permissions.json',
          ).readAsBytes();
        });
        core.sourceActions.clear();
        container.read(appVisibleProvider.notifier).value = true;
        container.read(viewSizeProvider.notifier).value = const Size(1000, 900);
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(child: Scaffold()),
          ),
        );
        Object? failure;
        var finished = false;
        await tester.runAsync(() async {
          unawaited(
            profiles
                .manageSourcePermissions(entry, review: true)
                .then(
                  (_) => finished = true,
                  onError: (Object error) {
                    failure = error;
                    finished = true;
                  },
                ),
          );
        });
        for (
          var i = 0;
          i < 500 && find.byType(SourceReviewDialog).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.byType(SourceReviewDialog), findsOneWidget);
        bool ready() {
          final button = find.widgetWithText(
            TextButton,
            'Accept this revision',
          );
          return button.evaluate().isNotEmpty &&
              tester.widget<TextButton>(button).onPressed != null;
        }

        for (var i = 0; i < 500 && !ready(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(ready(), true);
        Map<String, Object?>? newerInput;
        String? newerId;
        if (newerCandidate) {
          await tester.runAsync(() async {
            newerInput = {
              ...core.pendingReviewInput!,
              'forceReview': false,
              'body': original.replaceFirst('MATCH,DIRECT', 'MATCH,REJECT'),
            };
            final result = await core.sourceAcceptance(newerInput!);
            expect(result['status'], 'reviewRequired');
            newerId = result['candidate'] as String;
          });
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 500 && !finished; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(finished, true, reason: '${core.sourceActions} / $failure');
        await tester.pumpAndSettle();
        expect(failure, isNull);
        expect(find.byType(SourceReviewDialog), findsNothing);
        expect(core.sourceActions, contains('discard'));
        expect(core.sourceActions, isNot(contains('accept')));
        await tester.runAsync(() async {
          expect(
            await profiles.sourceReviewStatus(entry),
            newerCandidate
                ? SourceReviewStatus.required
                : SourceReviewStatus.ready,
          );
          expect(
            await File(
              '${root.path}/source-acceptance/permissions.json',
            ).readAsBytes(),
            permissions,
          );
          expect((await core.getConfigState()).fence, before.fence);
          if (newerInput != null) {
            await core.sourceAcceptance({
              ...newerInput!,
              'action': 'discard',
              'candidate': newerId,
            });
          }
        });
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: executable == null,
    );
  }

  test(
    'URL import uses its own review surface once for all related sources',
    () async {
      container.read(appVisibleProvider.notifier).value = true;
      responses['/import'] =
          '${yaml}proxy-providers: {pool: {type: http, url: "http://127.0.0.1:${server.port}/import-pool", interval: 0}}\n'
          'proxy-groups: [{name: Main, type: select, use: [pool]}]\n';
      responses['/import-pool'] =
          'proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n';
      var presentations = 0;
      final phases = <ProfileImportPhase>[];
      final task = ProfileImportTask(onPhase: phases.add);
      final result = await profiles.addProfileFormURL(
        'http://127.0.0.1:${server.port}/import',
        label: 'Imported fixture',
        mode: RequestMode.direct,
        confirmed: true,
        importTask: task,
        reviewPresentation: (
          present: (child) async {
            presentations++;
            final dialog = child as SourceReviewDialog;
            expect(dialog.onDecision, isNotNull);
            final related = await dialog.loadRelated!('source');
            expect(
              related.where((entry) => entry.kind == 'provider-proxy'),
              hasLength(1),
            );
            expect(dialog.loading!.ready, true);
            return const SourceReviewDecision(
              automatic: false,
              routing: 'source',
            );
          },
          onDecision: (_) => fail('no widget was mounted by this fixture'),
        ),
      );
      expect(result!.materialSaved, true);
      expect(presentations, 1);
      expect(confirmations, isEmpty);
      expect(received.where((path) => path == '/import'), hasLength(1));
      expect(received.where((path) => path == '/import-pool'), hasLength(1));
      expect(phases, [
        ProfileImportPhase.downloading,
        ProfileImportPhase.saving,
      ]);
      expect(
        (await store.profilesDao.query().get()).single.label,
        'Imported fixture',
      );
      task.cancel();
    },
    skip: executable == null,
  );

  test(
    'reopening attaches to the valid running subscription without reapplying it',
    () async {
      await existingService();
      final previous = container.read(configStateProvider).fact;
      core.calls.clear();
      core.sourceActions.clear();
      received.clear();
      confirmations.clear();
      when(
        () => native.initializeRequestState(any()),
      ).thenAnswer((_) async => false);
      globalState.needInitStatus = true;
      await setup.initStatus();
      final current = container.read(configStateProvider).fact;
      expect(current.owner, previous.owner);
      expect(current.token, previous.token);
      expect(current.businessActive, true);
      expect(
        core.calls.where(
          (call) => const [
            CoreMethod.registerConfigInput,
            CoreMethod.prepareConfig,
            CoreMethod.installConfig,
            CoreMethod.activateConfig,
          ].contains(call),
        ),
        isEmpty,
      );
      expect(core.sourceActions, isNot(contains('adoptInline')));
      expect(received, isEmpty);
      expect(confirmations, isEmpty);
      expect(globalState.needInitStatus, false);
    },
    skip: executable == null,
  );

  for (final external in [false, true]) {
    for (final active in [false, true]) {
      test(
        'local group management applies ${external ? 'provider' : 'inline'} nodes while ${active ? 'active' : 'inactive'} without another source review or download',
        () async {
          final entry = profile(2);
          final definition = external
              ? 'proxy-providers:\n  pool: {type: http, url: "http://127.0.0.1:${server.port}/pool", interval: 0}\nproxy-groups:\n  - {name: Main, type: select, use: [pool]}\n'
              : 'proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\nproxy-groups:\n  - {name: Main, type: select, proxies: [a]}\n';
          responses['/2'] =
              '$yaml$definition  - {name: Media, type: select, proxies: [Main]}\n';
          responses['/pool'] =
              'proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}, {name: b, type: socks5, server: 127.0.0.1, port: 10}]\n';
          await put([entry]);
          await File(
            await appPath.getProfilePath('2'),
          ).writeAsString(responses['/2']!);
          if (await client.materialRecoveryRequired()) {
            final acceptance = SourceAcceptance(
              core: CoreController.scoped(core),
              requests: client,
            );
            final source = await client.captureSource('application-config');
            final snapshot = await acceptance.inspectMaterialRecovery(
              source: source,
              rows: [
                {
                  'key': 'profile:2',
                  'identity': SourceAcceptance.fingerprint({
                    'kind': 'profile',
                    'id': entry.id,
                    'url': entry.url,
                    'type': entry.type.name,
                  }),
                },
              ],
            );
            await acceptance.recoverMaterialCommit(
              source: source,
              snapshot: snapshot,
            );
          }
          container.read(currentProfileIdProvider.notifier).value = 2;
          expect(
            await setup.applyProfile(force: true, allowSourceReview: true),
            true,
          );
          if (active) {
            await bridge.call('refreshRunning');
            expect(
              await setup.setRunning(
                true,
                initialize: true,
                preparedRequestId: 2,
              ),
              true,
            );
          }
          confirmations.clear();
          received.clear();
          const group = LocalProxyGroup(
            id: 7,
            name: 'Mine',
            nodes: ['a'],
            parent: 'Main',
          );
          Profile current() => container.read(profileProvider(2))!;
          await profiles.saveLocalGroups(current(), [group]);
          final activeGroups = await bridge.call('refreshGroups');
          final groups = (activeGroups['value'] as Map)['proxies'] as Map;
          expect((groups['Mine'] as Map)['all'], ['a']);
          expect((groups['Main'] as Map)['all'], contains('Mine'));
          expect((groups['Main'] as Map)['now'], 'a');
          expect(confirmations, isEmpty);
          expect(received, isEmpty);
          expect(current().localGroups, [group]);
          final renamed = group.copyWith(name: 'My group');
          final stale = current();
          await profiles.saveLocalGroups(current(), [renamed]);
          await expectLater(
            profiles.saveLocalGroups(stale, [group.copyWith(name: 'Old edit')]),
            throwsA(
              isA<RequestUnavailable>().having(
                (error) => error.code,
                'code',
                'request_cancelled',
              ),
            ),
          );
          final selected = await bridge.call('refreshSelect', {
            'group-name': 'Main',
            'proxy-name': renamed.name,
          });
          expect((selected['value'] as Map)['changed'], true);
          await expectLater(
            profiles.saveLocalGroups(current(), [
              renamed.copyWith(enabled: false),
            ]),
            throwsA(
              isA<RequestUnavailable>().having(
                (error) => error.code,
                'code',
                'local_groups_in_use',
              ),
            ),
          );
          await bridge.call('refreshSelect', {
            'group-name': 'Main',
            'proxy-name': 'a',
          });
          await profiles.saveLocalGroups(current(), [
            renamed.copyWith(enabled: false),
          ]);
          expect(current().localGroups.single.enabled, isFalse);
          final disabled = await bridge.call('refreshGroups');
          expect(
            ((disabled['value'] as Map)['proxies'] as Map).containsKey(
              renamed.name,
            ),
            isFalse,
          );
          await profiles.saveLocalGroups(current(), []);
          expect(current().localGroups, isEmpty);
          expect(confirmations, isEmpty);
          expect(received, isEmpty);
          expect(
            (await store.profilesDao.query().get()).getProfile(2)!.localGroups,
            isEmpty,
          );
          final matched = await core.sourceAcceptance({
            'action': 'matchLocalNodes',
            'pattern': '^a',
            'names': ['a', 'b'],
          });
          expect(matched['matches'], ['a']);
          const automatic = LocalProxyGroup(
            id: 8,
            name: 'Automatic',
            type: GroupType.Fallback,
            nodes: ['a'],
            regex: '^a',
            matchedNodes: ['a'],
            testUrl: 'http://127.0.0.1:1/test',
          );
          await profiles.saveLocalGroups(current(), [automatic]);
          final independent =
              ((await bridge.call('refreshGroups'))['value'] as Map)['proxies']
                  as Map;
          expect(
            (independent['Main'] as Map)['all'],
            isNot(contains('Automatic')),
          );
          final sourceFile = File(await appPath.getProfilePath('2'));
          final reviewedBody = await sourceFile.readAsString();
          final pendingBody = reviewedBody.replaceFirst(
            'MATCH,DIRECT',
            'MATCH,REJECT',
          );
          await sourceFile.writeAsString(pendingBody);
          final pendingSource = await client.captureSource('profile:2');
          final pendingReview = await core.sourceAcceptance({
            'action': 'review',
            'key': 'profile:2',
            'kind': 'profile',
            'identity': SourceAcceptance.fingerprint({
              'kind': 'profile',
              'id': entry.id,
              'url': entry.url,
              'type': entry.type.name,
            }),
            'settings': SourceAcceptance.fingerprint({
              'fixture': 'pending update',
            }),
            'body': pendingBody,
            'source': {
              'client': pendingSource.client,
              'dataset': pendingSource.snapshot['dataset'],
              'sources': {
                pendingSource.key: pendingSource.snapshot['sourceRevision'],
              },
            },
          });
          expect(pendingReview['status'], 'reviewRequired');
          expect(
            await profiles.sourceReviewStatus(current()),
            SourceReviewStatus.required,
          );
          final beforeReference = await core.getConfigState();
          core.sourceActions.clear();
          final attached = automatic.copyWith(parents: ['Main', 'Media']);
          await profiles.saveLocalGroups(current(), [attached]);
          expect(current().localGroups.single, attached);
          final afterReference = await core.getConfigState();
          expect(afterReference.businessActive, active);
          if (active) {
            expect(afterReference.owner, beforeReference.owner);
            expect(afterReference.token, beforeReference.token);
          }
          expect(core.sourceActions, isNot(contains('review')));
          expect(core.sourceActions, isNot(contains('status')));
          expect(core.sourceActions, isNot(contains('fetchProvider')));
          final appliedBody = await File(
            '${root.path}/config-inputs/${afterReference.yamlSha256}.yaml',
          ).readAsString();
          expect(appliedBody, contains('MATCH,DIRECT'));
          expect(appliedBody, isNot(contains('MATCH,REJECT')));
          expect(await sourceFile.readAsString(), pendingBody);

          expect(core.sourceActions, isNot(contains('resolveLocalGroups')));
          final autoRuntime =
              ((await bridge.call('refreshGroups'))['value'] as Map)['proxies']
                  as Map;
          expect((autoRuntime['Automatic'] as Map)['all'], ['a']);
          expect((autoRuntime['Main'] as Map)['all'], contains('Automatic'));
          expect((autoRuntime['Main'] as Map)['now'], 'a');
          expect((autoRuntime['Media'] as Map)['all'], contains('Automatic'));
          expect((autoRuntime['Media'] as Map)['now'], 'Main');
          expect(
            await profiles.sourceReviewStatus(current()),
            SourceReviewStatus.required,
          );
          await bridge.call('refreshSelect', {
            'group-name': 'Main',
            'proxy-name': 'Automatic',
          });
          await expectLater(
            profiles.saveLocalGroups(current(), [
              attached.copyWith(parents: ['Media']),
            ]),
            throwsA(
              isA<RequestUnavailable>().having(
                (error) => error.code,
                'code',
                'local_groups_in_use',
              ),
            ),
          );
          await bridge.call('refreshSelect', {
            'group-name': 'Main',
            'proxy-name': 'a',
          });
          await profiles.saveLocalGroups(current(), [
            attached.copyWith(parents: ['Media']),
          ]);
          final detached =
              ((await bridge.call('refreshGroups'))['value'] as Map)['proxies']
                  as Map;
          expect(
            (detached['Main'] as Map)['all'],
            isNot(contains('Automatic')),
          );
          expect((detached['Media'] as Map)['all'], contains('Automatic'));
          expect((detached['Media'] as Map)['now'], 'Main');
          expect(
            await profiles.sourceReviewStatus(current()),
            SourceReviewStatus.required,
          );
          final discardSource = await client.captureSource('profile:2');
          await core.sourceAcceptance({
            'source': {
              'client': discardSource.client,
              'dataset': discardSource.snapshot['dataset'],
              'sources': {
                discardSource.key: discardSource.snapshot['sourceRevision'],
              },
            },
            'kind': 'profile',
            'action': 'discard',
            'key': 'profile:2',
            'candidate': pendingReview['candidate'],
          });
          await sourceFile.writeAsString(reviewedBody);
          expect(
            await profiles.sourceReviewStatus(current()),
            SourceReviewStatus.ready,
          );
          expect(confirmations, isEmpty);
          expect(received, isEmpty);
        },
        skip: executable == null,
      );
    }
  }

  for (final restriction in [
    'controller',
    'retired',
    'background',
    'unclassified',
  ]) {
    test(
      'local group Save handles $restriction inline rejection without reviewing new sources',
      () async {
        final entry = profile(2);
        await put([entry]);
        final file = File(await appPath.getProfilePath('2'));
        final original = restriction == 'controller'
            ? '${yaml}proxy-providers: {pool: {type: http, url: "http://127.0.0.1:${server.port}/pool", interval: 0}}\n'
                  'proxy-groups: [{name: Main, type: select, use: [pool]}]\n'
            : '${yaml}proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n'
                  'proxy-groups: [{name: Main, type: select, proxies: [a]}]\n';
        responses['/pool'] =
            'proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n';
        await file.writeAsString(original);
        container.read(currentProfileIdProvider.notifier).value = 2;
        expect(
          await setup.applyProfile(force: true, allowSourceReview: true),
          true,
        );
        const group = LocalProxyGroup(id: 7, name: 'Mine', nodes: ['a']);
        Profile current() => container.read(profileProvider(2))!;
        await profiles.saveLocalGroups(current(), [group]);
        await bridge.call('refreshRunning');
        expect(
          await setup.setRunning(true, initialize: true, preparedRequestId: 2),
          true,
        );
        final before = await core.getConfigState();
        final beforeNative = await bridge.call('nativeState');
        await file.writeAsString(
          original.replaceFirst('MATCH,DIRECT', 'MATCH,REJECT'),
        );
        await bridge.call(
          'inlineBlock',
          restriction == 'retired' ? 'retired' : 'controller',
        );
        if (restriction == 'background') {
          container.read(appVisibleProvider.notifier).value = false;
        }
        if (restriction == 'unclassified') {
          core.inlineRejection = 'synthetic unclassified apply rejection';
        }
        core.calls.clear();
        core.sourceActions.clear();
        confirmations.clear();
        received.clear();
        if (restriction == 'background' || restriction == 'unclassified') {
          await expectLater(
            profiles.saveLocalGroups(current(), [
              group.copyWith(parents: ['Main']),
            ]),
            restriction == 'background'
                ? throwsA(
                    isA<LocalProxyGroupProblem>().having(
                      (error) => error.code,
                      'code',
                      'foreground',
                    ),
                  )
                : throwsA(
                    isA<MessageException>().having(
                      (error) => error.message,
                      'message',
                      core.inlineRejection,
                    ),
                  ),
          );
          expect(core.calls, isNot(contains(CoreMethod.registerConfigInput)));
          expect(current().localGroups, [group]);
          expect((await core.getConfigState()).owner, before.owner);
        } else {
          await profiles.saveLocalGroups(current(), [
            group.copyWith(parents: ['Main']),
          ]);
          final after = await core.getConfigState();
          expect(core.calls, contains(CoreMethod.registerConfigInput));
          expect(after.businessActive, true);
          expect(after.owner, isNot(before.owner));
          expect(
            (await bridge.call('nativeState'))['intentRevision'],
            beforeNative['intentRevision'],
          );
          final runtime =
              ((await bridge.call('refreshGroups'))['value'] as Map)['proxies']
                  as Map;
          expect((runtime['Main'] as Map)['all'], contains('Mine'));
          expect((runtime['Main'] as Map)['now'], 'a');
          final body = await File(
            '${root.path}/config-inputs/${after.yamlSha256}.yaml',
          ).readAsString();
          expect(body, contains('MATCH,DIRECT'));
          expect(body, isNot(contains('MATCH,REJECT')));
        }
        expect(core.sourceActions, isNot(contains('review')));
        expect(confirmations, isEmpty);
        expect(received, isEmpty);
      },
      skip: executable == null,
    );
  }

  test(
    'local group references cannot restore withdrawn source permissions',
    () async {
      final entry = profile(2);
      await put([entry]);
      final sourceFile = File(await appPath.getProfilePath('2'));
      await sourceFile.writeAsString(
        '$yaml'
        'proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n'
        'proxy-groups: [{name: Main, type: select, proxies: [a]}]\n',
      );
      container.read(currentProfileIdProvider.notifier).value = 2;
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      const group = LocalProxyGroup(id: 7, name: 'Mine', nodes: ['a']);
      Profile current() => container.read(profileProvider(2))!;
      await profiles.saveLocalGroups(current(), [group]);
      final acceptance = SourceAcceptance(
        core: CoreController.scoped(core),
        requests: client,
      );
      final permissions = await acceptance.permissions(
        source: await client.captureSource('profile:2'),
        kind: 'profile',
      );
      await acceptance.withdraw(permissions.single, stopUse: true);
      confirmations.clear();
      received.clear();
      await expectLater(
        profiles.saveLocalGroups(current(), [
          group.copyWith(parents: ['Main']),
        ]),
        throwsA(
          anyOf(isA<RequestUnavailable>(), isA<LocalProxyGroupProblem>()),
        ),
      );
      expect(current().localGroups, [group]);
      expect(confirmations, isEmpty);
      expect(received, isEmpty);
      expect((await core.getConfigState()).businessActive, false);
    },
    skip: executable == null,
  );

  test(
    'local group management can remove saved definitions while source review is pending',
    () async {
      final entry = profile(2);
      await put([entry]);
      final path = File(await appPath.getProfilePath('2'));
      await path.writeAsString(
        '$yaml'
        'proxies: [{name: a, type: socks5, server: 127.0.0.1, port: 9}]\n'
        'proxy-groups: [{name: Main, type: select, proxies: [a]}]\n',
      );
      container.read(currentProfileIdProvider.notifier).value = 2;
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      const group = LocalProxyGroup(
        id: 7,
        name: 'Mine',
        nodes: ['a'],
        parent: 'Main',
      );
      Profile current() => container.read(profileProvider(2))!;
      await profiles.saveLocalGroups(current(), [group]);
      final before = await core.getConfigState();
      confirmations.clear();
      await path.writeAsString('rules: ["MATCH,REJECT"]\n');
      expect(
        await profiles.sourceReviewStatus(current()),
        SourceReviewStatus.required,
      );
      await profiles.saveLocalGroups(current(), [
        group.copyWith(enabled: false),
      ]);
      final actual = await ConfigInput.acceptedLocalGroups(
        home: root.path,
        accepted: await core.getConfigState(),
        readFact: core.getConfigState,
      );
      expect(actual!.single['enabled'], false);
      expect((await core.getConfigState()).inputId, isNot(before.inputId));
      expect(current().localGroups.single.enabled, false);
      await profiles.saveLocalGroups(current(), []);
      expect(current().localGroups, isEmpty);
      final removed = await core.getConfigState();
      expect(removed.yamlSha256, isNot(before.yamlSha256));
      final appliedBody = await File(
        '${root.path}/config-inputs/${removed.yamlSha256}.yaml',
      ).readAsString();
      expect(appliedBody, contains('MATCH,DIRECT'));
      expect(appliedBody, isNot(contains('MATCH,REJECT')));
      expect(
        await profiles.sourceReviewStatus(current()),
        SourceReviewStatus.required,
      );
      expect(confirmations, isEmpty);
    },
    skip: executable == null,
  );

  for (final wake in ['attach', 'visible', 'started', 'timer']) {
    test(
      'recovery with unavailable record preserves started service and automatic $wake maintenance',
      () async {
        await existingService();
        final guard = (BootFixture()..writeStatus = 'io').guard();
        await guard.evaluate(profileId: 1);
        final before = await core.getConfigState();
        await setup.initStatus(recovery: guard.decision.isDegraded);
        expect((await core.getConfigState()).owner, before.owner);
        final observed = setup as _RecoverySetup;
        core.nativeAfterActivation = 'phase';
        if (wake == 'visible') {
          container.read(appVisibleProvider.notifier).value = false;
        }
        await enableAutomatic(
          delay: wake == 'timer' ? const Duration(seconds: 2) : Duration.zero,
          notify: wake == 'timer',
        );
        final acceptedScopes = confirmations.length;
        switch (wake) {
          case 'attach':
            await profiles.autoUpdateProfiles();
          case 'visible':
            container.read(appVisibleProvider.notifier).value = true;
          case 'started':
            final state = await bridge.call('nativeState');
            final next = {...state, 'revision': (state['revision'] as int) + 1};
            await bridge.call('control', {'action': 'publish', 'state': next});
            container
                .read(nativeRequestStateProvider.notifier)
                .onRequestState(next);
          case 'timer':
            await profiles.autoUpdateProfiles();
        }
        await until(() async => observed.outcomes.isNotEmpty);
        expect(received, ['/1']);
        expect(observed.outcomes.single, ProfileApplicationOutcome.activated);
        expect(confirmations, hasLength(acceptedScopes));
        expect((await core.getConfigState()).businessActive, true);
        expect((await bridge.call('nativeState'))['intentRevision'], 2);
        expect(container.read(currentProfileIdProvider), 1);
        expect(
          controls.where((c) => c['action'] == 'begin').last['mode'],
          'direct',
        );
      },
      skip: executable == null,
    );
  }

  for (final phase in ['stopped', 'failed']) {
    test(
      'recovery $phase blocks a previously scheduled automatic timer',
      () async {
        await existingService();
        await enableAutomatic(delay: const Duration(seconds: 2));
        await profiles.autoUpdateProfiles();
        final state = await bridge.call('nativeState');
        await bridge.call('control', {
          'action': 'publish',
          'state': {
            ...state,
            'revision': (state['revision'] as int) + 1,
            'phase': phase,
            'reason': 'recovery',
          },
        });
        final timerRead = nextNativeRead = Completer<void>();
        await timerRead.future.timeout(const Duration(seconds: 3));
        await profiles.autoUpdateProfiles();
        container.read(appVisibleProvider.notifier).value = true;
        expect(received, isEmpty);
        expect((setup as _RecoverySetup).outcomes, isEmpty);
      },
      skip: executable == null,
    );

    test(
      'automatic material saved before external $phase cannot reapply the profile',
      () async {
        await existingService();
        final observed = setup as _RecoverySetup;
        observed.postEntered = Completer<void>();
        observed.postGate = Completer<void>();
        addTearDown(() {
          if (!observed.postGate!.isCompleted) observed.postGate!.complete();
        });
        await enableAutomatic();
        await profiles.autoUpdateProfiles();
        await observed.postEntered!.future.timeout(const Duration(seconds: 5));
        final registrations = core.calls
            .where((m) => m == CoreMethod.registerConfigInput)
            .length;
        final state = await bridge.call('nativeState');
        await bridge.call('control', {
          'action': 'publish',
          'state': {
            ...state,
            'revision': (state['revision'] as int) + 1,
            'phase': phase,
            'reason': 'externalFailure',
          },
        });
        observed.postGate!.complete();
        await until(() async => observed.outcomes.isNotEmpty);
        expect(received, ['/1']);
        expect(
          observed.outcomes.single,
          isNot(ProfileApplicationOutcome.activated),
        );
        expect(
          core.calls.where((m) => m == CoreMethod.registerConfigInput).length,
          registrations,
        );
        expect((await bridge.call('nativeState'))['phase'], phase);
      },
      skip: executable == null,
    );
  }

  test(
    'real refresh changes its own Core Owner and completes MD5, groups and providers',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final before = await core.getConfigState();
      final groupCalls = core.calls
          .where((m) => m == CoreMethod.getProxies)
          .length;
      globalState.lastConfigMd5 = 'before-refresh';
      responses['/1'] = '$yaml# refreshed\n';
      final result = await profiles.updateProfile(a);
      final after = await core.getConfigState();
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.installedInactive);
      expect(after.owner, isNot(before.owner));
      expect(after.businessActive, false);
      expect(globalState.lastConfigMd5, isNot('before-refresh'));
      expect(
        core.calls.where((m) => m == CoreMethod.getProxies).length,
        greaterThan(groupCalls),
      );
      expect(
        core.calls.where((m) => m == CoreMethod.getExternalProviders).length,
        greaterThanOrEqualTo(2),
      );
      expect(received, ['/1']);
      expect(
        (await store.profilesDao.query().get()).single.subscriptionInfo,
        const SubscriptionInfo(upload: 10, download: 20),
      );
    },
    skip: executable == null,
  );

  test(
    'activated refresh retains its Owner and native token while preserving the run intent',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      final before = await core.getConfigState();
      expect(before.businessActive, true);
      globalState.lastConfigMd5 = 'before-active-refresh';
      core.nativeAfterActivation = 'phase';
      final result = await profiles.updateProfile(a);
      expect(result.application, ProfileApplicationOutcome.activated);
      final after = await core.getConfigState();
      expect(after.businessActive, true);
      expect(after.owner, before.owner);
      expect(after.token, before.token);
      expect(globalState.lastConfigMd5, isNot('before-active-refresh'));
      expect((await bridge.call('nativeState'))['intentRevision'], 2);
      expect((await bridge.call('nativeState'))['revision'], 3);
    },
    skip: executable == null,
  );

  test(
    'a stop after activation supersedes completion projections without restoring the run intent',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      final groups = core.calls.where((m) => m == CoreMethod.getProxies).length;
      core.nativeAfterActivation = 'stop';
      globalState.lastConfigMd5 = 'stop-owned-md5';
      final result = await profiles.updateProfile(a);
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.superseded);
      expect((await core.getConfigState()).businessActive, false);
      expect((await bridge.call('nativeState'))['intentRunning'], false);
      expect(globalState.lastConfigMd5, 'stop-owned-md5');
      expect(
        core.calls.where((m) => m == CoreMethod.getProxies).length,
        groups,
      );
    },
    skip: executable == null,
  );

  for (final type in [OverwriteType.standard, OverwriteType.script]) {
    test(
      'dormant $type provider reference causes no apply or Owner transition',
      () async {
        final a = profile(1, type: type), b = profile(2);
        await put([a, b]);
        await store.batch(
          (batch) => batch.insertAll(store.proxyGroups, [
            const ProxyGroup(
              profileId: 1,
              name: 'dormant',
              id: 1,
              type: GroupType.Selector,
              use: ['P2'],
            ).toCompanion(),
          ]),
        );
        expect(
          await setup.applyProfile(force: true, allowSourceReview: true),
          true,
        );
        final before = await core.getConfigState();
        final applies = core.calls
            .where((m) => m == CoreMethod.registerConfigInput)
            .length;
        final result = await profiles.updateProfile(b);
        expect(result.application, ProfileApplicationOutcome.notRequired);
        expect((await core.getConfigState()).owner, before.owner);
        expect(
          core.calls.where((m) => m == CoreMethod.registerConfigInput).length,
          applies,
        );
      },
      skip: executable == null,
    );
  }

  test('a real registered provider refresh reapplies the current input', () async {
    final a = profile(1, type: OverwriteType.custom), b = profile(2);
    await put([a, b]);
    await store.batch(
      (batch) => batch.insertAll(store.proxyGroups, [
        const ProxyGroup(
          profileId: 1,
          name: 'local',
          id: 1,
          type: GroupType.Selector,
          use: ['P2'],
        ).toCompanion(),
      ]),
    );
    final provider = File(await appPath.getProfilePath('2'));
    await provider.writeAsString(
      'proxies:\n  - {name: local-node, type: socks5, server: 127.0.0.1, port: 1}\n',
    );
    responses['/2'] =
        'proxies:\n  - {name: local-node, type: socks5, server: 127.0.0.1, port: 2}\n';
    expect(
      await setup.applyProfile(force: true, allowSourceReview: true),
      true,
    );
    final before = await core.getConfigState();
    expect(
      await ConfigInput.acceptedDependencies(
        home: root.path,
        accepted: before,
        readFact: core.getConfigState,
      ),
      contains('profile:2'),
    );
    final result = await profiles.updateProfile(b);
    expect(result.materialSaved, true);
    expect(result.application, ProfileApplicationOutcome.installedInactive);
    expect((await core.getConfigState()).owner, isNot(before.owner));
  }, skip: executable == null);

  for (final failure in [false, true]) {
    test(
      'cross-ID Setup material demand progresses after provider ${failure ? 'DB failure' : 'save'}',
      () async {
        final a = profile(1, type: OverwriteType.custom), b = profile(2);
        await put([a, b]);
        await store.batch(
          (batch) => batch.insertAll(store.proxyGroups, [
            const ProxyGroup(
              id: 1,
              profileId: 1,
              name: 'local',
              type: GroupType.Selector,
              use: ['P2'],
            ).toCompanion(),
          ]),
        );
        const providerBody =
            'proxies:\n  - {name: local-node, type: socks5, server: 127.0.0.1, port: 1}\n';
        final provider = File(await appPath.getProfilePath('2'));
        await provider.writeAsString(providerBody);
        responses['/2'] = providerBody;
        expect(
          await setup.applyProfile(force: true, allowSourceReview: true),
          true,
        );
        await bridge.call('refreshRunning');
        expect(
          await setup.setRunning(true, initialize: true, preparedRequestId: 2),
          true,
        );
        await File(await appPath.getProfilePath('1')).delete();
        final release = holds['/2'] = Completer<void>();
        if (failure) {
          (container.read(profilesProvider.notifier) as _StoredProfiles)
                  .failProfile =
              2;
        }
        final refresh = profiles.updateProfile(b);
        final checked = failure
            ? expectLater(refresh, throwsA(isA<RequestUnavailable>()))
            : refresh.then((result) => expect(result.materialSaved, true));
        for (var i = 0; !received.contains('/2') && i < 1000; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(received, ['/2']);
        final entered = (profiles as _Profiles).materialDemandEntered =
            Completer<void>();
        final oldSetup = setup.applyProfile(
          force: true,
          allowSourceReview: true,
        );
        await entered.future.timeout(const Duration(seconds: 3));
        expect(received, ['/2']);
        release.complete();
        await checked.timeout(const Duration(seconds: 10));
        await oldSetup.timeout(const Duration(seconds: 10));
        if (failure) {
          expect(await provider.readAsString(), providerBody);
          expect(received.where((name) => name == '/2').length, 1);
        } else {
          expect(
            await setup
                .applyProfile(force: true)
                .timeout(const Duration(seconds: 10)),
            true,
          );
          expect(received, contains('/1'));
        }
      },
      skip: executable == null,
    );
  }

  test(
    'missing current material resumes its original Setup and applies exactly once',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      await File(await appPath.getProfilePath('1')).delete();
      core.calls.clear();
      core.sourceActions.clear();
      final previous = container.read(configStateProvider).fact;
      globalState.lastConfigMd5 = 'before-material-repair';
      core.readEntered = Completer<void>();
      final release = core.readGate = Completer<void>();
      final original = setup.applyProfile(force: true, allowSourceReview: true);
      await core.readEntered!.future.timeout(const Duration(seconds: 3));
      await pumpEventQueue();
      release.complete();
      expect(await original.timeout(const Duration(seconds: 3)), true);
      expect(
        core.sourceActions.where((action) => action == 'adoptInline'),
        hasLength(1),
      );
      expect(
        core.calls.where(
          (call) =>
              call == CoreMethod.registerConfigInput ||
              call == CoreMethod.installConfig,
        ),
        isEmpty,
      );
      expect(container.read(configStateProvider).fact.owner, previous.owner);
      expect(container.read(configStateProvider).fact.token, previous.token);
      expect(received, ['/1']);
      expect(globalState.lastConfigMd5, isNot('before-material-repair'));
      expect(
        core.calls,
        containsAll([CoreMethod.getProxies, CoreMethod.getExternalProviders]),
      );
    },
    skip: executable == null,
  );

  test(
    'a newer Setup releases expired material demand before an unrelated download finishes',
    () async {
      final a = profile(1), b = profile(2);
      await put([a, b]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final file = File(await appPath.getProfilePath('1'));
      await file.delete();
      final release = holds['/2'] = Completer<void>();
      final refresh = profiles
          .updateProfile(b)
          .then<Object>((value) => value, onError: (Object error) => error);
      for (var i = 0; !received.contains('/2') && i < 1000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(received, ['/2']);
      final inspected = controls
          .where(
            (call) => call['action'] == 'inspect' && call['key'] == 'profile:1',
          )
          .length;
      final entered = (profiles as _Profiles).materialDemandEntered =
          Completer<void>();
      final oldSetup = setup.applyProfile(force: true, allowSourceReview: true);
      await entered.future.timeout(const Duration(seconds: 3));
      for (
        var i = 0;
        controls
                    .where(
                      (call) =>
                          call['action'] == 'inspect' &&
                          call['key'] == 'profile:1',
                    )
                    .length ==
                inspected &&
            i < 1000;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await file.writeAsString(yaml);
      final newerSetup = setup.applyProfile(
        force: true,
        allowSourceReview: true,
      );
      await Future.wait([
        oldSetup,
        newerSetup,
      ]).timeout(const Duration(seconds: 3));
      expect(release.isCompleted, false);
      expect(received, ['/2']);
      release.complete();
      await refresh.timeout(const Duration(seconds: 10));
    },
    skip: executable == null,
  );

  test(
    'disposal during a finite save reports durable material and superseded application',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final storeProfiles =
          container.read(profilesProvider.notifier) as _StoredProfiles;
      final release = storeProfiles.commitGate = Completer<void>();
      storeProfiles.commitEntered = Completer<void>();
      responses['/1'] = '$yaml# refreshed\n';
      final refresh = profiles.updateProfile(a);
      await storeProfiles.commitEntered!.future.timeout(
        const Duration(seconds: 3),
      );
      container.dispose();
      containerDisposed = true;
      release.complete();
      final result = await refresh.timeout(const Duration(seconds: 3));
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.superseded);
      expect(
        (await store.profilesDao.query().get()).single.lastUpdateDate,
        isNotNull,
      );
      expect(
        await File(await appPath.getProfilePath('1')).readAsString(),
        responses['/1'],
      );
    },
    skip: executable == null,
  );

  test(
    'auto=false manual successor survives while the previous saved result is applying',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final gate = core.registerGate = Completer<void>();
      core.registerEntered = Completer<void>();
      final first = profiles.updateProfile(a);
      await core.registerEntered!.future;
      final next = a.copyWith(url: 'http://127.0.0.1:${server.port}/new');
      late RequestSource expected;
      await profiles.putProfile(
        next,
        onSourceSaved: (source) => expected = source,
      );
      final second = profiles.updateProfile(
        next,
        sourceMustMatch: true,
        expectedSource: expected,
      );
      gate.complete();
      expect((await first).materialSaved, true);
      final result = await second;
      expect(
        result.materialSaved,
        true,
        reason: '${result.failure} / ${core.sourceReviews}',
      );
      expect(received, ['/1', '/new']);
      expect((await store.profilesDao.query().get()).single.url, next.url);
    },
    skip: executable == null,
  );

  test(
    'a manual request during a finite automatic commit captures the committed source and runs independently',
    () async {
      final a = profile(1).copyWith(autoUpdate: true);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final storeProfiles =
          container.read(profilesProvider.notifier) as _StoredProfiles;
      final release = storeProfiles.commitGate = Completer<void>();
      storeProfiles.commitEntered = Completer<void>();
      await bridge.call('refreshRunning');
      expect(
        await setup.setRunning(true, initialize: true, preparedRequestId: 2),
        true,
      );
      unawaited(profiles.autoUpdateProfiles());
      await storeProfiles.commitEntered!.future.timeout(
        const Duration(seconds: 3),
      );
      expect(received, ['/1']);
      final manual = profiles.updateProfile(a);
      release.complete();
      final result = await manual.timeout(const Duration(seconds: 10));
      expect(result.materialSaved, true);
      expect(received, ['/1', '/1']);
      expect(result.application, ProfileApplicationOutcome.activated);
    },
    skip: executable == null,
  );

  test(
    'the latest manual successor supersedes the earlier waiter while a saved result is applying',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final gate = core.registerGate = Completer<void>();
      core.registerEntered = Completer<void>();
      final first = profiles.updateProfile(a);
      await core.registerEntered!.future;
      final next = a.copyWith(url: 'http://127.0.0.1:${server.port}/new');
      late RequestSource expected;
      await profiles.putProfile(
        next,
        onSourceSaved: (source) => expected = source,
      );
      final second = profiles.updateProfile(
        next,
        sourceMustMatch: true,
        expectedSource: expected,
      );
      final newest = next.copyWith(
        url: 'http://127.0.0.1:${server.port}/newest',
      );
      late RequestSource latestSource;
      await profiles.putProfile(
        newest,
        onSourceSaved: (source) => latestSource = source,
      );
      final third = profiles.updateProfile(
        newest,
        sourceMustMatch: true,
        expectedSource: latestSource,
      );
      gate.complete();
      expect((await first).materialSaved, true);
      final stale = await second;
      expect(stale.materialSaved, false);
      expect(stale.application, ProfileApplicationOutcome.superseded);
      final latest = await third;
      expect(
        latest.materialSaved,
        true,
        reason: '${latest.failure} / ${core.sourceReviews}',
      );
      expect(received, ['/1', '/newest']);
      expect((await store.profilesDao.query().get()).single.url, newest.url);
    },
    skip: executable == null,
  );

  test(
    'a newer inactive Owner survives delayed failure cleanup from an unsaved refresh',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final previous = await core.getConfigState();
      (container.read(profilesProvider.notifier) as _StoredProfiles)
              .failProfile =
          1;
      final gate = core.failureGate = Completer<void>();
      core.failureEntered = Completer<void>();
      final failed = profiles.updateProfile(a);
      final checked = expectLater(failed, throwsA(isA<RequestUnavailable>()));
      await core.failureEntered!.future.timeout(const Duration(seconds: 3));
      final fresh = await client.mutate(
        () async => ConfigInput.write(
          home: root.path,
          yaml: yaml,
          runtimeEpoch: previous.runtimeEpoch,
          profileId: 1,
          profileName: 'newer',
          selectedMap: {},
          testUrl: 'http://127.0.0.1/',
          sources: [await client.captureSource('profile:1')],
        ),
      );
      final newer = await core.applyConfigInput(fresh.toRequest());
      expect(newer.succeeded, true);
      expect(newer.fact.owner, isNot(previous.owner));
      gate.complete();
      await checked;
      final after = await core.getConfigState();
      expect(after.owner, newer.fact.owner);
      expect(after.inputId, fresh.id);
      expect(after.phase, 'ready');
      await core.releaseConfigInput(fresh.markerName);
      await fresh.releaseMarker();
    },
    skip: executable == null,
  );

  test(
    'late groups and providers do not publish over a newer accepted input',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final gate = core.projectionGate = Completer<void>();
      core.projectionEntered = Completer<void>();
      final refresh = profiles.updateProfile(a);
      await core.projectionEntered!.future.timeout(const Duration(seconds: 3));
      final observed = await core.getConfigState();
      final fresh = await client.mutate(
        () async => ConfigInput.write(
          home: root.path,
          yaml: yaml,
          runtimeEpoch: observed.runtimeEpoch,
          profileId: 1,
          profileName: 'newer projection',
          selectedMap: {},
          testUrl: 'http://127.0.0.1/',
          sources: [await client.captureSource('profile:1')],
        ),
      );
      final newer = await core.applyConfigInput(fresh.toRequest());
      expect(newer.succeeded, true);
      container.read(groupsProvider.notifier).value = [];
      var providerWrites = 0;
      final subscription = container.listen(
        providersProvider,
        (_, _) => providerWrites++,
      );
      globalState.lastConfigMd5 = 'newer-md5';
      gate.complete();
      final result = await refresh;
      expect(result.materialSaved, true);
      expect(result.application, ProfileApplicationOutcome.superseded);
      expect(container.read(groupsProvider), isEmpty);
      expect(providerWrites, 0);
      expect(globalState.lastConfigMd5, 'newer-md5');
      expect((await core.getConfigState()).owner, newer.fact.owner);
      subscription.close();
      await core.releaseConfigInput(fresh.markerName);
      await fresh.releaseMarker();
    },
    skip: executable == null,
  );

  test(
    'publication failure after durable save does not roll back only the file',
    () async {
      final a = profile(1);
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      (container.read(profilesProvider.notifier) as _StoredProfiles)
              .failPublication =
          true;
      responses['/1'] = '$yaml# durable material\n';
      final result = await profiles.updateProfile(a);
      expect(result.materialSaved, true);
      expect(result.failure, 'profile_publish_failed');
      expect(
        (await store.profilesDao.query().get()).single.lastUpdateDate,
        isNotNull,
      );
      expect(
        await File(await appPath.getProfilePath('1')).readAsString(),
        responses['/1'],
      );
    },
    skip: executable == null,
  );

  test(
    'R3 invalid local import preserves the old file and formal permission',
    () async {
      final a = profile(1).copyWith(url: '');
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final before = await core.getConfigState();
      final path = File(await appPath.getProfilePath('1'));
      final old = await path.readAsBytes();
      await expectLater(
        profiles.importFile(a, utf8.encode('mixed-port: invalid-local-port\n')),
        throwsA(isA<Exception>()),
      );
      expect(await path.readAsBytes(), old);
      final after = await core.getConfigState();
      expect(after.owner, before.owner);
      expect(after.replayEligible, before.replayEligible);
      expect(
        await File('${root.path}/request-recovery-required').exists(),
        false,
      );
      expect(received, isEmpty);
    },
    skip: executable == null,
  );

  test(
    'R3 local fresh import publishes only after the actual file and DB save',
    () async {
      final a = profile(1).copyWith(url: '');
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final source = await client.captureSource('profile:1');
      final acceptance = SourceAcceptance(
        core: CoreController.scoped(core),
        requests: client,
      );
      final before = (await acceptance.permissions(
        source: source,
        kind: 'profile',
      )).single;
      final body = [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('$yaml# explicit local fresh import\n'),
      ];
      await profiles.importFile(a, body);
      expect(await File(await appPath.getProfilePath('1')).readAsBytes(), body);
      final current = await client.captureSource('profile:1');
      final after = (await acceptance.permissions(
        source: current,
        kind: 'profile',
      )).single;
      expect(after.incarnation, isNot(before.incarnation));
      expect(
        await File('${root.path}/request-recovery-required').exists(),
        false,
      );
      expect(received, isEmpty);
    },
    skip: executable == null,
  );

  test(
    'R3 local import DB failure restores bytes and frontend recovery rebuilds the actual old source',
    () async {
      final a = profile(1).copyWith(url: '');
      await put([a]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final path = File(await appPath.getProfilePath('1'));
      final old = await path.readAsBytes();
      await store.customStatement(
        "CREATE TRIGGER fail_material_profile BEFORE UPDATE ON profiles BEGIN SELECT RAISE(ABORT, 'controlled local DB failure'); END",
      );
      await expectLater(
        profiles.importFile(
          a,
          utf8.encode('$yaml# uncommitted local material\n'),
        ),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(await path.readAsBytes(), old);
      expect(client.partialCommit, true);
      expect(
        await File('${root.path}/request-recovery-required').exists(),
        true,
      );
      await store.customStatement('DROP TRIGGER fail_material_profile');
      final acceptance = SourceAcceptance(
        core: CoreController.scoped(core),
        requests: client,
      );
      final source = await client.captureSource('application-config');
      final actual = (await store.profilesDao.query().get()).single;
      final snapshot = await acceptance.inspectMaterialRecovery(
        source: source,
        rows: [
          {
            'key': 'profile:${actual.id}',
            'identity': SourceAcceptance.fingerprint({
              'kind': 'profile',
              'id': actual.id,
              'url': actual.url,
              'type': actual.type.name,
            }),
          },
        ],
      );
      await acceptance.recoverMaterialCommit(
        source: source,
        snapshot: snapshot,
      );
      expect(client.partialCommit, false);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      expect(await path.readAsBytes(), old);
      expect(
        await File('${root.path}/request-recovery-required').exists(),
        false,
      );
      expect(received, isEmpty);
    },
    skip: executable == null,
  );

  test(
    'R3 local Script save publishes exact code and DB failure keeps the old code',
    () async {
      final scripts = container.read(scriptsActionProvider.notifier);
      final script = Script(
        id: 91,
        label: 'local synthetic',
        lastUpdateTime: DateTime(2026),
      );
      await store.scriptsDao.setAll([script]);
      await scripts.saveScript(
        script,
        'function main(config) { return config; }',
      );
      final path = File(await script.path);
      final old = await path.readAsBytes();
      await store.customStatement(
        "CREATE TRIGGER fail_material_script BEFORE UPDATE ON scripts BEGIN SELECT RAISE(ABORT, 'controlled script DB failure'); END",
      );
      await expectLater(
        scripts.saveScript(script, 'function main(config) { return {}; }'),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(await path.readAsBytes(), old);
      expect(client.partialCommit, true);
      expect(
        await File('${root.path}/request-recovery-required').exists(),
        true,
      );
      expect(received, isEmpty);
    },
    skip: executable == null,
  );

  test(
    'a missing accepted manifest blocks new source acceptance and preserves uncommitted material',
    () async {
      final a = profile(1), b = profile(2);
      await put([a, b]);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final before = await core.getConfigState();
      final count = core.calls
          .where((m) => m == CoreMethod.registerConfigInput)
          .length;
      await File('${root.path}/config-inputs/${before.inputId}.json').delete();
      final path = File(await appPath.getProfilePath('2'));
      final previous = await path.readAsBytes();
      await expectLater(
        profiles.updateProfile(b),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(await path.readAsBytes(), previous);
      expect(
        core.calls.where((m) => m == CoreMethod.registerConfigInput).length,
        count,
      );
    },
    skip: executable == null,
  );

  Future<
    ({
      Profile profile,
      PolicyDraftDocument draft,
      Map<String, dynamic> a,
      Map<String, dynamic> b,
    })
  >
  materialService() async {
    final policy = Map<String, dynamic>.from(
      await bridge.call('refreshFixture'),
    );
    await bridge.call('materialAuth', [
      {'User': 'a', 'Pass': 'pass-a'},
      {'User': 'b', 'Pass': 'pass-b'},
    ]);
    await existingService();
    final row = profile(1);
    final draft = PolicyDraftDocument.decode(
      jsonEncode({'draftVersion': 1, 'policy': policy}),
    );
    final nodes = draft.resources('proxies');
    Map<String, dynamic> source(String name, String id, String user) => {
      'name': name,
      'type': 'socks5',
      'server': nodes[id]['address'],
      'port': nodes[id]['port'],
      'udp': false,
      'username': user,
      'password': 'pass-$user',
    };
    final a = <String, dynamic>{
      'proxies': [source('hop', 'nodeA', 'a')],
      'proxy-groups': [
        {
          'name': 'pool',
          'type': 'select',
          'proxies': ['hop'],
        },
      ],
      'rule-providers': {
        'domains': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': ['DOMAIN-SUFFIX,example.test'],
        },
      },
    };
    final b = <String, dynamic>{
      'proxies': [source('hop', 'nodeB', 'b'), source('next', 'nodeB', 'b')],
      'proxy-groups': [
        {
          'name': 'pool',
          'type': 'select',
          'proxies': ['next'],
        },
      ],
      'rule-providers': {
        'domains': {
          'type': 'inline',
          'behavior': 'classical',
          'payload': ['DOMAIN-SUFFIX,example.test'],
        },
      },
    };
    nodes['nodeB']['username'] = 'b';
    nodes['nodeB']['password'] = 'pass-b';
    draft.useMaterialSource(
      1,
      profileMaterialIdentity(
        profileId: 1,
        type: row.type.name,
        url: row.url,
        overwrite: row.overwriteType.name,
        scriptId: row.scriptId,
      ),
    );
    draft.policy['proxies']['nodeA'] = {'source': 'hop'};
    draft.policy['groups']['a'] = {'source': 'pool'};
    draft.policy['collections'] = {
      'domains': {'source': 'domains', 'kind': 'domain'},
    };
    draft.policy['domainRules'][0] = {
      'id': 'wide',
      'collection': 'domains',
      'target': {'kind': 'proxy', 'group': 'a'},
      'dnsService': 'dnsA',
    };
    await File(
      await appPath.getProfilePath('1'),
    ).writeAsString(YamlWriter().write(a));
    await store.profilePolicyDraftsDao.compareAndWrite(
      1,
      expectedRaw: null,
      rawContent: draft.encode(),
    );
    await store.profilePolicySelectionsDao.compareAndWrite(
      1,
      expected: null,
      selection: ProfilePolicySelection(
        profileId: 1,
        rawContent: selectPolicyDraft(
          draft,
          maintenanceProxyTarget: {'kind': 'proxy', 'id': 'nodeA'},
        ),
      ),
    );
    expect(
      await setup.applyProfile(force: true, allowSourceReview: true),
      true,
    );
    expect((await bridge.call('probe', 'before.example.test'))['body'], 'A');
    return (profile: row, draft: draft, a: a, b: b);
  }

  final materialSkip =
      executable == null ||
      Platform.environment['FLCLASH_MANAGED_PROFILE_COMPILER'] == null;
  test(
    'v2 actual refresh A to B preserves template and changes authenticated business and DNS receivers',
    () async {
      final f = await materialService();
      final before = await core.getConfigState();
      final aProbe = await bridge.call('probe', 'a.example.test');
      responses['/1'] = YamlWriter().write(f.b);
      final result = await profiles.updateProfile(f.profile);
      expect(result.materialSaved, true);
      final after = await core.getConfigState();
      expect(after.policySha256, before.policySha256);
      expect(after.inputId, isNot(before.inputId));
      final bProbe = await bridge.call('probe', 'b.example.test');
      expect(bProbe['body'], 'B');
      expect(bProbe['dnsFailed'], false);
      expect(
        (bProbe['proxyCounts'] as List)[0],
        (aProbe['proxyCounts'] as List)[0],
      );
      expect(
        (bProbe['proxyCounts'] as List)[1],
        greaterThan((aProbe['proxyCounts'] as List)[1] as num),
      );
      expect(
        (bProbe['dnsCounts'] as List)[0],
        greaterThan((aProbe['dnsCounts'] as List)[0] as num),
      );
      final receipt = await ConfigInput.acceptedMaterials(
        home: root.path,
        accepted: after,
        readFact: core.getConfigState,
      );
      expect(receipt, isNotNull);
      expect(
        receipt!['rawSha256'],
        sha256
            .convert(
              await File(await appPath.getProfilePath('1')).readAsBytes(),
            )
            .toString(),
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 bad refresh preserves saved bytes date and eligible authenticated A',
    () async {
      final f = await materialService();
      final before = await core.getConfigState();
      final path = await appPath.getProfilePath('1');
      final bytes = await File(path).readAsBytes();
      f.b['proxy-groups'][0]['proxies'] = ['gone'];
      responses['/1'] = YamlWriter().write(f.b);
      await expectLater(
        profiles.updateProfile(f.profile),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(await File(path).readAsBytes(), bytes);
      expect(
        (await store.profilesDao.query().get()).first.lastUpdateDate,
        isNull,
      );
      expect((await core.getConfigState()).inputId, before.inputId);
      expect((await core.getConfigState()).replayEligible, true);
      expect(
        (await bridge.call('probe', 'retained.example.test'))['body'],
        'A',
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 latest preview Save and discard do not adopt B; explicit Apply adopts exact B',
    () async {
      final f = await materialService();
      responses['/1'] = YamlWriter().write(f.b);
      final path = await appPath.getProfilePath('1');
      final bytes = await File(path).readAsBytes();
      final before = await core.getConfigState();
      final candidate = await setup.capturePolicyMaterial(
        1,
        latest: true,
        client: client,
      );
      final preview = await candidate.preview(f.draft);
      expect(preview.maskedYaml, isNot(contains('pass-b')));
      expect(await File(path).readAsBytes(), bytes);
      expect((await core.getConfigState()).inputId, before.inputId);
      await candidate.close();
      expect(await File(path).readAsBytes(), bytes);
      final next = await setup.capturePolicyMaterial(
        1,
        latest: true,
        client: client,
      );
      await next.preview(f.draft);
      container.read(initProvider.notifier).value = true;
      final selection = await store.profilePolicySelectionsDao
          .query(1)
          .getSingle();
      expect(
        await container
            .read(policySelectionActionProvider.notifier)
            .selectConfirmed(
              1,
              expected: selection,
              draftRaw: f.draft.encode(),
              selectionRaw: selection.rawContent,
              material: next,
            ),
        PolicyDraftWriteResult.saved,
      );
      await next.close();
      expect(await File(path).readAsBytes(), isNot(bytes));
      expect(
        (await store.profilesDao.query().get()).first.lastUpdateDate,
        isNotNull,
      );
      expect((await bridge.call('probe', 'adopted.example.test'))['body'], 'B');
    },
    skip: materialSkip,
  );

  test(
    'v2 latest preview draft conflict compensates the exact old file without changing date',
    () async {
      final f = await materialService();
      responses['/1'] = YamlWriter().write(f.b);
      final path = await appPath.getProfilePath('1');
      final old = await File(path).readAsBytes();
      final candidate = await setup.capturePolicyMaterial(
        1,
        latest: true,
        client: client,
      );
      await candidate.preview(f.draft);
      final selected = await store.profilePolicySelectionsDao
          .query(1)
          .getSingle();
      await store.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: f.draft.encode(),
        rawContent: 'a newer draft',
      );
      expect(
        await container
            .read(policySelectionActionProvider.notifier)
            .selectConfirmed(
              1,
              expected: selected,
              draftRaw: f.draft.encode(),
              selectionRaw: selected.rawContent,
              material: candidate,
            ),
        PolicyDraftWriteResult.conflict,
      );
      await candidate.close();
      expect(await File(path).readAsBytes(), old);
      expect(
        (await store.profilesDao.query().get()).first.lastUpdateDate,
        isNull,
      );
      expect(
        (await bridge.call('probe', 'conflict.example.test'))['body'],
        'A',
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 preview cancellation and a newer preview cannot write source or selection',
    () async {
      await materialService();
      final path = await appPath.getProfilePath('1');
      final old = await File(path).readAsBytes();
      final hold = holds['/1'] = Completer<void>();
      PolicyMaterialCandidate? pending;
      final load = setup.capturePolicyMaterial(
        1,
        latest: true,
        client: client,
        onCreated: (candidate) => pending = candidate,
      );
      final failed = expectLater(load, throwsA(isA<RequestUnavailable>()));
      await until(() async => received.contains('/1'));
      await pending!.close();
      hold.complete();
      await failed;
      holds.remove('/1');
      final first = await setup.capturePolicyMaterial(
        1,
        latest: true,
        client: client,
      );
      final second = await setup.capturePolicyMaterial(
        1,
        latest: true,
        client: client,
      );
      expect(await first.current(), false);
      await first.close();
      await second.close();
      expect(await File(path).readAsBytes(), old);
      expect(
        (await store.profilesDao.query().get()).first.lastUpdateDate,
        isNull,
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 source and script identity changes stay repairable and never silently rebind',
    () async {
      final f = await materialService();
      for (final changed in [
        f.profile.copyWith(url: '${f.profile.url}?changed'),
        f.profile.copyWith(overwriteType: OverwriteType.custom),
        f.profile.copyWith(overwriteType: OverwriteType.script, scriptId: 777),
      ]) {
        await store.profilesDao.putAll([changed.toCompanion()]);
        PolicyMaterialCandidate? candidate;
        try {
          candidate = await setup.capturePolicyMaterial(1, client: client);
          await expectLater(
            candidate.preview(f.draft),
            throwsA(isA<PolicyDraftProblem>()),
          );
        } on PolicyDraftProblem catch (error) {
          expect(error.location, 'materialSource');
        } finally {
          await candidate?.close();
        }
      }
      expect(PolicyDraftDocument.decode(f.draft.encode()).isReadOnly, false);
      expect(
        (await store.profilePolicySelectionsDao.query(1).getSingle())
            .rawContent,
        selectPolicyDraft(
          f.draft,
          maintenanceProxyTarget: {'kind': 'proxy', 'id': 'nodeA'},
        ),
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 preflight parse releases mutation and a changed qualification prevents source commit',
    () async {
      final f = await materialService();
      responses['/1'] = YamlWriter().write(f.b);
      final path = await appPath.getProfilePath('1');
      final old = await File(path).readAsBytes();
      final entered = core.readEntered = Completer<void>();
      final gate = core.readGate = Completer<void>();
      final update = profiles.updateProfile(f.profile);
      final failed = expectLater(update, throwsA(isA<RequestUnavailable>()));
      await entered.future;
      await client.mutate(() => client.invalidate('application-config'));
      gate.complete();
      await failed;
      expect(await File(path).readAsBytes(), old);
      expect(
        (await store.profilesDao.query().get()).first.lastUpdateDate,
        isNull,
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 committed material is freshly parsed and rejected final closure never reactivates A',
    () async {
      final f = await materialService();
      responses['/1'] = YamlWriter().write(f.b);
      final before = await core.getConfigState();
      var reads = 0;
      core.materialReadOverride = (value) {
        if (++reads > 1) value['proxies'] = <dynamic>[];
        return value;
      };
      final result = await profiles.updateProfile(f.profile);
      expect(result.materialSaved, true);
      expect(reads, greaterThanOrEqualTo(2));
      expect(result.application, isNot(ProfileApplicationOutcome.activated));
      final after = await core.getConfigState();
      expect(after.replayEligible, false);
      expect(after.businessActive, false);
      expect(after.inputId, before.inputId);
    },
    skip: materialSkip,
  );

  for (final route in [RequestMode.auto, RequestMode.proxy]) {
    test(
      'v2 $route refresh uses the existing request route and adopts actual B',
      () async {
        final f = await materialService();
        await bridge.call('allowRefreshTarget', '127.0.0.1:${server.port}');
        final changed = f.profile.copyWith(
          requestMode: route,
          requestProxy: route == RequestMode.proxy
              ? 'fc-managed-proxy-nodeA'
              : null,
        );
        await put([changed], files: false);
        expect(
          await setup.applyProfile(force: true, allowSourceReview: true),
          true,
        );
        responses['/1'] = YamlWriter().write(f.b);
        final result = await profiles.updateProfile(changed);
        expect(result.materialSaved, true);
        expect((await bridge.call('probe', 'route.example.test'))['body'], 'B');
        expect(received.where((path) => path == '/1').length, 1);
      },
      skip: materialSkip,
    );
  }

  test(
    'v2 automatic refresh adopts B without a new selection confirmation',
    () async {
      final f = await materialService();
      responses['/1'] = YamlWriter().write(f.b);
      final before = await core.getConfigState();
      final automatic = f.profile.copyWith(autoUpdate: true);
      await put([automatic], files: false);
      final confirmed = confirmations.length;
      await profiles.autoUpdateProfiles();
      await until(
        () async =>
            (await store.profilesDao.query().get()).first.lastUpdateDate !=
            null,
        evidence: () => core.sourceReviews,
      );
      await until(() async {
        final fact = await core.getConfigState();
        return fact.businessActive && fact.inputId != before.inputId;
      }, evidence: () => core.sourceReviews);
      expect(
        (await bridge.call('probe', 'automatic.example.test'))['body'],
        'B',
      );
      expect(confirmations, hasLength(confirmed));
    },
    skip: materialSkip,
  );

  test(
    'v2 a blocked unknown selection can be repaired through a qualified new preview',
    () async {
      final f = await materialService();
      final selected = await store.profilePolicySelectionsDao
          .query(1)
          .getSingle();
      const unknown = ProfilePolicySelection(
        profileId: 1,
        rawContent: '{"selectionVersion":99}',
      );
      await store.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: selected,
        selection: unknown,
      );
      final candidate = await setup.capturePolicyMaterial(1, client: client);
      await candidate.preview(f.draft);
      expect(
        await container
            .read(policySelectionActionProvider.notifier)
            .selectConfirmed(
              1,
              expected: unknown,
              draftRaw: f.draft.encode(),
              selectionRaw: selected.rawContent,
              material: candidate,
            ),
        PolicyDraftWriteResult.saved,
      );
      await candidate.close();
    },
    skip: materialSkip,
  );

  test(
    'v2 script bytes are frozen, its material is consumed, and changed bytes invalidate preview',
    () async {
      final f = await materialService();
      final script = Script(
        id: 9,
        label: 'local synthetic',
        lastUpdateTime: DateTime(2026),
      );
      await store.scriptsDao.setAll([script]);
      await initEditorNative();
      final scriptBody = 'function main(config) { return ${jsonEncode(f.b)}; }';
      await script.save(scriptBody);
      final row = f.profile.copyWith(
        overwriteType: OverwriteType.script,
        scriptId: script.id,
      );
      await put([row], files: false);
      f.draft.useMaterialSource(
        1,
        profileMaterialIdentity(
          profileId: 1,
          type: row.type.name,
          url: row.url,
          overwrite: row.overwriteType.name,
          scriptId: row.scriptId,
        ),
      );
      final old = await store.profilePolicySelectionsDao.query(1).getSingle();
      await store.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: old,
        selection: ProfilePolicySelection(
          profileId: 1,
          rawContent: selectPolicyDraft(f.draft),
        ),
      );
      final evaluator = scriptEvaluator;
      addTearDown(() => scriptEvaluator = evaluator);
      final scripts = <String>[];
      scriptEvaluator =
          ({required String script, required String config}) async {
            scripts.add(script);
            return evaluator(script: script, config: config);
          };
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
        reason: '${core.sourceReviews} / evaluations:${scripts.length}',
      );
      expect((await bridge.call('probe', 'script.example.test'))['body'], 'B');
      expect(scripts, isNotEmpty);
      expect(scripts.toSet(), {scriptBody});
      final candidate = await setup.capturePolicyMaterial(1, client: client);
      await File(await script.path).writeAsString('new-synthetic-script');
      expect(await candidate.current(), false);
      await expectLater(
        candidate.preview(f.draft),
        throwsA(isA<PolicyDraftProblem>()),
      );
      await candidate.close();
    },
    skip: materialSkip,
  );

  test(
    'v2 custom select group overwrite is used by preflight and final material expansion',
    () async {
      final f = await materialService();
      final row = f.profile.copyWith(overwriteType: OverwriteType.custom);
      await put([row], files: false);
      await store.batch(
        (batch) => batch.insertAll(store.proxyGroups, [
          const ProxyGroup(
            id: 19,
            profileId: 1,
            name: 'pool',
            type: GroupType.Selector,
            proxies: ['hop'],
          ).toCompanion(),
        ]),
      );
      f.draft.useMaterialSource(
        1,
        profileMaterialIdentity(
          profileId: 1,
          type: row.type.name,
          url: row.url,
          overwrite: row.overwriteType.name,
          scriptId: row.scriptId,
        ),
      );
      final old = await store.profilePolicySelectionsDao.query(1).getSingle();
      await store.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: old,
        selection: ProfilePolicySelection(
          profileId: 1,
          rawContent: selectPolicyDraft(f.draft),
        ),
      );
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      responses['/1'] = YamlWriter().write(f.b);
      expect((await profiles.updateProfile(row)).materialSaved, true);
      expect(
        (await bridge.call('probe', 'overwrite.example.test'))['body'],
        'B',
      );
    },
    skip: materialSkip,
  );

  test(
    'v2 changed domain and address collections reach the actual ordered DNS and IP consumers',
    () async {
      final f = await materialService();
      f.a['rule-providers']['addresses'] = {
        'type': 'inline',
        'behavior': 'ipcidr',
        'payload': ['203.0.113.0/24'],
      };
      f.b['rule-providers']['addresses'] = {
        'type': 'inline',
        'behavior': 'ipcidr',
        'payload': ['192.0.2.0/24'],
      };
      f.b['rule-providers']['domains']['payload'] = [
        'DOMAIN-SUFFIX,example.test',
        'DOMAIN-SUFFIX,added.test',
      ];
      f.draft.policy['collections']['addresses'] = {
        'source': 'addresses',
        'kind': 'ip',
      };
      f.draft.policy['ipRules'][0] = {
        'id': 'collection-ip',
        'collection': 'addresses',
        'target': {'kind': 'proxy', 'group': 'a'},
      };
      await File(
        await appPath.getProfilePath('1'),
      ).writeAsString(YamlWriter().write(f.a));
      final old = await store.profilePolicySelectionsDao.query(1).getSingle();
      await store.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: old,
        selection: ProfilePolicySelection(
          profileId: 1,
          rawContent: selectPolicyDraft(f.draft),
        ),
      );
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      final domainA = await bridge.call('probe', 'before.added.test');
      expect(domainA['body'], 'B');
      expect(domainA['dnsFailed'], false);
      expect((domainA['dnsCounts'] as List)[1], greaterThan(0));
      expect(
        (await bridge.call('probe', '192.0.2.123'))['businessFailed'],
        true,
      );
      final before = await bridge.call('probe', 'final-before.added.test');
      responses['/1'] = YamlWriter().write(f.b);
      expect((await profiles.updateProfile(f.profile)).materialSaved, true);
      final domainB = await bridge.call('probe', 'after.added.test');
      expect(domainB['body'], 'B');
      expect(domainB['dnsFailed'], false);
      expect(
        (domainB['dnsCounts'] as List)[0],
        greaterThan((before['dnsCounts'] as List)[0] as num),
      );
      expect(
        (domainB['dnsCounts'] as List)[1],
        (before['dnsCounts'] as List)[1],
      );
      expect((await bridge.call('probe', '192.0.2.123'))['body'], 'B');
    },
    skip: materialSkip,
  );

  test(
    'I1 changed selection validates reset picks while unchanged refresh remains strict',
    () async {
      final f = await materialService();
      final initialRaw = f.draft.encode();
      f.draft.policy['groups']['b'] = ['nodeA'];
      await store.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: initialRaw,
        rawContent: f.draft.encode(),
      );
      final selected = await store.profilePolicySelectionsDao
          .query(1)
          .getSingle();
      final oldRaw = selectPolicyDraft(f.draft);
      await store.profilePolicySelectionsDao.compareAndWrite(
        1,
        expected: selected,
        selection: ProfilePolicySelection(profileId: 1, rawContent: oldRaw),
      );
      final row = f.profile.copyWith(
        selectedMap: {
          'fc-managed-group-b': 'fc-managed-proxy-nodeA',
          'legacy-group': 'legacy-node',
        },
      );
      await put([row], files: false);
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        true,
      );
      expect((await bridge.call('probe', 'manual.other.test'))['body'], 'A');
      final next = PolicyDraftDocument.decode(f.draft.encode());
      next.policy['groups']['b'] = ['nodeB'];
      await store.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: f.draft.encode(),
        rawContent: next.encode(),
      );
      final candidate = await setup.capturePolicyMaterial(1, client: client);
      await candidate.preview(next);
      container.read(initProvider.notifier).value = true;
      final oldSelection = await store.profilePolicySelectionsDao
          .query(1)
          .getSingle();
      final nextRaw = selectPolicyDraft(next);
      expect(
        await container
            .read(policySelectionActionProvider.notifier)
            .selectConfirmed(
              1,
              expected: oldSelection,
              draftRaw: next.encode(),
              selectionRaw: nextRaw,
              material: candidate,
            ),
        PolicyDraftWriteResult.saved,
      );
      await candidate.close();
      final saved = (await store.profilesDao.query().get()).first;
      expect(saved.selectedMap.containsKey('fc-managed-group-b'), false);
      expect(saved.selectedMap['legacy-group'], 'legacy-node');
      expect(
        (await bridge.call('probe', 'new-manual.other.test'))['body'],
        'B',
      );
      final path = await appPath.getProfilePath('1');
      final bytes = await File(path).readAsBytes();
      await put([
        saved.copyWith(
          selectedMap: {'fc-managed-group-b': 'fc-managed-proxy-nodeA'},
        ),
      ], files: false);
      responses['/1'] = YamlWriter().write(f.b);
      await expectLater(
        profiles.updateProfile(f.profile),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(await File(path).readAsBytes(), bytes);
      final resolved = SelectedPolicy.decode(nextRaw).resolve(
        material: f.a,
        identity: profileMaterialIdentity(
          profileId: 1,
          type: row.type.name,
          url: row.url,
          overwrite: row.overwriteType.name,
          scriptId: row.scriptId,
        ),
        profileId: 1,
        rawSha256: materialDigest(f.a),
      );
      await put([
        saved.copyWith(
          selectedMap: {
            'fc-managed-group-b': 'fc-managed-proxy-nodeB',
            'fc-managed-group-a':
                'fc-managed-proxy-${resolved.policy.groups['a']!.first}',
          },
        ),
      ], files: false);
      expect((await profiles.updateProfile(f.profile)).materialSaved, true);
      expect((await bridge.call('probe', 'dynamic.example.test'))['body'], 'B');
    },
    skip: materialSkip,
  );

  test(
    'I3 final qualification wait cannot attach an old preview to a mutated draft',
    () async {
      final f = await materialService();
      final candidate = await setup.capturePolicyMaterial(1, client: client);
      final original = PolicyDraftDocument.decode(f.draft.encode());
      final oldPreview = await candidate.preview(f.draft);
      expect(
        (loadYaml(oldPreview.maskedYaml)['dns']['nameserver'] as List).first,
        startsWith('tcp://'),
      );
      final entered = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var inspections = 0;
      when(() => native.requestControl(any())).thenAnswer((invocation) async {
        final command = Map<String, Object?>.from(
          invocation.positionalArguments.first as Map,
        );
        if (command['action'] == 'inspect' &&
            command['key'] == 'profile:1' &&
            ++inspections == 2) {
          entered.complete();
          await release.future;
        }
        return bridge.call('control', command);
      });
      final pending = candidate.preview(f.draft);
      final rejected = expectLater(pending, throwsA(isA<PolicyDraftProblem>()));
      await entered.future;
      f.draft.policy['domainDefault'] = {
        'target': {'kind': 'reject'},
      };
      release.complete();
      await rejected;
      expect(candidate.qualifies(f.draft), false);
      expect(candidate.qualifies(original), false);
      final fresh = await candidate.preview(f.draft);
      expect(
        (loadYaml(fresh.maskedYaml)['dns']['nameserver'] as List).first,
        'rcode://refused',
      );
      expect(candidate.qualifies(f.draft), true);
      expect(candidate.qualifies(original), false);
      await candidate.close();
    },
    skip: materialSkip,
  );

  for (final registered in [false, true]) {
    test(
      'managed policy remains selected when ${registered ? 'registered' : 'unregistered'} subscription material refreshes',
      () async {
        final fixture = await bridge.call('refreshFixture');
        final selected = selectPolicyDraft(
          PolicyDraftDocument.decode(
            jsonEncode({'draftVersion': 1, 'policy': fixture}),
          ),
        );
        final a = profile(
              1,
              type: registered ? OverwriteType.custom : OverwriteType.standard,
            ),
            b = profile(2);
        await put([a, b]);
        await store.profilePolicySelectionsDao.compareAndWrite(
          1,
          expected: null,
          selection: ProfilePolicySelection(profileId: 1, rawContent: selected),
        );
        if (registered) {
          await store.batch(
            (batch) => batch.insertAll(store.proxyGroups, [
              const ProxyGroup(
                id: 1,
                profileId: 1,
                name: 'dormant-material',
                type: GroupType.Selector,
                use: ['P2'],
              ).toCompanion(),
            ]),
          );
          await File(await appPath.getProfilePath('2')).writeAsString(
            'proxies:\n  - {name: ignored-node, type: socks5, server: 127.0.0.1, port: 1}\n',
          );
          responses['/2'] =
              'proxies:\n  - {name: ignored-node, type: socks5, server: 127.0.0.1, port: 2}\n';
        }
        expect(
          await setup.applyProfile(force: true, allowSourceReview: true),
          true,
        );
        final before = await core.getConfigState();
        expect(before.isManaged, true);
        final result = await profiles.updateProfile(b);
        final after = await core.getConfigState();
        expect(result.materialSaved, true);
        expect(after.policySha256, before.policySha256);
        expect(
          (await store.profilePolicySelectionsDao.query(1).getSingle())
              .rawContent,
          selected,
        );
        expect(after.owner, registered ? isNot(before.owner) : before.owner);
      },
      skip:
          executable == null ||
          Platform.environment['FLCLASH_MANAGED_PROFILE_COMPILER'] == null,
    );
  }

  for (final recovery in [false, true]) {
    test(
      'real Go backup restore clears only its ${recovery ? 'retained' : 'own'} durable barrier',
      () async {
        await put([profile(1)]);
        if (recovery) await client.markRecoveryRequired();
        final staging = Directory('${root.path}/owned-restore-staging');
        await Directory('${staging.path}/profiles').create(recursive: true);
        const restored = '$yaml# restored by actual backup actor\n';
        await File('${staging.path}/profiles/1.yaml').writeAsString(restored);
        await container
            .read(backupActionProvider.notifier)
            .applyRestore(
              MigrationData(
                profiles: [profile(1).copyWith(label: 'Restored fixture')],
              ),
              RestoreOption.onlyProfiles,
              stagingDirPath: staging.path,
            );
        expect(
          (await store.profilesDao.query().get()).single.label,
          'Restored fixture',
        );
        expect(
          await File(await appPath.getProfilePath('1')).readAsString(),
          restored,
        );
        expect(client.partialCommit, false);
        expect(
          await File('${root.path}/request-recovery-required').exists(),
          false,
        );
        final completed = controls.lastWhere((c) => c['action'] == 'complete');
        if (recovery) {
          final cleared = controls.lastWhere(
            (c) => c['action'] == 'clearRecovery',
          );
          expect(cleared['id'], completed['id']);
          expect(cleared['client'], completed['client']);
        }
      },
      skip: executable == null,
    );
  }

  test(
    'R3.4 actual Dart late finally cannot mutate the replacement client dataset',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final work = client.localCommit(() async {
        entered.complete();
        await release.future;
        await client.markPartialCommit();
      });
      await entered.future;
      await bridge.call('control', {'action': 'engineDetach'});
      final replacement = ProviderContainer();
      addTearDown(replacement.dispose);
      client.attach(replacement);
      await client.ready().timeout(const Duration(seconds: 2));
      final before = await client.captureSource('application-config');
      await expectLater(
        profiles.manageSourcePermissions(profile(1)),
        throwsA(
          isA<RequestUnavailable>().having(
            (e) => e.code,
            'code',
            'request_restart_required',
          ),
        ),
      );
      expect(
        const RequestUnavailable('request_restart_required').toString(),
        contains('Force stop'),
      );
      release.complete();
      await expectLater(
        work,
        throwsA(
          isA<RequestUnavailable>().having(
            (e) => e.code,
            'code',
            'request_partial_commit',
          ),
        ),
      );
      final after = await client.captureSource('application-config');
      expect(after.client, before.client);
      expect(after.snapshot['dataset'], before.snapshot['dataset']);
      expect(
        await File('${root.path}/request-recovery-required').exists(),
        true,
      );
      final completion = controls.lastWhere((c) => c['action'] == 'complete');
      expect(completion['client'], isNot(before.client));
    },
    skip: executable == null,
  );

  for (final local in [false, true]) {
    for (final failure in ['before', 'after']) {
      test(
        'real Go ${local ? 'localCommit' : 'session commit'} ack loss $failure release stays in its receipt',
        () async {
          ackFault = failure;
          final work = local
              ? client.localCommit(() async {})
              : () async {
                  final session = await client.begin(
                    key: 'profile:ack',
                    url: 'http://127.0.0.1/',
                    mode: RequestMode.direct,
                  );
                  try {
                    await session.commit(() async {});
                  } finally {
                    session.close();
                  }
                }();
          await expectLater(
            work.timeout(const Duration(seconds: 3)),
            throwsA(
              isA<RequestUnavailable>().having(
                (e) => e.code,
                'code',
                'request_partial_commit',
              ),
            ),
          );
          expect(client.partialCommit, true);
          expect(
            await File('${root.path}/request-recovery-required').exists(),
            true,
          );
          expect(
            controls.where((c) => c['action'] == 'inspect' && c['id'] != null),
            isNotEmpty,
          );
          final completed = controls.lastWhere(
            (c) => c['action'] == 'complete',
          );
          await bridge.call('control', completed);
        },
        skip: executable == null,
      );
    }
  }
  test(
    'passive setup does not enqueue an interactive download for a missing profile',
    () async {
      await put([profile(1)], files: false);
      final entered = (profiles as _Profiles).materialDemandEntered =
          Completer<void>();
      expect(await setup.applyProfile(force: true), isFalse);
      expect(entered.isCompleted, isFalse);
      expect(received, isEmpty);
      expect(confirmations, isEmpty);
    },
    skip: executable == null,
  );

  test(
    'passive startup reuses accepted materials without depending on the replay pointer',
    () async {
      final row = profile(1);
      await put([row]);
      final config =
          'mode: rule\n'
          'rule-providers:\n'
          '  legacy: {type: http, url: "http://127.0.0.1:${server.port}/legacy", format: text, behavior: domain}\n'
          'rules: ["RULE-SET,legacy,DIRECT", "MATCH,DIRECT"]\n';
      await File(await appPath.getProfilePath('1')).writeAsString(config);
      responses['/legacy'] = 'legacy.invalid\n';
      expect(
        await setup.applyProfile(force: true, allowSourceReview: true),
        isTrue,
      );
      expect(received, contains('/legacy'));
      SourceReviewBatchStore.forRequests(client).clear();
      received.clear();
      confirmations.clear();
      core.sourceActions.clear();
      expect(await setup.applyProfile(force: true), isTrue);
      expect(core.sourceActions, contains('reuseCachedProviders'));
      expect(core.sourceActions, isNot(contains('reuseReviewedProvider')));
      expect(core.sourceActions, isNot(contains('reuseCachedProvider')));
      expect(received, isEmpty);
      expect(confirmations, isEmpty);
      await File('${root.path}/config-inputs/checkpoint.json').delete();
      core.sourceActions.clear();
      final previous = container.read(configStateProvider).fact;
      expect(
        await setup.applyProfile(force: true, allowSourceReview: false),
        isTrue,
      );
      expect(core.sourceActions, contains('reuseCachedProviders'));
      expect(core.sourceActions, isNot(contains('reuseReviewedProvider')));
      expect(core.sourceActions, isNot(contains('reuseCachedProvider')));
      expect(core.sourceActions, isNot(contains('fetchProvider')));
      expect(
        container.read(configStateProvider).fact.token,
        greaterThan(previous.token),
      );
      expect(received, isEmpty);
      expect(confirmations, isEmpty);
    },
    skip: executable == null,
  );

  test(
    'existing pending source review retains available rules and saves once',
    () async {
      await existingService();
      final entry = profile(2);
      await put([profile(1), entry]);
      final original =
          'proxies: [{name: inline, type: socks5, server: 127.0.0.1, port: 9}]\n'
          'proxy-groups: [{name: Source, type: select, proxies: [inline]}]\n'
          'rule-providers:\n'
          '  missing: {type: http, url: "http://127.0.0.1:${server.port}/missing", proxy: DIRECT, format: text, behavior: domain}\n'
          '  loaded: {type: http, url: "http://127.0.0.1:${server.port}/loaded-rule", proxy: DIRECT, format: text, behavior: domain}\n'
          'rules: ["RULE-SET,missing,DIRECT", "RULE-SET,loaded,Source", "MATCH,Source"]\n';
      await File(await appPath.getProfilePath('2')).writeAsString(original);
      statuses['/missing'] = 503;
      responses['/loaded-rule'] = 'available.invalid\n';
      container.read(appVisibleProvider.notifier).value = true;
      var reviews = 0;
      reviewOverride = container.read(
        Provider<SourceConfirmation>(
          (ref) =>
              (review) => confirmSourceReview(
                ref,
                review,
                present: (child) async {
                  reviews++;
                  final dialog = child as SourceReviewDialog;
                  await dialog.loadRelated!(dialog.review.routing);
                  return SourceReviewDecision(
                    automatic: false,
                    routing: 'source',
                    importChoice: dialog.loading!.ready
                        ? SourceImportChoice.complete
                        : SourceImportChoice.availableConfiguration,
                  );
                },
              ),
        ),
      );
      (profiles as _Profiles).reviewConfirmation = reviewOverride;
      received.clear();
      await profiles.manageSourcePermissions(entry, review: true);
      expect(reviews, 2);
      final body =
          jsonDecode(
                await File(await appPath.getProfilePath('2')).readAsString(),
              )
              as Map;
      expect(body['rules'], ['RULE-SET,loaded,Source', 'MATCH,Source']);
      expect((body['rule-providers'] as Map).keys, ['loaded']);
      expect(received.where((x) => x == '/missing'), hasLength(1));
      expect(received.where((x) => x == '/loaded-rule'), hasLength(1));
      expect(
        await profiles.sourceReviewStatus(entry),
        SourceReviewStatus.ready,
      );
    },
    skip: executable == null,
  );

  test(
    '53 of 55 sources retain groups, independent logical rules and DNS policies',
    () async {
      container.read(currentProfileIdProvider.notifier).value = null;
      const groupNames = ['Entry', 'Streaming', 'Fallback'];
      final sourceRules = [
        for (var i = 0; i < 55; i++) 'RULE-SET,rule-$i,Entry',
        'AND,((RULE-SET,rule-0),(RULE-SET,rule-1)),Entry',
        'NOT,((RULE-SET,rule-7)),REJECT',
        'MATCH,Fallback',
      ];
      responses['/batch-55'] = jsonEncode({
        'proxies': [
          {
            'name': 'only-node',
            'type': 'socks5',
            'server': '127.0.0.1',
            'port': 9,
          },
        ],
        'proxy-groups': [
          for (final name in groupNames)
            {
              'name': name,
              'type': 'select',
              'proxies': ['only-node'],
            },
        ],
        'rule-providers': {
          for (var i = 0; i < 55; i++)
            'rule-$i': {
              'type': 'http',
              'url': 'http://127.0.0.1:${server.port}/rule/$i',
              'proxy': 'DIRECT',
              'format': 'text',
              'behavior': 'domain',
            },
        },
        'dns': {
          'enable': true,
          'listen': '127.0.0.1:0',
          'nameserver': ['127.0.0.1:9'],
          'nameserver-policy': {
            'rule-set:rule-7': '127.0.0.1:10',
            'rule-set:rule-13': '127.0.0.1:11',
            '*.example.invalid': '127.0.0.1:12',
          },
        },
        'rules': sourceRules,
      });
      for (var i = 0; i < 55; i++) {
        responses['/rule/$i'] = 'fixture-$i.invalid\n';
      }
      statuses['/rule/7'] = 503;
      statuses['/rule/11'] = 503;
      container.read(appVisibleProvider.notifier).value = true;
      var reviews = 0;
      final result = await profiles.addProfileFormURL(
        'http://127.0.0.1:${server.port}/batch-55',
        label: 'Batch fixture',
        mode: RequestMode.direct,
        confirmed: true,
        importTask: ProfileImportTask(onPhase: (_) {}),
        reviewPresentation: (
          present: (child) async {
            final dialog = child as SourceReviewDialog;
            reviews++;
            await dialog.loadRelated!(dialog.review.routing);
            if (reviews == 1) {
              final sources = dialog.loading!.items.where(
                (item) => item.kind == 'provider-rule',
              );
              expect(sources, hasLength(55));
              expect(
                sources.where(
                  (item) => item.phase == SourceReviewLoadPhase.ready,
                ),
                hasLength(53),
              );
              expect(dialog.canUseAvailableConfiguration!(), true);
              return const SourceReviewDecision(
                automatic: false,
                routing: 'source',
                importChoice: SourceImportChoice.availableConfiguration,
              );
            }
            expect(dialog.loading!.ready, true);
            expect(
              dialog.partialConfiguration!.changes['nodesOnly'],
              isNot(true),
            );
            expect(
              dialog.partialConfiguration!.changes['blocked'],
              anyOf(isNull, isEmpty),
            );
            expect(
              dialog.partialConfiguration!.changes['removedRules'],
              hasLength(3),
            );
            expect(
              dialog.partialConfiguration!.changes['removedSettings'],
              hasLength(1),
            );
            return const SourceReviewDecision(
              automatic: false,
              routing: 'source',
            );
          },
          onDecision: (_) {},
        ),
      );
      expect(result!.materialSaved, true);
      expect(reviews, 2);
      final row = (await store.profilesDao.query().get()).single;
      final body =
          jsonDecode(
                await File(
                  await appPath.getProfilePath('${row.id}'),
                ).readAsString(),
              )
              as Map;
      expect(
        (body['proxy-groups'] as List).map((group) => group['name']),
        groupNames,
      );
      expect((body['rule-providers'] as Map), hasLength(53));
      expect(
        body['rules'],
        sourceRules.where(
          (rule) =>
              !rule.contains('rule-7,') &&
              !rule.contains('rule-11,') &&
              !rule.startsWith('NOT,'),
        ),
      );
      expect((body['dns'] as Map)['nameserver-policy'], {
        'rule-set:rule-13': '127.0.0.1:11',
        '*.example.invalid': '127.0.0.1:12',
      });
      for (var i = 0; i < 55; i++) {
        expect(received.where((path) => path == '/rule/$i'), hasLength(1));
      }
      received.clear();
      SourceReviewBatchStore.forRequests(client).clear();
      expect(await setup.applyProfile(force: true), true);
      expect((await core.getProxies()).proxies.keys, containsAll(groupNames));
      expect(
        (await core.getProxies()).proxies.keys,
        isNot(contains('Imported nodes')),
      );
      expect(received, isEmpty);
    },
    skip: executable == null,
  );

  for (final scenario in [
    (outcome: 'early', first: false, blocker: ''),
    (outcome: 'pending', first: false, blocker: ''),
    (outcome: 'configuration', first: false, blocker: ''),
    (outcome: 'cancel-configuration', first: false, blocker: ''),
    (outcome: 'pending', first: true, blocker: ''),
    (outcome: 'configuration', first: true, blocker: ''),
    for (final blocker in [
      'dns',
      'logical',
      'sub-rules',
      'no-default',
      'external-only',
      'one-node',
    ])
      (outcome: 'configuration', first: true, blocker: blocker),
    (outcome: 'pending', first: true, blocker: 'empty'),
    (outcome: 'cancel-configuration', first: true, blocker: 'dns'),
  ]) {
    final outcome = scenario.outcome;
    final nodeFallback = const {
      'sub-rules',
      'no-default',
    }.contains(scenario.blocker);
    final name =
        'URL partial import $outcome first=${scenario.first} blocker=${scenario.blocker}';
    test(name, () async {
      if (scenario.first) {
        container.read(currentProfileIdProvider.notifier).value = null;
      } else {
        await existingService();
      }
      Future<List<int>> permissionBytes() async {
        final file = File('${root.path}/source-acceptance/permissions.json');
        return await file.exists() ? file.readAsBytes() : [];
      }

      final previous = await core.getConfigState();
      final permissions = await permissionBytes();
      received.clear();
      core.sourceActions.clear();
      core.calls.clear();
      responses['/partial'] =
          'proxies: [{name: inline, type: socks5, server: 127.0.0.1, port: 9}]\n'
          'proxy-providers:\n'
          '  loaded: {type: http, url: "http://127.0.0.1:${server.port}/loaded", proxy: DIRECT}\n'
          'proxy-groups: [{name: Source, type: select, proxies: [inline], use: [loaded]}]\n'
          'rule-providers:\n'
          '  Domestic: {type: http, url: "http://127.0.0.1:${server.port}/missing", proxy: DIRECT, format: text, behavior: domain}\n'
          '  Available: {type: http, url: "http://127.0.0.1:${server.port}/available", proxy: DIRECT, format: text, behavior: domain}\n'
          'dns: {nameserver: [https://1.1.1.1/dns-query]}\n'
          'rules: ["DOMAIN,first.invalid,DIRECT", "RULE-SET,Domestic,DIRECT", "RULE-SET,Available,Source", "MATCH,Source"]\n';
      responses['/loaded'] =
          'proxies: [{name: external, type: socks5, server: 127.0.0.1, port: 10}]\n';
      responses['/available'] = 'available.invalid\n';
      statuses['/missing'] = 503;
      if (scenario.blocker.isNotEmpty) {
        var material = responses['/partial']!;
        if (scenario.blocker == 'logical') {
          material = material.replaceFirst(
            '"MATCH,Source"',
            '"AND,((NETWORK,TCP),(RULE-SET,Available)),Source", "MATCH,Source"',
          );
        } else if (scenario.blocker == 'sub-rules') {
          material += 'sub-rules: {inner: ["MATCH,Source"]}\n';
        } else if (scenario.blocker == 'no-default') {
          material = material.replaceFirst(', "MATCH,Source"', '');
        } else {
          material = material.replaceFirst(
            'dns: {nameserver: [https://1.1.1.1/dns-query]}',
            'dns: {nameserver: [https://1.1.1.1/dns-query], nameserver-policy: {"rule-set:Domestic": [https://1.1.1.1/dns-query]}}',
          );
        }
        if (scenario.blocker == 'empty' ||
            scenario.blocker == 'external-only') {
          material = material.replaceFirst(
            'proxies: [{name: inline, type: socks5, server: 127.0.0.1, port: 9}]',
            'proxies: []',
          );
          material = material.replaceFirst('proxies: [inline], ', '');
        }
        if (scenario.blocker == 'empty') {
          responses['/loaded'] = 'proxies: []\n';
          material = material.replaceFirst(', "MATCH,Source"', '');
        }
        if (scenario.blocker == 'one-node') {
          statuses['/loaded'] = 503;
          statuses['/available'] = 503;
        }
        responses['/partial'] = material;
      }
      container.read(appVisibleProvider.notifier).value = true;
      var presentations = 0;
      final task = ProfileImportTask(onPhase: (_) {});
      final work = profiles.addProfileFormURL(
        'http://127.0.0.1:${server.port}/partial',
        label: 'Partial fixture',
        mode: RequestMode.direct,
        confirmed: true,
        importTask: task,
        reviewPresentation: (
          present: (child) async {
            final dialog = child as SourceReviewDialog;
            if (scenario.first) {
              expect(container.read(currentProfileIdProvider), isNull);
            }
            presentations++;
            if (outcome == 'early') {
              return const SourceReviewDecision(
                automatic: false,
                routing: 'source',
              );
            }
            await dialog.loadRelated!(dialog.review.routing);
            expect(dialog.loading!.settled, true);
            expect(core.sourceActions, isNot(contains('approveMaterial')));
            if (presentations == 1) {
              expect(dialog.loading!.ready, false);
              expect(received.where((x) => x == '/missing'), hasLength(1));
              expect(received.where((x) => x == '/loaded'), hasLength(1));
              expect(received.where((x) => x == '/available'), hasLength(1));
              expect(
                dialog.canUseAvailableConfiguration!(),
                scenario.blocker != 'empty',
              );
              return SourceReviewDecision(
                automatic: false,
                routing: 'source',
                importChoice: outcome == 'pending'
                    ? SourceImportChoice.savePending
                    : SourceImportChoice.availableConfiguration,
              );
            }
            expect(dialog.partialConfiguration, isNotNull);
            expect(dialog.routingEditable, false);
            expect(dialog.loading!.ready, true);
            expect(received.where((x) => x == '/missing'), hasLength(1));
            expect(received.where((x) => x == '/loaded'), hasLength(1));
            expect(received.where((x) => x == '/available'), hasLength(1));
            if (nodeFallback) {
              expect(dialog.partialConfiguration!.changes['nodesOnly'], true);
            } else {
              expect(
                dialog.partialConfiguration!.changes['nodesOnly'],
                isNot(true),
              );
              expect(
                dialog.partialConfiguration!.changes['removedRules'],
                contains('RULE-SET,Domestic,DIRECT'),
              );
            }
            return outcome == 'cancel-configuration'
                ? null
                : const SourceReviewDecision(
                    automatic: false,
                    routing: 'source',
                  );
          },
          onDecision: (_) {},
        ),
      );
      if (outcome == 'cancel-configuration' || outcome == 'early') {
        await expectLater(work, throwsA(isA<RequestUnavailable>()));
        expect(
          (await store.profilesDao.query().get()).map((p) => p.id),
          scenario.first ? <int>[] : [1],
        );
        expect(await permissionBytes(), permissions);
        return;
      }
      expect((await work)?.materialSaved, true);
      final row = (await store.profilesDao.query().get()).singleWhere(
        (p) => p.id != 1,
      );
      expect(row.url, 'http://127.0.0.1:${server.port}/partial');
      expect(
        container.read(currentProfileIdProvider),
        scenario.first ? (outcome == 'pending' ? null : row.id) : 1,
      );
      expect((await core.getConfigState()).fence, previous.fence);
      expect(core.calls, isNot(contains(CoreMethod.activateConfig)));
      final raw = await File(
        await appPath.getProfilePath('${row.id}'),
      ).readAsString();
      if (outcome == 'pending') {
        expect(raw, responses['/partial']);
        expect(
          await profiles.sourceReviewStatus(row),
          SourceReviewStatus.required,
        );
        expect(core.sourceActions, isNot(contains('approveMaterial')));
        expect(await permissionBytes(), permissions);
      } else {
        final map = jsonDecode(raw) as Map;
        if (nodeFallback) {
          expect(map.keys.toSet(), {'proxies', 'proxy-groups', 'rules'});
          expect(
            (map['proxies'] as List).map((p) => p['name']),
            scenario.blocker == 'external-only'
                ? ['external']
                : scenario.blocker == 'one-node'
                ? ['inline']
                : ['inline', 'external'],
          );
          expect(map['rules'], ['MATCH,Imported nodes']);
        } else {
          expect(
            (map['proxies'] as List).map((p) => p['name']),
            scenario.blocker == 'external-only' ? <String>[] : ['inline'],
          );
          expect(map['rules'], [
            'DOMAIN,first.invalid,DIRECT',
            if (scenario.blocker != 'one-node') 'RULE-SET,Available,Source',
            if (scenario.blocker == 'logical')
              'AND,((NETWORK,TCP),(RULE-SET,Available)),Source',
            'MATCH,Source',
          ]);
          expect((map['proxy-groups'] as List).single['name'], 'Source');
          expect(
            (map['rule-providers'] as Map).keys,
            scenario.blocker == 'one-node' ? <String>[] : ['Available'],
          );
          expect(
            (map['proxy-providers'] as Map).keys,
            scenario.blocker == 'one-node' ? <String>[] : ['loaded'],
          );
          expect(map['dns'], {
            'nameserver': ['https://1.1.1.1/dns-query'],
          });
        }
        expect(row.autoUpdate, false);
        expect(
          await profiles.sourceReviewStatus(row),
          SourceReviewStatus.ready,
        );
        SourceReviewBatchStore.forRequests(client).clear();
        final source = await client.captureSource('profile:${row.id}');
        final grant = await SourceAcceptance(
          core: CoreController.scoped(core),
          requests: client,
        ).permissions(source: source, kind: 'profile');
        expect(grant.single.acceptedCount, greaterThan(0));
        expect(grant.single.automatic, false);
        received.clear();
        confirmations.clear();
        container.read(currentProfileIdProvider.notifier).value = row.id;
        expect(await setup.applyProfile(force: true), true);
        expect(received, isEmpty);
        expect(confirmations, isEmpty);
        if (scenario.blocker.isNotEmpty) return;
        received.clear();
        if (!nodeFallback) {
          var updateReviews = 0;
          final updateConfirmation = Provider<SourceConfirmation>(
            (ref) =>
                (review) => confirmSourceReview(
                  ref,
                  review,
                  present: (child) async {
                    updateReviews++;
                    final dialog = child as SourceReviewDialog;
                    await dialog.loadRelated!(dialog.review.routing);
                    expect(dialog.allowPartialImport, false);
                    return SourceReviewDecision(
                      automatic: false,
                      routing: 'source',
                      importChoice: dialog.loading!.ready
                          ? SourceImportChoice.complete
                          : SourceImportChoice.availableConfiguration,
                    );
                  },
                ),
          );
          expect(
            (await profiles.updateProfile(
              row,
              confirm: container.read(updateConfirmation),
            )).materialSaved,
            true,
          );
          expect(updateReviews, greaterThan(0));
          expect(
            await File(
              await appPath.getProfilePath('${row.id}'),
            ).readAsString(),
            raw,
          );
          expect(received.where((x) => x == '/missing'), hasLength(1));
          expect(received.where((x) => x == '/loaded'), isEmpty);
          expect(received.where((x) => x == '/available'), isEmpty);
          received.clear();
        }
        statuses['/missing'] = 200;
        statuses['/loaded'] = 200;
        statuses['/available'] = 200;
        responses['/missing'] = 'example.invalid\n';
        final confirmation = Provider<SourceConfirmation>(
          (ref) =>
              (review) => confirmSourceReview(
                ref,
                review,
                present: (child) async {
                  final dialog = child as SourceReviewDialog;
                  await dialog.loadRelated!(dialog.review.routing);
                  expect(dialog.loading!.ready, true);
                  expect(dialog.allowPartialImport, false);
                  return const SourceReviewDecision(
                    automatic: false,
                    routing: 'source',
                  );
                },
              ),
        );
        expect(
          (await profiles.updateProfile(
            row,
            confirm: container.read(confirmation),
          )).materialSaved,
          true,
        );
        expect(
          await File(await appPath.getProfilePath('${row.id}')).readAsString(),
          responses['/partial'],
        );
        expect(received.where((x) => x == '/missing'), hasLength(1));
        expect(
          received.where((x) => x == '/loaded'),
          hasLength(nodeFallback ? 1 : 0),
        );
        expect(
          received.where((x) => x == '/available'),
          hasLength(nodeFallback ? 1 : 0),
        );
      }
    }, skip: executable == null);
  }

  testWidgets(
    'subscription batch cancels safely then accepts once and reuses persisted sources',
    (tester) async {
      bool canAccept() {
        final button = find.widgetWithText(TextButton, 'Accept this revision');
        return button.evaluate().isNotEmpty &&
            tester.widget<TextButton>(button).onPressed != null;
      }

      for (final outcome in ['background', 'cancel', 'retry', 'accept']) {
        final accept = outcome == 'accept';
        interactiveReview = true;
        container.read(appVisibleProvider.notifier).value = true;
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        container.read(viewSizeProvider.notifier).value = const Size(1000, 900);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(child: Scaffold()),
          ),
        );
        final p = profile(2);
        responses['/2'] =
            'mode: rule\n'
            'rule-providers:\n'
            '  first: {type: http, url: "http://127.0.0.1:${server.port}/first", proxy: DIRECT, format: text, behavior: domain}\n'
            '  second: {type: http, url: "http://127.0.0.1:${server.port}/second", proxy: DIRECT, format: text, behavior: domain}\n'
            'rules: ["RULE-SET,first,DIRECT", "RULE-SET,second,DIRECT", "MATCH,DIRECT"]\n';
        responses['/first'] = 'first.invalid\n';
        responses['/second'] = 'second.invalid\n';
        if (outcome == 'retry') {
          responses['/2'] = responses['/2']!.replaceFirst(
            'rules: [',
            '  third: {type: http, url: "http://127.0.0.1:${server.port}/third", proxy: DIRECT, format: text, behavior: domain}\n'
                '  fourth: {type: http, url: "http://127.0.0.1:${server.port}/fourth", proxy: DIRECT, format: text, behavior: domain}\n'
                'rules: [',
          );
          responses['/third'] = 'third.invalid\n';
          responses['/fourth'] = 'fourth.invalid\n';
          statuses['/first'] = 503;
          for (final path in ['/first', '/second', '/third', '/fourth']) {
            holds[path] = Completer<void>();
          }
          received.clear();
        }
        ProfileRefreshResult? result;
        Object? failure;
        var finished = false;
        await tester.runAsync(() async {
          unawaited(
            profiles
                .updateProfile(p, importing: true)
                .then(
                  (value) {
                    result = value;
                    finished = true;
                  },
                  onError: (Object error) {
                    failure = error;
                    finished = true;
                  },
                ),
          );
        });
        if (outcome == 'retry') {
          for (
            var i = 0;
            i < 1200 && received.where((path) => path != '/2').length < 3;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(received.where((path) => path != '/2'), hasLength(3));
          expect(find.text('Associated sources: 4'), findsOneWidget);
          expect(find.text('Waiting'), findsOneWidget);
          expect(canAccept(), isFalse);
          for (final gate in holds.values) {
            if (!gate.isCompleted) gate.complete();
          }
          for (
            var i = 0;
            i < 1200 &&
                (find.byType(SourceReviewDialog).evaluate().isEmpty ||
                    tester
                        .widget<SourceReviewDialog>(
                          find.byType(SourceReviewDialog),
                        )
                        .loading!
                        .busy);
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          final loading = tester
              .widget<SourceReviewDialog>(find.byType(SourceReviewDialog))
              .loading!;
          final failed = loading.items.singleWhere(
            (item) => item.error != null,
          );
          expect(failed.label, 'first');
          expect(canAccept(), isFalse);
          statuses.remove('/first');
          final retryButton = find.byKey(ValueKey('retry:${failed.key}'));
          await tester.ensureVisible(retryButton);
          await tester.tap(retryButton);
        }
        for (var i = 0; i < 1200 && !canAccept() && !finished; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(failure, isNull);
        expect(
          find.text('Review subscription'),
          findsOneWidget,
          reason:
              'finished=$finished failure=$failure received=$received reviews=${core.sourceReviews} confirmations=${confirmations.map((r) => r.kind).toList()}',
        );
        expect(
          find.text('Associated sources: ${outcome == 'retry' ? 4 : 2}'),
          findsOneWidget,
        );
        if (outcome == 'retry') {
          expect(received.where((path) => path == '/first'), hasLength(2));
          for (final path in ['/second', '/third', '/fourth']) {
            expect(received.where((item) => item == path), hasLength(1));
          }
          holds.clear();
        }
        final before = await tester.runAsync(
          () async =>
              SourceAcceptance(
                core: CoreController.scoped(core),
                requests: client,
              ).permissions(
                source: await client.captureSource('profile:2'),
                kind: 'profile',
              ),
        );
        expect(before, isEmpty);
        if (outcome == 'background') {
          container.read(appVisibleProvider.notifier).value = false;
        } else {
          await tester.tap(
            find.text(accept ? 'Accept this revision' : 'Cancel'),
          );
        }
        for (var i = 0; i < 1200 && !finished; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          finished,
          isTrue,
          reason: '$failure ${core.sourceActions} ${core.calls}',
        );
        await tester.pumpAndSettle();
        expect(find.byType(SourceReviewDialog), findsNothing);
        if (accept) {
          expect(failure, isNull);
          expect(result?.materialSaved, isTrue);
          SourceReviewBatchStore.forRequests(client).clear();
          received.clear();
          container.read(currentProfileIdProvider.notifier).value = 2;
          final applied = await tester.runAsync(
            () => setup.applyProfile(force: true, allowSourceReview: true),
          );
          await tester.pumpAndSettle();
          expect(applied, isTrue, reason: '${core.sourceReviews}');
          expect(
            await tester.runAsync(() => profiles.sourceReviewStatus(p)),
            SourceReviewStatus.ready,
          );
          expect(received, isEmpty);
          expect(find.byType(SourceReviewDialog), findsNothing);
          final legacyReview = await tester.runAsync(() async {
            final composition = await setup.getProfile(
              setupState: await container.read(setupStateProvider(2).future),
              patchConfig: container.read(patchClashConfigProvider),
            );
            final service = SourceAcceptance(
              core: CoreController.scoped(core),
              requests: client,
            );
            final rootSource = await client.captureSource('profile:2');
            final preview = await service.preview(
              source: rootSource,
              kind: 'config',
              body: composition.yaml,
              rootKey: rootSource.key,
            );
            final plan = (preview['providers'] as List).first as Map;
            final mapping = Map<String, Object?>.from(plan['mapping'] as Map);
            final bytes = utf8.encode(responses['/${plan['name']}']!);
            return SourceReview(
              source: await client.captureSource(plan['key'] as String),
              subscriptionKey: rootSource.key,
              key: plan['key'] as String,
              kind: plan['kind'] as String,
              bodyHash: sha256.convert(bytes).toString(),
              settingsHash: SourceAcceptance.fingerprint(mapping),
              binaryMaterial: bytes,
              label: plan['name'] as String,
              origin: '',
              reasons: const ['first_use'],
              routing: 'source',
            );
          });
          SourceReviewBatchStore.forRequests(client).clear();
          SourceReviewDecision? legacyDecision;
          await tester.runAsync(() async {
            unawaited(
              container
                  .read(sourceConfirmationProvider)(legacyReview!)
                  .then((value) => legacyDecision = value),
            );
          });
          for (var i = 0; i < 1200 && !canAccept(); i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(find.text('Review subscription'), findsOneWidget);
          expect(find.text('Associated sources: 2'), findsOneWidget);
          await tester.tap(find.text('Accept this revision'));
          for (var i = 0; i < 1200 && legacyDecision == null; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(legacyDecision, isNotNull);
          expect(received, isEmpty);
          await tester.pumpAndSettle();
          expect(find.byType(SourceReviewDialog), findsNothing);
          SourceReviewBatchStore.forRequests(client).clear();
          var menuDone = false;
          Object? menuError;
          await tester.runAsync(() async {
            unawaited(
              profiles
                  .manageSourcePermissions(p, review: true)
                  .then(
                    (_) => menuDone = true,
                    onError: (Object error) {
                      menuError = error;
                      menuDone = true;
                    },
                  ),
            );
          });
          await tester.pump();
          expect(find.text('Review subscription'), findsOneWidget);
          for (var i = 0; i < 1200 && !canAccept() && !menuDone; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(menuError, isNull);
          expect(canAccept(), isTrue);
          expect(received, isEmpty);
          await tester.tap(find.text('Accept this revision'));
          for (var i = 0; i < 1200 && !menuDone; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(menuDone, isTrue);
          expect(menuError, isNull);
          expect(
            await tester.runAsync(() => profiles.sourceReviewStatus(p)),
            SourceReviewStatus.ready,
          );
          await tester.pumpAndSettle();
          expect(find.byType(SourceReviewDialog), findsNothing);
          expect(received, isEmpty);
        } else {
          expect(failure, isA<RequestUnavailable>());
          expect(
            await tester.runAsync(() => store.profilesDao.query().get()),
            isEmpty,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: executable == null,
  );
}
