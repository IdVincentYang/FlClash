import 'dart:async';

import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/models/config.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/manager/vpn_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fl_clash/manager/app_manager.dart';
import 'package:fl_clash/manager/connectivity_manager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class _Service extends Mock implements Service {}

class _NativeState extends NativeRequestState {
  @override
  Map<String, Object?> build() => const {};
}

class _Profiles extends ProfilesAction {
  @override
  void build() {}
}

class _Common extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

class _Store extends StoreAction {
  @override
  void savePreferencesDebounce() {}
}

class _VpnProps extends Notifier<VpnProps> {
  @override
  VpnProps build() => const VpnProps();

  void change() => state = state.copyWith(enable: false);
}

final _vpnProps = NotifierProvider<_VpnProps, VpnProps>(_VpnProps.new);

class _Setup extends SetupAction {
  _Setup(Service native)
    : super.scoped(
        isAndroid: true,
        native: native,
        requests: Request.scoped(native: native, isAndroid: false),
      );
  int builds = 0;
  final bootstrapChoices = <bool>[];
  Completer<void>? buildGate;
  Completer<void>? stopGate;
  final listenerTargets = <bool>[];
  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    bool allowSourceReview = true,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
  }) async {
    builds++;
    bootstrapChoices.add(allowBootstrap);
    await buildGate?.future;
    return true;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    listenerTargets.add(running);
    if (!running) await stopGate?.future;
    return true;
  }

  @override
  void resetCoreTraffic() {}
}

Map<String, Object?> snapshot({
  bool paused = false,
  bool running = true,
  String phase = 'preparing',
  String reason = 'none',
  int revision = 1,
  int? intentRevision,
}) => {
  'processEpoch': 'pause-test',
  'revision': revision,
  'intentRevision': intentRevision ?? revision,
  'intentRunning': running,
  'paused': paused,
  'source': 'ssid',
  'phase': phase,
  'reason': reason,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Service native;
  late _Setup setup;
  late ProviderContainer container;
  late Completer<Map<String, Object?>> held;
  late Completer<void> entered;
  void configure({bool appManager = false}) {
    native = _Service();
    setup = _Setup(native);
    held = Completer();
    entered = Completer();
    Future<Map<String, Object?>> capture() {
      if (!entered.isCompleted) entered.complete();
      return held.future;
    }

    when(() => native.preparePauseIntent(any())).thenAnswer((_) => capture());
    when(native.getRequestState).thenAnswer((_) => capture());
    when(native.getRunTime).thenAnswer(
      (_) async => DateTime.now().subtract(const Duration(seconds: 1)),
    );
    var id = 10;
    when(
      () => native.prepareRunIntent(
        running: any(named: 'running'),
        source: any(named: 'source'),
        paused: any(named: 'paused'),
      ),
    ).thenAnswer((_) async => ++id);
    container = ProviderContainer(
      overrides: [
        setupActionProvider.overrideWith(() => setup),
        nativeRequestStateProvider.overrideWith(_NativeState.new),
        profilesActionProvider.overrideWith(_Profiles.new),
        if (!appManager) appVisibleProvider.overrideWithValue(false),
        commonActionProvider.overrideWith(_Common.new),
        storeActionProvider.overrideWith(_Store.new),
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(showTrayTitle: false),
        ),
        vpnSettingProvider.overrideWithBuild((ref, _) => ref.watch(_vpnProps)),
      ],
    );
    globalState.container = container;
    container.read(initProvider.notifier).value = true;
    container.read(setupActionProvider.notifier);
  }

  setUp(configure);
  tearDown(() => container.dispose());

  for (final entry in ['ui', 'tile', 'initialize', 'prepared', 'paused']) {
    test('only a fresh UI intent carries provider recovery: $entry', () async {
      await setup.setRunning(
        true,
        initialize: entry == 'initialize',
        preparedRequestId: entry == 'prepared' ? 99 : null,
        source: entry == 'tile' ? 'tile' : 'ui',
        paused: entry == 'paused',
      );
      expect(
        setup.bootstrapChoices,
        entry == 'paused' ? isEmpty : [entry == 'ui'],
      );
    });
  }

  test(
    'a late pause response cannot recreate intent after manual Stop',
    () async {
      final pending = setup.setPaused(false);
      await entered.future;
      await setup.setRunning(false);
      held.complete(snapshot());
      await pending;
      expect(setup.builds, 0);
      expect(setup.listenerTargets, [false]);
      expect(container.read(runTimeProvider), isNull);
    },
  );

  test(
    'an external newer native command owns runtime despite a late pause reply',
    () async {
      final pending = setup.setPaused(true);
      await entered.future;
      container
          .read(nativeRequestStateProvider.notifier)
          .onRequestState(snapshot(phase: 'started', revision: 9));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(runTimeProvider), isNotNull);
      held.complete(snapshot(paused: true, phase: 'stopping'));
      await pending;
      expect(setup.builds, 0);
      expect(setup.listenerTargets, isEmpty);
      expect(container.read(runTimeProvider), isNotNull);
    },
  );

  for (final reason in ['setupFailed', 'exiting']) {
    test('a $reason pause snapshot never becomes a new dispatch', () async {
      final pending = setup.setPaused(true);
      final assertion = expectLater(pending, throwsStateError);
      await entered.future;
      held.complete(
        snapshot(
          paused: true,
          running: false,
          phase: reason == 'exiting' ? 'stopping' : 'failed',
          reason: reason,
        ),
      );
      await assertion;
      expect(setup.builds, 0);
      expect(setup.listenerTargets, isEmpty);
    });
  }

  for (final paused in [true, false]) {
    test('same-intent observations preserve pause=$paused dispatch', () async {
      final pending = setup.setPaused(paused);
      await entered.future;
      final phase = paused ? 'stopping' : 'preparing';
      container
          .read(nativeRequestStateProvider.notifier)
          .onRequestState(
            snapshot(
              paused: paused,
              phase: phase,
              revision: 2,
              intentRevision: 1,
            ),
          );
      held.complete(snapshot(paused: paused, phase: phase));
      await pending;
      expect(setup.builds, paused ? 0 : 1);
      expect(setup.listenerTargets, paused ? [false] : isEmpty);
      expect(container.read(nativeRequestStateProvider)['revision'], 2);
    });
  }

  test(
    'a pause response cannot replace a different observed process',
    () async {
      final pending = setup.setPaused(true);
      await entered.future;
      container.read(nativeRequestStateProvider.notifier).onRequestState({
        ...snapshot(phase: 'started'),
        'processEpoch': 'new-process',
      });
      held.complete(snapshot(paused: true, phase: 'stopping'));
      await pending;
      expect(setup.listenerTargets, isEmpty);
      expect(setup.builds, 0);
      expect(
        container.read(nativeRequestStateProvider)['processEpoch'],
        'new-process',
      );
    },
  );

  for (final reason in ['setupFailed', 'exiting']) {
    test('a newer $reason observation rejects the held pause', () async {
      final pending = setup.setPaused(true);
      await entered.future;
      container
          .read(nativeRequestStateProvider.notifier)
          .onRequestState(
            snapshot(
              paused: true,
              running: reason == 'exiting',
              phase: reason == 'exiting' ? 'stopping' : 'failed',
              reason: reason,
              revision: 2,
              intentRevision: 1,
            ),
          );
      held.complete(snapshot(paused: true, phase: 'stopping'));
      await pending;
      expect(setup.listenerTargets, isEmpty);
      expect(setup.builds, 0);
    });
  }

  testWidgets('manual Stop wins while the VPN Restart action is pending', (
    tester,
  ) async {
    container.dispose();
    configure();
    globalState.lastVpnState = null;
    setup.buildGate = Completer();
    setup.stopGate = Completer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          builder: (_, child) =>
              StatusManager(child: VpnManager(child: child!)),
          home: const SizedBox(),
        ),
      ),
    );
    container.read(runTimeProvider.notifier).value = 1;
    container.read(_vpnProps.notifier).change();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Restart'));
    await tester.pump();
    final stop = setup.setRunning(false);
    var stopped = false;
    unawaited(stop.then((_) => stopped = true));
    await tester.pump();
    setup.stopGate!.complete();
    setup.buildGate!.complete();
    for (var i = 0; i < 20 && !stopped; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(stopped, true);
    await tester.pump();
    expect(container.read(runTimeProvider), isNull);
    expect(setup.listenerTargets, [false]);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox.shrink());
    globalState.lastVpnState = null;
  });

  testWidgets('opt-in SSID observation reaches the Android pause command', (
    tester,
  ) async {
    container.dispose();
    configure(appManager: true);
    final changes = StreamController<List<ConnectivityResult>>.broadcast();
    var permission = true;
    String? ssid = 'SyntheticHome';
    var reads = 0;
    var running = true;
    var revision = 0;
    final pauses = <bool>[];
    when(() => native.preparePauseIntent(any())).thenAnswer((call) async {
      final paused = call.positionalArguments.single as bool;
      pauses.add(paused);
      return snapshot(
        paused: paused,
        running: running,
        phase: paused || !running ? 'stopping' : 'preparing',
        revision: ++revision,
      );
    });
    when(
      () => native.prepareRunIntent(
        running: any(named: 'running'),
        source: any(named: 'source'),
        paused: any(named: 'paused'),
      ),
    ).thenAnswer((call) async {
      running = call.namedArguments[#running] as bool;
      return ++revision;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppStateManager(
          isAndroid: true,
          child: ConnectivityManager(
            connectivityStream: changes.stream,
            readSsid: () async {
              reads++;
              return permission ? ssid : null;
            },
            child: const SizedBox(),
          ),
        ),
      ),
    );
    Future<void> drain() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    changes.add([ConnectivityResult.wifi]);
    await drain();
    expect(reads, 0);
    expect(pauses, isEmpty);
    container.read(excludeSSIDsProvider.notifier).value = ['SyntheticHome'];
    await drain();
    expect(container.read(currentSSIDProvider), 'SyntheticHome');
    expect(container.read(suspendProvider), true);
    expect(pauses, [true]);
    expect(setup.listenerTargets, [false]);

    permission = false;
    changes.add([ConnectivityResult.wifi]);
    await drain();
    expect(container.read(currentSSIDProvider), isNull);
    expect(container.read(suspendProvider), false);
    expect(pauses, [true, false]);
    expect(setup.builds, 1);

    permission = true;
    ssid = null;
    changes.add([ConnectivityResult.wifi]);
    await drain();
    expect(container.read(currentSSIDProvider), isNull);
    expect(pauses, [true, false]);
    ssid = 'SyntheticHome';
    changes.add([ConnectivityResult.wifi]);
    await drain();
    expect(pauses, [true, false, true]);
    var stopped = false;
    unawaited(setup.setRunning(false).then((_) => stopped = true));
    await drain();
    expect(stopped, true);
    ssid = 'OtherSyntheticNetwork';
    changes.add([ConnectivityResult.wifi]);
    await drain();
    expect(pauses, [true, false, true, false]);
    expect(container.read(suspendProvider), false);
    expect(container.read(nativeRequestStateProvider)['intentRunning'], false);
    expect(setup.builds, 1);
    expect(container.read(runTimeProvider), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });
}
