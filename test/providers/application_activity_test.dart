import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/request_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/application_activity.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Config extends ConfigState {
  @override
  ConfigViewState build() => const ConfigViewState(
    fact: ConfigFact(
      runtimeEpoch: 'runtime-a',
      phase: 'ready',
      businessActive: true,
    ),
  );
}

class _Native extends NativeRequestState {
  @override
  Map<String, Object?> build() => const {
    'phase': 'started',
    'intentRunning': true,
    'paused': false,
    'serviceId': 'vpn-a',
    'protectPhase': 'ready',
    'protectGeneration': 1,
  };
  void stop() => state = const {
    'phase': 'stopped',
    'intentRunning': false,
    'paused': false,
    'serviceId': '',
    'protectPhase': 'none',
  };
}

class _SnapshotWire extends CoreHandlerInterface {
  _SnapshotWire(this.data);
  final Map<String, dynamic>? data;
  @override
  Future<T?> invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async => data as T?;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyCatalogue extends SystemAction {
  int reads = 0;
  @override
  void build() {}
  @override
  Future<List<Package>> getPackages() async {
    reads++;
    await Future<void>.delayed(Duration.zero);
    ref.read(packagesProvider.notifier).value = [];
    return [];
  }

  @override
  Future<bool> isInstalledAppsPermissionGranted() async => false;
}

void main() {
  late ProviderContainer container;
  late _Core core;

  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  setUp(() {
    core = _Core();
    when(() => core.getConnections()).thenAnswer((_) async => []);
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        configStateProvider.overrideWith(_Config.new),
        nativeRequestStateProvider.overrideWith(_Native.new),
      ],
    );
  });
  tearDown(() => container.dispose());

  void event(TrackerInfo info) => coreEventManager.sendEvent(
    CoreEvent(type: CoreEventType.request, data: jsonDecode(jsonEncode(info))),
  );

  test(
    'observation does not read native state before bootstrap completes',
    () async {
      final scoped = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          configStateProvider.overrideWith(_Config.new),
          nativeRequestStateProvider.overrideWith(_Native.new),
        ],
      );
      addTearDown(scoped.dispose);
      scoped.listen(applicationActivityProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(scoped.exists(configStateProvider), false);
      expect(scoped.exists(nativeRequestStateProvider), false);
      verifyNever(() => core.getConnections());
      scoped.read(initProvider.notifier).value = true;
      await Future<void>.delayed(Duration.zero);
      expect(scoped.read(applicationActivityProvider).observing, true);
      verify(() => core.getConnections()).called(1);
    },
  );

  test(
    'an empty catalogue completes once and later shared package updates are reused',
    () async {
      final action = _EmptyCatalogue();
      final scoped = ProviderContainer(
        overrides: [systemActionProvider.overrideWith(() => action)],
      );
      addTearDown(scoped.dispose);
      final result = await scoped
          .read(applicationCatalogueProvider.future)
          .timeout(const Duration(seconds: 1));
      expect(result.accessible, false);
      expect(result.packages, isEmpty);
      expect(action.reads, 1);
      scoped.read(packagesProvider.notifier).value = [
        const Package(
          packageName: 'test.app',
          label: 'Test',
          system: false,
          internet: true,
          lastUpdateTime: 0,
        ),
      ];
      final cached = await scoped.read(applicationCatalogueProvider.future);
      expect(cached.packages.single.label, 'Test');
      expect(action.reads, 1);
    },
  );

  test(
    'invalid and partial wire snapshots fail instead of claiming no connections',
    () async {
      for (final raw in [
        null,
        <String, dynamic>{},
        <String, dynamic>{'connections': 'unavailable'},
        <String, dynamic>{
          'connections': [activityConnection('valid').toJson(), null],
        },
      ]) {
        await expectLater(
          _SnapshotWire(raw).getConnections(),
          throwsA(anything),
        );
      }
      expect(
        await _SnapshotWire({'connections': []}).getConnections(),
        isEmpty,
      );
    },
  );

  test('application observation does not depend on an activity page', () async {
    container.listen(applicationActivityProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    event(activityConnection('short'));
    event(activityConnection('short'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      container
          .read(applicationActivityProvider)
          .apps
          .single
          .totals
          .connectionCount,
      1,
    );
    await container.read(applicationActivityProvider.notifier).refresh();
    expect(
      container
          .read(applicationActivityProvider)
          .apps
          .single
          .totals
          .activeCount,
      0,
    );
    verifyNever(() => core.startListener());
    verifyNever(() => core.sourceAcceptance(any()));
    container.dispose();
  });

  test(
    'snapshot errors retain history and retries recover active state',
    () async {
      final info = activityConnection('live');
      when(() => core.getConnections()).thenAnswer((_) async => [info]);
      container.listen(applicationActivityProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(applicationActivityProvider)
            .apps
            .single
            .totals
            .activeCount,
        1,
      );
      when(() => core.getConnections()).thenThrow(StateError('offline'));
      await container.read(applicationActivityProvider.notifier).refresh();
      expect(container.read(applicationActivityProvider).connections.length, 1);
      expect(container.read(applicationActivityProvider).snapshotFailed, true);
      expect(
        container
            .read(applicationActivityProvider)
            .apps
            .single
            .totals
            .activeCount,
        null,
      );
      when(() => core.getConnections()).thenAnswer((_) async => [info]);
      await container.read(applicationActivityProvider.notifier).refresh();
      expect(
        container
            .read(applicationActivityProvider)
            .apps
            .single
            .totals
            .activeCount,
        1,
      );
      container.dispose();
    },
  );

  test(
    'background receives delivered events and defers polling until resume',
    () async {
      container.listen(applicationActivityProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      clearInteractions(core);
      container.read(appVisibleProvider.notifier).value = false;
      await Future<void>.delayed(Duration.zero);
      event(activityConnection('background'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(container.read(applicationActivityProvider).connections.length, 1);
      expect(container.read(applicationActivityProvider).interrupted, true);
      verifyNever(() => core.getConnections());
      when(
        () => core.getConnections(),
      ).thenAnswer((_) async => [activityConnection('background')]);
      container.read(appVisibleProvider.notifier).value = true;
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(applicationActivityProvider)
            .apps
            .single
            .totals
            .activeCount,
        1,
      );
      container.dispose();
    },
  );

  test('late snapshot after stop cannot erase retained events', () async {
    container.listen(applicationActivityProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    event(activityConnection('retain'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final pending = Completer<List<TrackerInfo>>();
    when(() => core.getConnections()).thenAnswer((_) => pending.future);
    final operation = container
        .read(applicationActivityProvider.notifier)
        .refresh();
    (container.read(nativeRequestStateProvider.notifier) as _Native).stop();
    await Future<void>.delayed(Duration.zero);
    pending.complete([]);
    await operation;
    expect(container.read(applicationActivityProvider).connections.length, 1);
    expect(container.read(applicationActivityProvider).observing, false);
    expect(
      container
          .read(applicationActivityProvider)
          .apps
          .single
          .totals
          .activeCount,
      null,
    );
    container.dispose();
  });

  test(
    'new Core instance rejects old events and in-flight snapshots',
    () async {
      container.listen(applicationActivityProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final pending = Completer<List<TrackerInfo>>();
      when(() => core.getConnections()).thenAnswer((_) => pending.future);
      final operation = container
          .read(applicationActivityProvider.notifier)
          .refresh();
      container
          .read(configStateProvider.notifier)
          .accept(
            const ConfigFact(
              runtimeEpoch: 'runtime-b',
              phase: 'ready',
              businessActive: true,
            ),
            authoritative: true,
          );
      await Future<void>.delayed(Duration.zero);
      event(activityConnection('old'));
      event(activityConnection('new', epoch: 'runtime-b'));
      await Future<void>.delayed(Duration.zero);
      pending.complete([activityConnection('old')]);
      await operation;
      expect(
        container.read(applicationActivityProvider).runtimeEpoch,
        'runtime-b',
      );
      expect(
        container
            .read(applicationActivityProvider)
            .connections
            .map((item) => item.info.id),
        ['new'],
      );
      container.dispose();
    },
  );
}
