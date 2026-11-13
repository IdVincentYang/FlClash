import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/connection_exits.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/application_activity.dart';
import '../helpers/ip_lookup_request.dart';
import '../helpers/test_config_state.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Cache extends ConnectionExits {
  _Cache(this.client);
  final Request client;
  Duration time = Duration.zero;
  @override
  Request get requestClient => client;
  @override
  Duration get elapsed => time;
}

class _Route extends RouteTracker {
  @override
  RouteState build() => route;
  @override
  void attach() {}
  @override
  void detach() {}
  void replace(RouteState next) => state = next;
}

class _Groups extends Groups {
  @override
  List<Group> build() => const [
    Group(
      name: 'Main',
      type: GroupType.Selector,
      all: [
        Proxy(name: 'A', type: 'ss'),
        Proxy(name: 'B', type: 'ss'),
        Proxy(name: 'C', type: 'ss'),
      ],
    ),
  ];
}

const a = ConnectionExitTarget('A', '8.8.8.8', 'input-a');
const b = ConnectionExitTarget('B', '8.8.8.8', 'input-a');
const route = RouteState(
  coreEpoch: 1,
  picksVersion: 1,
  hostEpoch: 1,
  proxied: true,
  synced: true,
  live: true,
);
OutboundIpResult answer(String node, {int epoch = 1, String? error}) =>
    OutboundIpResult(
      url: 'https://www.cloudflare.com/cdn-cgi/trace',
      body: 'ip=1.1.1.1\nloc=HK\n',
      chains: [node],
      coreEpoch: epoch,
      picksVersion: 1,
      error: error,
    );

void main() {
  setUpAll(() => registerFallbackValue(const OutboundIpParams(timeout: 0)));
  late _Core core;
  late _Cache cache;
  late IpTestRequest client;
  late ProviderContainer container;
  final calls = <String>[];

  setUp(() async {
    calls.clear();
    core = _Core();
    client = IpTestRequest(
      IpTestAdapter((_, _) async => ResponseBody.fromString('', 500)),
    );
    cache = _Cache(client);
    when(() => core.outboundIp(any())).thenAnswer((call) async {
      final node =
          (call.positionalArguments.single as OutboundIpParams).proxyName;
      calls.add(node);
      return answer(node);
    });
    container = ProviderContainer(
      overrides: [
        connectionExitsProvider.overrideWith(() => cache),
        routeTrackerProvider.overrideWith(_Route.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        configStateProvider.overrideWith(
          () => TestConfigState(const ConfigFact(inputId: 'input-a')),
        ),
        initProvider.overrideWithBuild((_, _) => true),
        appVisibleProvider.overrideWithBuild((_, _) => true),
        groupsProvider.overrideWith(_Groups.new),
      ],
    );
    container.listen(connectionExitsProvider, (_, _) {});
    container.listen(groupsProvider, (_, _) {});
    client.attach(container);
    await client.ready();
  });
  tearDown(() async {
    await client.detach();
    container.dispose();
  });

  test(
    'deduplicates visible apps and reuses the same node and entry cache',
    () async {
      cache.watch(a, automatic: true);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(client.triggers, [true]);
      expect(
        container.read(connectionExitsProvider)[a]?.value?.countryCode,
        'HK',
      );
      cache.unwatch(a, automatic: true);
      cache.unwatch(a, automatic: true);
      cache.time = const Duration(minutes: 9);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      cache.unwatch(a, automatic: true);
      cache.time = const Duration(minutes: 11);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A', 'A']);
    },
  );

  test(
    'one entry IP with different node identities does not share an exit',
    () async {
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      cache.time = const Duration(seconds: 2);
      cache.watch(b, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A', 'B']);
      expect(container.read(connectionExitsProvider).keys, containsAll([a, b]));
    },
  );

  test(
    'inactive watch does nothing; manual refresh bypasses cache and coalesces clicks',
    () async {
      cache.watch(a, automatic: false);
      await pumpEventQueue();
      expect(calls, isEmpty);
      cache.refresh(a);
      cache.refresh(a);
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(client.triggers, [false]);
      cache.refresh(a);
      await pumpEventQueue();
      expect(calls, ['A']);
      cache.time = const Duration(seconds: 6);
      cache.refresh(a);
      cache.refresh(a);
      await pumpEventQueue();
      expect(calls, ['A', 'A']);
    },
  );

  test(
    'serializes different nodes and removes offscreen queued work',
    () async {
      final gate = Completer<OutboundIpResult?>();
      when(() => core.outboundIp(any())).thenAnswer((call) async {
        final node =
            (call.positionalArguments.single as OutboundIpParams).proxyName;
        calls.add(node);
        return node == 'A' ? gate.future : answer(node);
      });
      cache.watch(a, automatic: true);
      cache.watch(b, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      cache.unwatch(b, automatic: true);
      cache.time = const Duration(seconds: 2);
      gate.complete(answer('A'));
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(container.read(connectionExitsProvider).containsKey(b), false);
    },
  );

  test(
    'failure backoff survives scrolling and explicit retry remains possible',
    () async {
      when(() => core.outboundIp(any())).thenAnswer((_) async {
        calls.add('A');
        return answer('A', error: 'timeout');
      });
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(
        container.read(connectionExitsProvider)[a]?.phase,
        ProbePhase.failed,
      );
      cache.unwatch(a, automatic: true);
      cache.time = const Duration(seconds: 30);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      cache.refresh(a);
      await pumpEventQueue();
      expect(calls, ['A', 'A']);
    },
  );

  test(
    'backgrounding cancels work and a late answer cannot populate cache',
    () async {
      final gate = Completer<OutboundIpResult?>();
      when(() => core.outboundIp(any())).thenAnswer((_) => gate.future);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      container.read(appVisibleProvider.notifier).value = false;
      gate.complete(answer('A'));
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider), isEmpty);
    },
  );

  test(
    'route changes clear cached measurements and do not accept old epochs',
    () async {
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider)[a]?.value, isNotNull);
      cache.time = const Duration(seconds: 2);
      (container.read(routeTrackerProvider.notifier) as _Route).replace(
        route.copyWith(hostEpoch: 2, live: false),
      );
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider), isEmpty);
    },
  );

  test('unwatching the last active subscriber cancels the run', () async {
    final gate = Completer<OutboundIpResult?>();
    when(() => core.outboundIp(any())).thenAnswer((_) => gate.future);
    cache.watch(a, automatic: true);
    await pumpEventQueue();
    cache.unwatch(a, automatic: true);
    gate.complete(answer('A'));
    await pumpEventQueue();
    expect(container.read(connectionExitsProvider), isEmpty);
  });

  test(
    'a reply from a different node or Core is never shown as this exit',
    () async {
      when(() => core.outboundIp(any())).thenAnswer((_) async => answer('B'));
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider)[a]?.value, isNull);
      expect(
        container.read(connectionExitsProvider)[a]?.phase,
        ProbePhase.failed,
      );
    },
  );

  test(
    'cancelling a forced refresh retains the previous unexpired shared result',
    () async {
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      final original = container.read(connectionExitsProvider)[a]?.value;
      final gate = Completer<OutboundIpResult?>();
      when(() => core.outboundIp(any())).thenAnswer((_) => gate.future);
      cache.time = const Duration(seconds: 6);
      cache.refresh(a);
      await pumpEventQueue();
      cache.unwatch(a, automatic: true);
      gate.complete(answer('A'));
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider)[a]?.value, original);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
    },
  );

  test(
    'a removed node cannot hold the queue or publish a late measurement',
    () async {
      final gate = Completer<OutboundIpResult?>();
      when(() => core.outboundIp(any())).thenAnswer((_) => gate.future);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      container.read(groupsProvider.notifier).value = [];
      await pumpEventQueue();
      gate.complete(answer('A'));
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider), isEmpty);
    },
  );

  test(
    'a connection from another accepted configuration cannot trigger a node check',
    () {
      expect(
        connectionExitTarget(
          activityConnection('current', exit: 'A'),
          'input-a',
        ),
        const ConnectionExitTarget('A', '', 'input-a'),
      );
      expect(
        connectionExitTarget(activityConnection('old', exit: 'A'), 'input-b'),
        isNull,
      );
      expect(
        connectionExitTarget(
          activityConnection('direct', exit: 'DIRECT'),
          'input-a',
        ),
        isNull,
      );
    },
  );
}
