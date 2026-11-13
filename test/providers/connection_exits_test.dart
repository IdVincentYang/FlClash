import 'dart:async';
import 'package:drift/native.dart';
import 'package:fl_clash/database/connection_exits.dart';
import 'package:fl_clash/providers/exit_cache.dart';

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

class _Disk extends ExitCacheDatabase {
  _Disk() : super(NativeDatabase.memory());
  Completer<void>? readGate;
  bool failRead = false;
  @override
  Future<IpInfo?> latest(String identity, DateTime now) async {
    await readGate?.future;
    if (failRead) throw StateError('unavailable');
    return super.latest(identity, now);
  }
}

class _Config extends TestConfigState {
  _Config() : super(const ConfigFact(inputId: 'input-a'));
  void replace(String input) =>
      state = ConfigViewState(fact: ConfigFact(inputId: input));
}

class _Cache extends ConnectionExits {
  _Cache(this.client);
  final Request client;
  Duration time = Duration.zero;
  @override
  Request get requestClient => client;
  @override
  Duration get elapsed => time;
  @override
  DateTime get utcNow => DateTime.utc(2026, 11, 13).add(time);
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
        Proxy(name: 'A', type: 'ss', cacheIdentity: 'id-a'),
        Proxy(name: 'B', type: 'ss', cacheIdentity: 'id-b'),
        Proxy(name: 'C', type: 'ss', cacheIdentity: 'id-c'),
      ],
    ),
  ];
}

const a = ConnectionExitTarget('A', '8.8.8.8', 'input-a', 'id-a');
const b = ConnectionExitTarget('B', '8.8.8.8', 'input-a', 'id-b');
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
      entryIp: '8.8.8.8',
      cacheIdentity: 'id-${node.toLowerCase()}',
      error: error,
    );

void main() {
  setUpAll(() => registerFallbackValue(const OutboundIpParams(timeout: 0)));
  late _Core core;
  late _Cache cache;
  late IpTestRequest client;
  late ProviderContainer container;
  late _Disk disk;
  final calls = <String>[];

  setUp(() async {
    calls.clear();
    core = _Core();
    client = IpTestRequest(
      IpTestAdapter((_, _) async => ResponseBody.fromString('', 500)),
    );
    cache = _Cache(client);
    disk = _Disk();
    when(() => core.outboundIp(any())).thenAnswer((call) async {
      final node =
          (call.positionalArguments.single as OutboundIpParams).proxyName;
      calls.add(node);
      return answer(node);
    });
    container = ProviderContainer(
      overrides: [
        exitCacheDatabaseProvider.overrideWithValue(disk),
        connectionExitsProvider.overrideWith(() => cache),
        routeTrackerProvider.overrideWith(_Route.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        configStateProvider.overrideWith(_Config.new),
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
    await disk.close();
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
      cache.time = const Duration(days: 6, hours: 23, minutes: 59, seconds: 59);
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      cache.unwatch(a, automatic: true);
      cache.time = const Duration(days: 7);
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
    'disk reads finish before scheduling an automatic external request',
    () async {
      await disk.save(
        a.identity,
        a.entry,
        IpInfo(ip: '1.1.1.1', countryCode: 'HK', checkedAt: cache.utcNow),
      );
      disk.readGate = Completer<void>();
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(calls, isEmpty);
      disk.readGate!.complete();
      await pumpEventQueue();
      expect(calls, isEmpty);
      expect(
        container.read(connectionExitsProvider)[a]?.value?.countryCode,
        'HK',
      );
    },
  );

  test(
    'a renamed node in another subscription reuses the global file record',
    () async {
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      cache.unwatch(a, automatic: true);
      (container.read(configStateProvider.notifier) as _Config).replace(
        'input-b',
      );
      container.read(groupsProvider.notifier).value = const [
        Group(
          name: 'Different rules',
          type: GroupType.Selector,
          all: [Proxy(name: 'Renamed', type: 'ss', cacheIdentity: 'id-a')],
        ),
      ];
      const renamed = ConnectionExitTarget(
        'Renamed',
        '8.8.8.8',
        'input-b',
        'id-a',
      );
      cache.watch(renamed, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(
        container.read(connectionExitsProvider)[renamed]?.value?.countryCode,
        'HK',
      );
    },
  );

  test(
    'a measurement is saved under its actual entry, never the old entry',
    () async {
      when(() => core.outboundIp(any())).thenAnswer((_) async {
        calls.add('A');
        return answer('A').copyWith(entryIp: '9.9.9.9');
      });
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider)[a]?.value, isNotNull);
      expect(
        (await disk.select(disk.exitMeasurements).get()).single.entryIp,
        '9.9.9.9',
      );
      expect(await disk.latest(a.identity, cache.utcNow), isNotNull);
      const actual = ConnectionExitTarget('A', '9.9.9.9', 'input-a', 'id-a');
      cache.watch(actual, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(container.read(connectionExitsProvider)[actual]?.value, isNotNull);
    },
  );

  test(
    'a failed forced refresh keeps the old flag and SQLite result',
    () async {
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      final before = container.read(connectionExitsProvider)[a]!.value;
      cache.time = const Duration(seconds: 6);
      when(
        () => core.outboundIp(any()),
      ).thenAnswer((_) async => answer('A', error: 'timeout'));
      cache.refresh(a);
      await pumpEventQueue();
      expect(
        container.read(connectionExitsProvider)[a]?.phase,
        ProbePhase.failed,
      );
      expect(container.read(connectionExitsProvider)[a]?.value, before);
      expect(cache.isExpired(a), false);
      expect(await disk.latest(a.identity, cache.utcNow), before);
    },
  );

  test('a broken cache read does not block a scoped measurement', () async {
    disk.failRead = true;
    cache.watch(a, automatic: true);
    await pumpEventQueue();
    expect(calls, ['A']);
    expect(container.read(connectionExitsProvider)[a]?.value, isNotNull);
  });

  test(
    'different hosts and entries for the same node share one check',
    () async {
      const other = ConnectionExitTarget('A', '9.9.9.9', 'input-a', 'id-a');
      final gate = Completer<OutboundIpResult?>();
      when(() => core.outboundIp(any())).thenAnswer((_) {
        calls.add('A');
        return gate.future;
      });
      cache.watch(a, automatic: true);
      cache.watch(other, automatic: true);
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(cache.refresh(other), ExitRefreshResult.coalesced);
      gate.complete(answer('A').copyWith(entryIp: '1.0.0.1'));
      await pumpEventQueue();
      expect(
        container.read(connectionExitsProvider)[a]?.value?.countryCode,
        'HK',
      );
      expect(
        container.read(connectionExitsProvider)[other]?.value?.countryCode,
        'HK',
      );
      expect(
        (await disk.select(disk.exitMeasurements).get()).single.entryIp,
        '1.0.0.1',
      );
      cache.time = const Duration(seconds: 2);
      expect(cache.refresh(other), ExitRefreshResult.throttled);
    },
  );

  test(
    'manual clicks on different entries coalesce before the queue starts',
    () async {
      const other = ConnectionExitTarget('A', '9.9.9.9', 'input-a', 'id-a');
      cache.watch(a, automatic: false);
      cache.watch(other, automatic: false);
      await pumpEventQueue();
      expect(cache.refresh(a), ExitRefreshResult.accepted);
      expect(cache.refresh(other), ExitRefreshResult.coalesced);
      await pumpEventQueue();
      expect(calls, ['A']);
      expect(
        container.read(connectionExitsProvider)[other]?.value?.countryCode,
        'HK',
      );
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
    'route changes retain successful measurements without a new check',
    () async {
      cache.watch(a, automatic: true);
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider)[a]?.value, isNotNull);
      cache.time = const Duration(seconds: 2);
      (container.read(routeTrackerProvider.notifier) as _Route).replace(
        route.copyWith(hostEpoch: 2, live: false),
      );
      await pumpEventQueue();
      expect(container.read(connectionExitsProvider)[a]?.value, isNotNull);
      expect(await disk.latest(a.identity, cache.utcNow), isNotNull);
      expect(calls, ['A']);
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
          activityConnection(
            'current',
            exit: 'A',
          ).copyWith(metadata: const Metadata(remoteDestination: '8.8.8.8')),
          'input-a',
          identity: 'id-a',
        ),
        a,
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
