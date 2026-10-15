import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/dav_client.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';
import '../helpers/test_app.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import '../widgets/edit_profile_focus_test.dart' as edit;
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Native implements Service {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  _Native(this.endpoint);
  String endpoint;
  final calls = <Map<String, Object?>>[];
  final listeners = <ServiceListener>[];
  var revision = 1;
  var epoch = 'synthetic';
  var paused = false;
  var stopReason = 'userStop';
  var rejectBegin = false;
  var running = false;
  var bridgeEligibility = false;
  var hasProxy = false;
  var valid = true;
  var dataset = 1;
  final sources = <String, int>{};
  Map<String, Object?> get snapshot => {
    'processEpoch': epoch,
    'revision': revision,
    'intentRunning': running,
    'paused': paused,
    'directNetworkId': 'synthetic-network',
    'defaultNetworkKind': 'nonVpn',
    'protectPhase': 'none',
    'phase': running ? 'started' : 'stopped',
    'reason': running ? 'none' : stopReason,
  };

  @override
  void addListener(ServiceListener listener) => listeners.add(listener);

  @override
  void removeListener(ServiceListener listener) => listeners.remove(listener);

  void stopPending(String change) {
    if (change == 'epoch') {
      epoch = 'new synthetic';
    } else {
      revision++;
    }
    running = false;
    paused = change == 'ssid';
    stopReason = paused ? 'excludedSsid' : 'userStop';
    for (final listener in List.of(listeners)) {
      listener.onRequestState(snapshot);
    }
  }

  void revoke() {
    valid = false;
    revision++;
    for (final listener in List.of(listeners)) {
      listener.onRequestState(snapshot);
    }
  }

  @override
  Future<Map<String, Object?>> requestControl(Map<String, Object?> data) async {
    calls.add(Map.of(data));
    if (data['action'] == 'invalidateDataset') dataset++;
    if (data['action'] == 'invalidate') {
      final key = data['key']! as String;
      sources[key] = (sources[key] ?? 0) + 1;
    }
    if (data['action'] == 'begin' && bridgeEligibility) {
      final result = await Process.run(
        'go',
        ['test', '-run', r'^TestAppRequestDartSpec$', '-count=1', '.'],
        workingDirectory: 'core',
        environment: {
          'L1_REQUEST_SPEC': jsonEncode({'State': snapshot, 'Params': data}),
          'CGO_ENABLED': '0',
          'GOPROXY': 'off',
          'GOSUMDB': 'off',
          'GOTOOLCHAIN': 'local',
        },
      );
      if (result.exitCode != 0) return {'error': 'request_blocked'};
    }
    return switch (data['action']) {
      'attach' => {'client': 'synthetic-client'},
      'inspect' => {
        'state': snapshot,
        'owner': 1,
        'phase': 'ready',
        'dataset': dataset,
        'sourceRevision': sources[data['key']] ?? 0,
        'commits': 0,
        'hasProxy': hasProxy,
      },
      'begin' =>
        rejectBegin
            ? {'error': 'request_blocked'}
            : {
                'id': 'scope-${calls.length}',
                'owner': 1,
                'dataset': 1,
                'sourceRevision': 0,
                'operation': 1,
                'user': 'scoped',
                'password': 'synthetic',
                'endpoint': endpoint,
              },
      'lock' => {'id': 'local-${calls.length}'},
      'permit' => {'permit': 'synthetic-permit'},
      'check' || 'grant' => {'ok': valid},
      _ => {'ok': true},
    };
  }
}

class _SocketProbe extends Notifier<RoutedProbeState<String, String>>
    with RoutedProbe<String, String> {
  _SocketProbe(this.client);
  final Request client;
  final sessions = <RequestSession>[];
  final answers = <Completer<void>>[];
  @override
  RoutedProbeState<String, String> build() => buildProbe();
  @override
  void cancelProbe(String target) {
    for (final session in sessions) {
      session.close();
    }
  }

  @override
  Future<Map<String, ProbeAnswer<String>>> probe(
    String target,
    RouteState route,
  ) async {
    final session = await client.begin(
      key: 'probe:$target',
      url: 'http://127.0.0.1/',
      mode: RequestMode.direct,
      automatic: true,
    );
    sessions.add(session);
    final answer = Completer<void>();
    answers.add(answer);
    try {
      await session.dio.get<String>('http://127.0.0.1/');
    } catch (_) {}
    await answer.future;
    return {
      target: ProbeAnswer(
        value: 'late result',
        coreEpoch: route.coreEpoch,
        picksVersion: route.picksVersion,
      ),
    };
  }
}

class _ValidationCore implements CoreHandlerInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<String> validateConfig(String path) async => '';
  @override
  Future<String> clearEffect(int id) async => '';
}

class _ImportProfiles extends ProfilesAction {
  _ImportProfiles(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _ImportScripts extends ScriptsAction {
  _ImportScripts(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _ImportBackup extends BackupAction {
  _ImportBackup(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _ScopedDAV extends DAVClient {
  _ScopedDAV(super.props, this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late ProviderContainer container;
  late ServerSocket proxy;
  late _Native native;
  late Request client;
  late db.Database database;
  final proxyHeaders = <String?>[];
  final originHeaders = <String?>[];
  final sockets = <Socket>[];
  final bridgeStates = <String>[];

  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('flclash-scope-');
    AppPath.supportDirectory = () async => temporary;
    AppPath.temporaryDirectory = () async => temporary;
    AppPath.cacheDirectory = () async => temporary;
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'synthetic',
      packageName: 'synthetic',
      version: '1.0.0',
      buildNumber: '1',
    );
  });
  tearDownAll(() => temporary.delete(recursive: true));

  setUp(() async {
    proxyHeaders.clear();
    originHeaders.clear();
    bridgeStates.clear();
    proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    proxy.listen((inbound) {
      sockets.add(inbound);
      final pending = <int>[];
      Socket? outbound;
      var accepted = false;
      late StreamSubscription<List<int>> subscription;
      subscription = inbound.listen(
        (chunk) async {
          if (accepted) {
            outbound?.add(chunk);
            return;
          }
          pending.addAll(chunk);
          final header = latin1.decode(pending);
          final end = header.indexOf('\r\n\r\n');
          if (end < 0) return;
          accepted = true;
          subscription.pause();
          final first = header.split('\r\n').first.split(' ');
          bridgeStates.add('${first[0]} ${first[1]}');
          final credential = RegExp(
            r'^proxy-authorization:\s*(.*)$',
            caseSensitive: false,
            multiLine: true,
          ).firstMatch(header)?.group(1)?.trim();
          proxyHeaders.add(credential);
          if (first[0] == 'CONNECT') {
            final target = Uri.parse('https://${first[1]}');
            expect(InternetAddress.tryParse(target.host)?.isLoopback, isTrue);
            outbound = await Socket.connect(target.host, target.port);
            sockets.add(outbound!);
            inbound.write('HTTP/1.1 200 Connection established\r\n\r\n');
            await inbound.flush();
            bridgeStates.add('headers sent');
            outbound!.listen(
              inbound.add,
              onDone: inbound.destroy,
              onError: (Object _) => inbound.destroy(),
            );
            if (pending.length > end + 4) {
              outbound!.add(pending.sublist(end + 4));
            }
            subscription.resume();
          } else {
            inbound.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\nsynthetic',
            );
            await inbound.flush();
            inbound.destroy();
          }
        },
        onDone: () {
          outbound?.destroy();
          unawaited(subscription.cancel());
        },
        onError: (Object _) => outbound?.destroy(),
      );
    });
    native = _Native('127.0.0.1:${proxy.port}');
    database = db.Database(NativeDatabase.memory());
    db.database = database;
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(
          CoreController.scoped(_ValidationCore()),
        ),
        profilesActionProvider.overrideWith(() => _ImportProfiles(client)),
        scriptsActionProvider.overrideWith(() => _ImportScripts(client)),
        backupActionProvider.overrideWith(() => _ImportBackup(client)),
      ],
    );
    container.listen(configProvider, (_, _) {});
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(disclaimerAccepted: true, checkCertificate: false),
        );
    client = Request.scoped(native: native, isAndroid: true)..attach(container);
    await client.ready();
  });
  tearDown(() async {
    await client.detach();
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await proxy.close();
    container.dispose();
    await database.close();
  });

  test(
    'actual Dart Direct specs pass the Go registry in running and idle states',
    () async {
      native.bridgeEligibility = true;
      for (final running in [false, true]) {
        native.running = running;
        final session = await client.begin(
          key: 'profile:direct',
          url: 'http://127.0.0.1/',
          mode: RequestMode.direct,
        );
        session.close();
      }
      native.running = true;
      final automatic = await client.begin(
        key: 'profile:auto-direct',
        url: 'http://127.0.0.1/',
        mode: RequestMode.direct,
        automatic: true,
      );
      automatic.close();
      native.running = false;
      await expectLater(
        client.begin(
          key: 'profile:auto-direct',
          url: 'http://127.0.0.1/',
          mode: RequestMode.direct,
          automatic: true,
        ),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(proxyHeaders, isEmpty);
    },
  );

  Future<void> showApp(WidgetTester tester) async {
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1000, 800);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForRecovery(WidgetTester tester) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find
          .text(AppLocalizations.current.requestDirectRecoveryTitle)
          .evaluate()
          .isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }
    fail('actual import did not reach the one-operation recovery dialog');
  }

  testWidgets(
    'first Proxy profile URL import asks once and preserves its preference',
    (tester) async {
      await showApp(tester);
      late Future<void> work;
      await tester.runAsync(() async {
        work = container
            .read(profilesActionProvider.notifier)
            .addProfileFormURL(
              'http://127.0.0.1/sub',
              label: 'synthetic first',
              mode: RequestMode.proxy,
              confirmed: true,
            );
      });
      await tester.pumpAndSettle();
      expect(native.calls.where((call) => call['action'] == 'begin'), isEmpty);
      await waitForRecovery(tester);
      await tester.tap(find.text(AppLocalizations.current.confirm));
      await tester.runAsync(() => work);
      await tester.pumpAndSettle();
      final saved = (await database.profilesDao.query().get()).single;
      expect(saved.requestMode, RequestMode.proxy);
      expect(
        native.calls.firstWhere((call) => call['action'] == 'begin')['kind'],
        'bootstrap',
      );
      expect(proxyHeaders, isNotEmpty);
    },
  );

  testWidgets('declined first Proxy script import sends no request', (
    tester,
  ) async {
    await showApp(tester);
    final script = Script.create(
      label: 'synthetic first',
      url: 'http://127.0.0.1/script',
    ).copyWith(requestMode: RequestMode.proxy);
    late Future<void> work;
    await tester.runAsync(() async {
      work = container
          .read(scriptsActionProvider.notifier)
          .updateScript(script);
    });
    final expected = expectLater(work, throwsA(isA<RequestUnavailable>()));
    await tester.pumpAndSettle();
    await waitForRecovery(tester);
    await tester.tap(find.text(AppLocalizations.current.cancel));
    await tester.runAsync(() => expected);
    expect(native.calls.where((call) => call['action'] == 'begin'), isEmpty);
    expect(proxyHeaders, isEmpty);
    expect(await database.scriptsDao.query().get(), isEmpty);
  });

  testWidgets(
    'first Proxy script import keeps Proxy after accepted one-operation Direct',
    (tester) async {
      await showApp(tester);
      final script = Script.create(
        label: 'synthetic first',
        url: 'http://127.0.0.1/script',
      ).copyWith(requestMode: RequestMode.proxy);
      late Future<void> work;
      await tester.runAsync(() async {
        work = container
            .read(scriptsActionProvider.notifier)
            .updateScript(script);
      });
      await tester.pumpAndSettle();
      await waitForRecovery(tester);
      await tester.tap(find.text(AppLocalizations.current.confirm));
      await tester.runAsync(() => work);
      expect(
        (await database.scriptsDao.query().get()).single.requestMode,
        RequestMode.proxy,
      );
      expect(
        native.calls.firstWhere((call) => call['action'] == 'begin')['kind'],
        'bootstrap',
      );
    },
  );

  test(
    'ordinary running proxy failure never asks for a bootstrap permit',
    () async {
      native.running = true;
      native.rejectBegin = true;
      await expectLater(
        client.begin(
          key: 'profile:ordinary',
          url: 'http://127.0.0.1/',
          mode: RequestMode.proxy,
          bootstrapIfUnconfigured: true,
        ),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(native.calls.where((call) => call['action'] == 'permit'), isEmpty);
      expect(proxyHeaders, isEmpty);
    },
  );

  test(
    'hiding an in-flight probe closes its socket and rejects a late answer',
    () async {
      native.running = true;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final firstClosed = Completer<void>();
      final started = Completer<void>();
      final secondStarted = Completer<void>();
      var connections = 0;
      final held = <Socket>[];
      final listener = server.listen((socket) {
        held.add(socket);
        connections++;
        if (connections == 1) {
          started.complete();
        } else {
          secondStarted.complete();
        }
        socket.listen(
          (_) {},
          onDone: () {
            if (!firstClosed.isCompleted) firstClosed.complete();
          },
        );
      });
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await listener.cancel();
        await server.close();
      });
      native.endpoint = '127.0.0.1:${server.port}';
      final provider =
          NotifierProvider<_SocketProbe, RoutedProbeState<String, String>>(
            () => _SocketProbe(client),
          );
      final probeContainer = ProviderContainer(
        overrides: [
          routeTrackerProvider.overrideWithBuild(
            (_, _) => const RouteState(
              coreEpoch: 1,
              picksVersion: 1,
              hostEpoch: 1,
              proxied: true,
              synced: true,
              live: true,
            ),
          ),
        ],
      );
      addTearDown(probeContainer.dispose);
      probeContainer.listen(provider, (_, _) {});
      final probe = probeContainer.read(provider.notifier);
      probe.watch('a');
      await started.future.timeout(const Duration(seconds: 2));
      probeContainer.read(appVisibleProvider.notifier).value = false;
      await firstClosed.future.timeout(const Duration(seconds: 2));
      expect(probe.sessions.first.cancelToken.isCancelled, isTrue);
      probe.answers.first.complete();
      await pumpEventQueue();
      expect(
        probeContainer.read(provider).entryOf('a').phase,
        isNot(ProbePhase.fresh),
      );
      probeContainer.read(appVisibleProvider.notifier).value = true;
      await secondStarted.future.timeout(const Duration(seconds: 2));
      expect(probe.sessions.length, 2);
      probe.cancelProbe('a');
      probe.answers.last.complete();
      await pumpEventQueue();
    },
  );

  test(
    'hiding DAV ping closes real IO and resume registers a fresh ping',
    () async {
      native.running = true;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>(), closed = Completer<void>();
      var count = 0;
      final held = <Socket>[];
      final listener = server.listen((socket) {
        held.add(socket);
        count++;
        final first = count == 1;
        socket.listen(
          (_) {
            if (first) {
              if (!started.isCompleted) started.complete();
            } else {
              socket.write(
                'HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
              );
              unawaited(socket.flush().then((_) => socket.destroy()));
            }
          },
          onDone: () {
            if (first && !closed.isCompleted) closed.complete();
          },
        );
      });
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await listener.cancel();
        await server.close();
      });
      native.endpoint = '127.0.0.1:${server.port}';
      const props = DAVProps(
        uri: 'http://127.0.0.1/dav',
        user: 'synthetic',
        password: 'synthetic',
        fileName: 'test.zip',
        requestMode: RequestMode.direct,
      );
      container.read(davSettingProvider.notifier).update((_) => props);
      final controller = DAVConnectionController(
        createClient: (props) => _ScopedDAV(props, client),
      );
      addTearDown(controller.dispose);
      final old = controller.update(props);
      await started.future.timeout(const Duration(seconds: 2));
      await controller.setVisible(false);
      await old;
      await closed.future.timeout(const Duration(seconds: 2));
      expect(controller.value, isNull);
      await controller.setVisible(true).timeout(const Duration(seconds: 2));
      expect(controller.value, isTrue);
      expect(count, 2);
    },
  );

  testWidgets(
    'URL confirmation precedes delayed refresh and queued UI fields preserve newer Proxy',
    (tester) async {
      native.running = true;
      final original = Profile.normal(
        label: 'synthetic edit',
        url: 'http://127.0.0.1/original',
      );
      await tester.runAsync(
        () => database.profiles.put(original.toCompanion()),
      );
      await edit.pumpEditProfile(
        tester,
        profile: original,
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => original.id),
          coreHandlerProvider.overrideWithValue(
            CoreController.scoped(_ValidationCore()),
          ),
          profilesActionProvider.overrideWith(() => _ImportProfiles(client)),
        ],
      );
      final formContainer = globalState.container;
      formContainer.listen(configProvider, (_, _) {});
      await tester.enterText(
        find.widgetWithText(TextFormField, AppLocalizations.current.url),
        'http://127.0.0.1/older-edit',
      );
      await tester.tap(find.byTooltip(AppLocalizations.current.save));
      var registered = false;
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final profile = await tester.runAsync(
          () async => (await database.profilesDao.query().get()).single,
        );
        if (profile!.url.endsWith('/older-edit')) {
          registered = true;
          break;
        }
      }
      expect(registered, isTrue);
      final entered = Completer<void>(), release = Completer<void>();
      late Future<void> holding;
      await tester.runAsync(() async {
        holding = dataMutations.run(() async {
          entered.complete();
          await release.future;
        });
      });
      for (var attempt = 0; !entered.isCompleted && attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(entered.isCompleted, isTrue);
      final newer = original.copyWith(
        url: 'http://127.0.0.1/new-source',
        requestMode: RequestMode.proxy,
        requestProxy: 'new target',
      );
      var saved = false, drained = false;
      Object? saveError;
      await tester.runAsync(() async {
        unawaited(
          formContainer
              .read(profilesActionProvider.notifier)
              .putProfile(newer)
              .then(
                (_) => saved = true,
                onError: (Object error) {
                  saveError = error;
                },
              ),
        );
        final proxies = formContainer.read(proxiesActionProvider.notifier);
        proxies.updateCurrentGroupName('new group');
        proxies.updateCurrentUnfoldSet({'new group'});
        release.complete();
        unawaited(holding.then((_) {}));
        unawaited(dataMutations.run(() async {}).then((_) => drained = true));
      });
      for (var attempt = 0; !drained && attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(saveError, isNull);
      expect(saved, isTrue);
      expect(drained, isTrue);
      await tester.pump(commonDuration + const Duration(milliseconds: 1));
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final profile = (await tester.runAsync(
        () async => (await database.profilesDao.query().get()).single,
      ))!;
      expect(
        (profile.url, profile.requestMode, profile.requestProxy),
        ('http://127.0.0.1/new-source', RequestMode.proxy, 'new target'),
      );
      expect(profile.currentGroupName, 'new group');
      expect(profile.unfoldSet, {'new group'});
      expect(native.calls.where((call) => call['action'] == 'begin'), isEmpty);
      expect(proxyHeaders, isEmpty);
    },
  );

  for (final change in [
    'delete',
    'restore',
    'file',
    'fields',
    'stop',
    'ssid',
    'epoch',
  ]) {
    testWidgets(
      'confirmed pending refresh handles $change by source generation',
      (tester) async {
        native.running = true;
        final original = Profile.normal(
          label: 'pending $change',
          url: 'http://127.0.0.1/original',
        );
        await tester.runAsync(
          () => database.profiles.put(original.toCompanion()),
        );
        await edit.pumpEditProfile(
          tester,
          profile: original,
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => original.id),
            coreHandlerProvider.overrideWithValue(
              CoreController.scoped(_ValidationCore()),
            ),
            profilesActionProvider.overrideWith(() => _ImportProfiles(client)),
            backupActionProvider.overrideWith(() => _ImportBackup(client)),
          ],
        );
        final form = globalState.container;
        form.listen(configProvider, (_, _) {});
        await tester.enterText(
          find.widgetWithText(TextFormField, AppLocalizations.current.url),
          'http://127.0.0.1/confirmed',
        );
        await tester.tap(find.byTooltip(AppLocalizations.current.save));
        var drained = false;
        await tester.runAsync(() async {
          unawaited(dataMutations.run(() async {}).then((_) => drained = true));
        });
        for (var i = 0; !drained && i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(drained, isTrue);
        final confirmed = (await tester.runAsync(
          () async => (await database.profilesDao.query().get()).single,
        ))!;
        expect(confirmed.url, endsWith('/confirmed'));
        final target = await tester.runAsync(
          () => appPath.getProfilePath('${original.id}'),
        );
        await tester.runAsync(() async {
          await File(target!).parent.create(recursive: true);
          await File(target).writeAsString('confirmed file');
        });
        var changed = false;
        Object? failure;
        await tester.runAsync(() async {
          final action = form.read(profilesActionProvider.notifier);
          Future<void> mutation;
          if (['stop', 'ssid', 'epoch'].contains(change)) {
            native.stopPending(change);
            mutation = Future<void>.value();
          } else if (change == 'delete') {
            mutation = action.deleteProfile(original.id);
          } else if (change == 'restore') {
            final stage = Directory('${temporary.path}/restore-${original.id}');
            final data = MigrationData(profiles: [confirmed]);
            for (final entry in BackupEntries.ofData(data)) {
              final file = File('${stage.path}/$entry');
              await file.parent.create(recursive: true);
              await file.writeAsString('restored file');
            }
            mutation = form
                .read(backupActionProvider.notifier)
                .applyRestore(
                  data,
                  RestoreOption.onlyProfiles,
                  stagingDirPath: stage.path,
                );
          } else if (change == 'fields') {
            final proxies = form.read(proxiesActionProvider.notifier);
            proxies.updateCurrentGroupName('retained group');
            proxies.updateCurrentUnfoldSet({'retained group'});
            mutation = dataMutations.run(() async {});
          } else {
            mutation = action.importFile(
              confirmed,
              utf8.encode('local replacement'),
            );
          }
          unawaited(
            mutation.then(
              (_) => changed = true,
              onError: (Object error) {
                failure = error;
                changed = true;
              },
            ),
          );
        });
        for (var i = 0; !changed && i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(failure, isNull);
        expect(changed, isTrue);
        await tester.pump(commonDuration + const Duration(milliseconds: 1));
        for (var i = 0; i < (change == 'fields' ? 100 : 10); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
          if (change == 'fields' &&
              native.calls.any(
                (call) =>
                    call['action'] == 'complete' &&
                    (call['id'] as String).startsWith('scope-'),
              )) {
            break;
          }
        }
        final rows = await tester.runAsync(
          () => database.profilesDao.query().get(),
        );
        expect(
          rows!.where((row) => row.id == original.id).length,
          change == 'delete' ? 0 : 1,
        );
        expect(
          native.calls.where((call) => call['action'] == 'begin').length,
          change == 'fields' ? 1 : 0,
        );

        expect(proxyHeaders.length, change == 'fields' ? 1 : 0);
        if (change == 'fields') {
          expect(rows.single.currentGroupName, 'retained group');
          expect(rows.single.unfoldSet, {'retained group'});
        }
        if (change != 'delete') {
          expect(
            await tester.runAsync(() => File(target!).readAsString()),
            change == 'restore'
                ? 'restored file'
                : change == 'fields'
                ? 'synthetic'
                : ['stop', 'ssid', 'epoch'].contains(change)
                ? 'confirmed file'
                : 'local replacement',
          );
        }
        var queueDrained = false;
        await tester.runAsync(() async {
          unawaited(
            dataMutations.run(() async {}).then((_) => queueDrained = true),
          );
        });
        for (var i = 0; !queueDrained && i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(queueDrained, isTrue);
      },
    );
  }

  test('DAV hide resume preserves concurrent backup and restore IO', () async {
    native.running = true;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final putStarted = Completer<void>(),
        getStarted = Completer<void>(),
        pingStarted = Completer<void>();
    final release = Completer<void>();
    final held = <Socket>[];
    var pings = 0;
    final listener = server.listen((socket) {
      held.add(socket);
      final bytes = <int>[];
      var accepted = false;
      socket.listen((chunk) async {
        if (accepted) return;
        bytes.addAll(chunk);
        final header = latin1.decode(bytes);
        if (!header.contains('\r\n\r\n')) return;
        accepted = true;
        final method = header.split(' ').first;
        if (method == 'OPTIONS' && ++pings == 1) {
          pingStarted.complete();
          return;
        }
        if (method == 'PUT') {
          putStarted.complete();
          await release.future;
        }
        if (method == 'GET') {
          getStarted.complete();
          await release.future;
        }
        final body = method == 'GET' ? 'restored data' : '';
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body',
        );
        await socket.flush();
        socket.destroy();
      });
    });
    addTearDown(() async {
      for (final socket in held) {
        socket.destroy();
      }
      await listener.cancel();
      await server.close();
    });
    native.endpoint = '127.0.0.1:${server.port}';
    const props = DAVProps(
      uri: 'http://127.0.0.1/dav',
      user: 'synthetic',
      password: 'synthetic',
      fileName: 'data.zip',
      requestMode: RequestMode.direct,
    );
    container.read(davSettingProvider.notifier).update((_) => props);
    final controller = DAVConnectionController(
      createClient: (p) => _ScopedDAV(p, client),
    );
    addTearDown(controller.dispose);
    final ping = controller.update(props);
    await pingStarted.future.timeout(const Duration(seconds: 2));
    final dav = controller.client!;
    final local = File('${temporary.path}/business-upload')
      ..writeAsStringSync('backup data');
    final restored = File('${temporary.path}/business-download');
    late RequestSession backupScope, restoreScope;
    final backup = dav.operation('backup', (scope) {
      backupScope = scope;
      return dav.upload(local.path);
    });
    final restore = dav.operation('restore', (scope) {
      restoreScope = scope;
      return dav.download(restored.path);
    });
    await Future.wait([
      putStarted.future,
      getStarted.future,
    ]).timeout(const Duration(seconds: 2));
    await controller.setVisible(false);
    await ping;
    await controller.setVisible(true).timeout(const Duration(seconds: 2));
    expect(identical(controller.client, dav), isTrue);
    expect(controller.value, isTrue);
    expect(pings, 2);
    expect(backupScope.cancelToken.isCancelled, isFalse);
    expect(restoreScope.cancelToken.isCancelled, isFalse);
    release.complete();
    await Future.wait([backup, restore]).timeout(const Duration(seconds: 2));
    expect(await restored.readAsString(), 'restored data');
  });

  test(
    'confirmed native version cannot be replaced while begin waits in the write queue',
    () async {
      native.running = true;
      final source = await client.mutate(
        () => client.captureSource('profile:queued'),
      );
      final entered = Completer<void>(), release = Completer<void>();
      final holding = dataMutations.run(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final attempt = client.begin(
        key: 'profile:queued',
        url: 'http://127.0.0.1/',
        expectedSource: source,
      );
      final rejected = expectLater(attempt, throwsA(isA<RequestUnavailable>()));
      for (
        var i = 0;
        i < 100 &&
            native.calls
                    .where(
                      (call) =>
                          call['action'] == 'inspect' &&
                          call['key'] == 'profile:queued',
                    )
                    .length <
                2;
        i++
      ) {
        await pumpEventQueue();
      }
      expect(
        native.calls
            .where(
              (call) =>
                  call['action'] == 'inspect' &&
                  call['key'] == 'profile:queued',
            )
            .length,
        2,
      );
      native.stopPending('stop');
      release.complete();
      await holding;
      await rejected;
      expect(native.calls.where((call) => call['action'] == 'begin'), isEmpty);
      expect(proxyHeaders, isEmpty);
      final fresh = await client.begin(
        key: 'profile:queued',
        url: 'http://127.0.0.1/',
      );
      try {
        expect(
          (await fresh.dio.get<String>('http://127.0.0.1/')).data,
          'synthetic',
        );
      } finally {
        fresh.close();
      }
      final command = native.calls.firstWhere(
        (call) => call['action'] == 'begin',
      );
      expect(command['proxy'], 'DIRECT');
      expect((command['expectedState'] as Map)['revision'], native.revision);
    },
  );

  test('unattached requests open no proxy connection', () async {
    final unattached = Request.scoped(native: native, isAndroid: true);
    await expectLater(
      unattached.begin(key: 'profile:1', url: 'http://127.0.0.1/'),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(proxyHeaders, isEmpty);
  });

  test('manual idle Auto issues one fixed proxy capability', () async {
    final scope = await client.begin(
      key: 'profile:1',
      url: 'http://127.0.0.1/',
    );
    try {
      final response = await scope.dio.get<String>('http://127.0.0.1/');
      expect(response.data, 'synthetic');
      expect(
        proxyHeaders.single,
        'Basic ${base64Encode(utf8.encode('scoped:synthetic'))}',
      );
      expect(
        native.calls.firstWhere((call) => call['action'] == 'begin')['proxy'],
        'DIRECT',
      );
    } finally {
      scope.close();
    }
  });

  test('unavailable Proxy never retries Direct', () async {
    native.rejectBegin = true;
    await expectLater(
      client.begin(
        key: 'profile:1',
        url: 'http://127.0.0.1/',
        mode: RequestMode.proxy,
      ),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(
      native.calls
          .where((call) => call['action'] == 'begin')
          .map((call) => call['proxy']),
      ['GLOBAL'],
    );
    expect(proxyHeaders, isEmpty);
  });

  test('HTTPS CONNECT keeps proxy credentials out of the origin', () async {
    final tls = SecurityContext()
      ..useCertificateChain('test/fixtures/request_tls/cert.pem')
      ..usePrivateKey('test/fixtures/request_tls/key.pem');
    final origin = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      tls,
    );
    addTearDown(() => origin.close(force: true));
    origin.listen((incoming) async {
      originHeaders.add(
        incoming.headers.value(HttpHeaders.proxyAuthorizationHeader),
      );
      incoming.response.write('secure synthetic');
      await incoming.response.close();
    });
    final url = 'https://127.0.0.1:${origin.port}/';
    final scope = await client.begin(key: 'profile:tls', url: url);
    try {
      try {
        expect((await scope.dio.get<String>(url)).data, 'secure synthetic');
      } catch (error) {
        fail('$error; bridge=$bridgeStates');
      }
      expect(proxyHeaders.single, isNotNull);
      expect(originHeaders, [null]);
    } finally {
      scope.close();
    }
  });

  test('revocation after body prevents formal commit', () async {
    final scope = await client.begin(
      key: 'profile:1',
      url: 'http://127.0.0.1/',
    );
    await scope.dio.get<String>('http://127.0.0.1/');
    native.revoke();
    var writes = 0;
    await expectLater(
      scope.commit(() async {
        writes++;
      }),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(writes, 0);
  });

  test(
    'a granted local segment finishes and cannot authorize new network',
    () async {
      final scope = await client.begin(
        key: 'profile:1',
        url: 'http://127.0.0.1/',
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      var writes = 0;
      final committing = scope.commit(() async {
        entered.complete();
        await release.future;
        writes++;
      });
      await entered.future;
      native.revoke();
      release.complete();
      await committing;
      expect(writes, 1);
      expect(native.calls.any((call) => call['action'] == 'complete'), isTrue);
      await expectLater(scope.check(), throwsA(isA<RequestUnavailable>()));
      expect(proxyHeaders, isEmpty);
    },
  );

  test(
    'a failed database step compensates the real file replacement',
    () async {
      final target = File('${temporary.path}/formal.yaml')
        ..writeAsStringSync('previous');
      final staged = await RequestFile.stage(utf8.encode('candidate'));
      try {
        await expectLater(
          staged.replace<void>(target.path, () async {
            throw StateError('synthetic database failure');
          }),
          throwsStateError,
        );
        expect(await target.readAsString(), 'previous');
      } finally {
        await staged.close();
      }
    },
  );
}
