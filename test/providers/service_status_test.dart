import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _ClockedServiceStatus extends ServiceStatus {
  _ClockedServiceStatus(this.elapsed);
  final Duration Function() elapsed;
  @override
  Duration get monotonicElapsed => elapsed();
}

ServiceCheckItem _item(String name, {String status = 'available'}) =>
    ServiceCheckItem(
      name: name,
      status: status,
      delay: 12,
      chains: const ['HK-01'],
      checkedAt: 1700000000000,
      coreEpoch: 1,
      picksVersion: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(const ServiceCheckParams(timeout: 0)));

  late _MockCore core;
  late List<ServiceCheckParams> sweeps;
  var elapsed = Duration.zero;
  // Request keeps a process-wide serial future whose originating zone survives each case.
  final _ = FakeAsync();

  setUp(() {
    core = _MockCore();
    sweeps = [];
    elapsed = Duration.zero;
    when(() => core.serviceCheck(any())).thenAnswer((invocation) async {
      final params =
          invocation.positionalArguments.single as ServiceCheckParams;
      sweeps.add(params);
      return [
        for (final name in params.names)
          _item(name).copyWith(
            purpose: params.purpose,
            status: params.purpose == 'advanced' ? 'observed' : 'available',
          ),
      ];
    });
  });

  ProviderContainer container({
    bool proxied = true,
    bool synced = true,
    Duration Function()? clock,
    bool realRoute = false,
  }) {
    final scope = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild((_, _) => const AppSettingProps()),
        serviceStatusProvider.overrideWith(
          () => _ClockedServiceStatus(clock ?? () => elapsed),
        ),
        if (realRoute) initProvider.overrideWithBuild((_, _) => true),
        if (realRoute)
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        if (!realRoute)
          routeTrackerProvider.overrideWithBuild(
            (_, _) => RouteState(
              coreEpoch: 1,
              picksVersion: 1,
              hostEpoch: 1,
              proxied: proxied,
              synced: synced,
              live: synced,
            ),
          ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(scope.dispose);
    scope.listen(serviceStatusProvider, (_, _) {});
    return scope;
  }

  ServiceStatus notifierOf(ProviderContainer scope) =>
      scope.read(serviceStatusProvider.notifier);

  RoutedProbeState<ServiceProbeKey, ServiceCheck> stateOf(
    ProviderContainer scope,
  ) => scope.read(serviceStatusProvider);

  test(
    'checks each watched target through the Core route on its own',
    () async {
      final scope = container();

      notifierOf(scope)
        ..watch(ServiceTarget.youtube.basic)
        ..watch(ServiceTarget.claude.basic);
      await pumpEventQueue();

      expect(sweeps.map((sweep) => sweep.names), [
        ['youtube'],
        ['claude'],
      ]);
      expect(sweeps.first.proxyName, isEmpty);
      expect(sweeps.first.timeout, probeTimeoutDuration.inMilliseconds);
      final state = stateOf(scope);
      expect(
        state.entryOf(ServiceTarget.youtube.basic).phase,
        ProbePhase.fresh,
      );
      expect(state.valueOf(ServiceTarget.youtube.basic)?.node, 'HK-01');
      expect(state.valueOf(ServiceTarget.claude.basic)?.delay, 12);
    },
  );

  test('shows each answer as it lands', () async {
    final scope = container();
    final gates = <String, Completer<List<ServiceCheckItem>>>{};
    when(() => core.serviceCheck(any())).thenAnswer((invocation) {
      final params =
          invocation.positionalArguments.single as ServiceCheckParams;
      return (gates[params.names.single] = Completer()).future;
    });

    notifierOf(
      scope,
    ).refresh(ServiceTarget.values.map((target) => target.basic));
    await pumpEventQueue();
    expect(gates.keys, [for (final target in ServiceTarget.values) target.id]);

    gates['google']!.complete([_item('google')]);
    await pumpEventQueue();
    final state = stateOf(scope);
    expect(state.entryOf(ServiceTarget.google.basic).phase, ProbePhase.fresh);
    expect(state.isLoading(ServiceTarget.github.basic), isTrue);
  });

  test(
    'a route change asks the Core again at once, not behind the stale checks',
    () async {
      final scope = container();
      when(() => core.serviceCheck(any())).thenAnswer((invocation) {
        sweeps.add(invocation.positionalArguments.single as ServiceCheckParams);
        return Completer<List<ServiceCheckItem>>().future;
      });
      final notifier = notifierOf(scope);
      for (final target in ServiceTarget.values) {
        notifier.watch(target.basic);
      }
      await pumpEventQueue();
      expect(sweeps, hasLength(ServiceTarget.values.length));

      elapsed += const Duration(seconds: 30);
      scope.read(routeTrackerProvider.notifier).bumpHostEpoch();
      await pumpEventQueue();

      expect(sweeps.skip(ServiceTarget.values.length).map((s) => s.names), [
        for (final target in ServiceTarget.values) [target.id],
      ]);
    },
  );

  test('checks through the direct outbound while the proxy is off', () async {
    final scope = container(proxied: false);

    notifierOf(scope).watch(ServiceTarget.bilibili.basic);
    await pumpEventQueue();

    expect(sweeps.single.proxyName, directOutbound);
    expect(sweeps.single.names, ['bilibili']);
  });

  test('does not ask the Core before the route has been read', () async {
    final scope = container(synced: false);

    notifierOf(scope).watch(ServiceTarget.bilibili.basic);
    await pumpEventQueue();

    verifyNever(() => core.serviceCheck(any()));
    expect(
      stateOf(scope).entryOf(ServiceTarget.bilibili.basic).phase,
      ProbePhase.queued,
    );
  });

  test('marks a target loading while its check is in flight', () async {
    final scope = container();
    final gate = Completer<List<ServiceCheckItem>>();
    when(() => core.serviceCheck(any())).thenAnswer((_) => gate.future);

    notifierOf(scope).watch(ServiceTarget.youtube.basic);
    await pumpEventQueue();
    expect(stateOf(scope).isLoading(ServiceTarget.youtube.basic), isTrue);

    gate.complete([_item('youtube')]);
    await pumpEventQueue();
    expect(stateOf(scope).isLoading(ServiceTarget.youtube.basic), isFalse);
  });

  test(
    'will not queue a second check for a target already in flight',
    () async {
      final scope = container();
      final gate = Completer<List<ServiceCheckItem>>();
      when(() => core.serviceCheck(any())).thenAnswer((_) => gate.future);
      final notifier = notifierOf(scope);

      notifier.watch(ServiceTarget.youtube.basic);
      await pumpEventQueue();
      notifier
        ..watch(ServiceTarget.youtube.basic)
        ..refresh([ServiceTarget.youtube.basic]);
      await pumpEventQueue();
      gate.complete([_item('youtube')]);
      await pumpEventQueue();

      verify(() => core.serviceCheck(any())).called(1);
    },
  );

  test('a refresh checks the named targets, watched or not', () async {
    final scope = container();
    final notifier = notifierOf(scope);
    notifier.watch(ServiceTarget.youtube.basic);
    await pumpEventQueue();

    elapsed += const Duration(seconds: 30);
    notifier.refresh([ServiceTarget.youtube.basic, ServiceTarget.claude.basic]);
    await pumpEventQueue();

    expect(sweeps.map((sweep) => sweep.names), [
      ['youtube'],
      ['youtube'],
      ['claude'],
    ]);
    expect(stateOf(scope).valueOf(ServiceTarget.claude.basic), isNotNull);
  });

  test(
    'a timeout is shown as a status and retried once the app resumes',
    () async {
      when(() => core.serviceCheck(any())).thenAnswer((invocation) async {
        final params =
            invocation.positionalArguments.single as ServiceCheckParams;
        sweeps.add(params);
        return [
          for (final name in params.names) _item(name, status: 'timeout'),
        ];
      });
      final scope = container();
      notifierOf(scope).watch(ServiceTarget.youtube.basic);
      await pumpEventQueue();

      final entry = stateOf(scope).entryOf(ServiceTarget.youtube.basic);
      expect(entry.phase, ProbePhase.failed);
      expect(entry.value?.status, ServiceProbeStatus.timeout);

      elapsed += const Duration(seconds: 30);
      scope.read(routeTrackerProvider.notifier).markResumed();
      await pumpEventQueue();

      expect(sweeps, hasLength(2));
    },
  );

  test('drops results once the route has changed under them', () async {
    final scope = container();
    notifierOf(scope).watch(ServiceTarget.youtube.basic);
    await pumpEventQueue();
    expect(stateOf(scope).valueOf(ServiceTarget.youtube.basic), isNotNull);

    elapsed += const Duration(seconds: 30);
    scope.read(routeTrackerProvider.notifier).bumpHostEpoch();

    expect(stateOf(scope).valueOf(ServiceTarget.youtube.basic), isNull);
    expect(stateOf(scope).isLoading(ServiceTarget.youtube.basic), isTrue);
    await pumpEventQueue();
    expect(sweeps, hasLength(2));
    expect(stateOf(scope).valueOf(ServiceTarget.youtube.basic), isNotNull);
  });

  test(
    'an answer that arrives after the route changed is asked again',
    () async {
      final scope = container();
      final gate = Completer<List<ServiceCheckItem>>();
      var first = true;
      when(() => core.serviceCheck(any())).thenAnswer((invocation) {
        final params =
            invocation.positionalArguments.single as ServiceCheckParams;
        sweeps.add(params);
        if (first) {
          first = false;
          return gate.future;
        }
        return Future.value([for (final name in params.names) _item(name)]);
      });
      notifierOf(scope).watch(ServiceTarget.youtube.basic);
      await pumpEventQueue();

      elapsed += const Duration(seconds: 30);
      scope.read(routeTrackerProvider.notifier).bumpHostEpoch();
      gate.complete([_item('youtube')]);
      await pumpEventQueue();

      expect(sweeps, hasLength(2));
      expect(
        stateOf(scope).entryOf(ServiceTarget.youtube.basic).phase,
        ProbePhase.fresh,
      );
    },
  );

  test(
    'enabled targets follow the saved order and skip turned-off services',
    () {
      final scope = container();
      scope.read(appSettingProvider.notifier).value = const AppSettingProps(
        serviceOrder: ['claude', 'google'],
        disabledServices: ['github', 'bilibili'],
      );

      expect(scope.read(enabledServiceTargetsProvider).map((t) => t.id), [
        'claude',
        'google',
        for (final target in ServiceTarget.values)
          if (!['claude', 'google', 'github', 'bilibili'].contains(target.id))
            target.id,
      ]);
    },
  );

  for (final _ in [false, true]) {}

  for (final _ in [false, true]) {}

  for (final _ in [false, true]) {}
}
