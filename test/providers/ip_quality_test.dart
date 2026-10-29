import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ip_lookup_request.dart';

class _Probe extends IpQualityProbe {
  _Probe(this.client);
  final Request client;
  Duration elapsed = Duration.zero;
  @override
  Request get requestClient => client;
  @override
  Duration get monotonicElapsed => elapsed;
}

void main() {
  const ip = '1.1.1.1';
  late IpTestAdapter adapter;
  late IpTestRequest client;
  late ProviderContainer container;
  late _Probe probe;
  Future<void> setup({IpTestAdapter? custom}) async {
    adapter =
        custom ??
        IpTestAdapter(
          (_, _) async => ResponseBody.fromString(
            jsonEncode({
              'status': 'ok',
              ip: {
                'network': {'type': 'Hosting'},
                'detections': {'proxy': false},
              },
            }),
            200,
          ),
        );
    client = IpTestRequest(adapter);
    probe = _Probe(client);
    container = ProviderContainer(
      overrides: [
        ipQualityProbeProvider.overrideWith(() => probe),
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
    addTearDown(() async {
      await client.detach();
      container.dispose();
    });
    client.attach(container);
    await client.ready();
    container.listen(ipQualityProbeProvider, (_, _) {});
  }

  test(
    'opening/reopening and native-state reads do not classify; only explicit actions send',
    () async {
      await setup();
      probe.watch(ip, automatic: false);
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(
        adapter.requests,
        hasLength(1),
        reason: container.read(ipQualityProbeProvider).entryOf(ip).reason,
      );
      expect(client.triggers, [false]);
      expect(
        container.read(ipQualityProbeProvider).valueOf(ip)?.checkedAt,
        isNotNull,
      );
      probe.unwatch(ip, automatic: false);
      await pumpEventQueue();
      probe.watch(ip, automatic: false);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      container
          .read(routeTrackerProvider.notifier)
          .applySnapshot(const RouteSnapshot(coreEpoch: 1, picksVersion: 1));
      probe.elapsed = const Duration(seconds: 30);
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(2));
    },
  );
  test(
    'provider rebuild revokes pending intent and preserves source interval',
    () async {
      await setup();
      probe.watch(ip, automatic: false);
      final release = Completer<void>(), entered = Completer<void>();
      final blocked = dataMutations.run(() {
        entered.complete();
        return release.future;
      });
      await entered.future;
      probe.refresh([ip]);
      await pumpEventQueue();
      container.invalidate(ipQualityProbeProvider);
      await pumpEventQueue();
      release.complete();
      await blocked;
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
      expect(
        container.read(ipQualityProbeProvider).entryOf(ip).phase,
        ProbePhase.empty,
      );
      container
          .read(routeTrackerProvider.notifier)
          .applySnapshot(const RouteSnapshot(coreEpoch: 1, picksVersion: 1));
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
      probe.elapsed = const Duration(seconds: 30);
      await Future<void>.delayed(Duration.zero);
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      probe.unwatch(ip, automatic: false);
    },
  );
  test(
    'closing details in begin queue sends nothing and reopening does not replay',
    () async {
      await setup();
      probe.watch(ip, automatic: false);
      final release = Completer<void>(), entered = Completer<void>();
      final blocked = dataMutations.run(() {
        entered.complete();
        return release.future;
      });
      await entered.future;
      probe.refresh([ip]);
      await pumpEventQueue();
      probe.unwatch(ip, automatic: false);
      release.complete();
      await blocked;
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
      probe.watch(ip, automatic: false);
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'background cancels pending admission without subsequent query',
    () async {
      await setup();
      probe.watch(ip, automatic: false);
      final release = Completer<void>(), entered = Completer<void>();
      final blocked = dataMutations.run(() {
        entered.complete();
        return release.future;
      });
      await entered.future;
      probe.refresh([ip]);
      await pumpEventQueue();
      container.read(appVisibleProvider.notifier).value = false;
      release.complete();
      await blocked;
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
    },
  );
  test('route failure does not classify until a new explicit action', () async {
    await setup();
    probe.watch(ip, automatic: false);
    probe.refresh([ip]);
    await pumpEventQueue();
    expect(adapter.requests, hasLength(1));
    container.read(routeTrackerProvider.notifier).bumpHostEpoch();
    await pumpEventQueue();
    expect(adapter.requests, hasLength(1));
    expect(
      container.read(ipQualityProbeProvider).entryOf(ip).phase,
      ProbePhase.failed,
    );
  });
  test(
    '429 backoff applies across IP targets and does not retry on expiry',
    () async {
      await setup(
        custom: IpTestAdapter(
          (_, _) async => ResponseBody.fromString(
            '',
            429,
            headers: {
              'retry-after': ['120'],
            },
          ),
        ),
      );
      probe.watch(ip, automatic: false);
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      probe.elapsed = const Duration(seconds: 31);
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      probe.watch('8.8.8.8', automatic: false);
      probe.refresh(['8.8.8.8']);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      probe.elapsed = const Duration(seconds: 121);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      probe.refresh([ip]);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(2));
    },
  );
  test(
    'one source interval serializes simultaneous explicit queries for different IPs',
    () async {
      await setup(
        custom: IpTestAdapter(
          (options, _) async => ResponseBody.fromString(
            jsonEncode({
              'status': 'ok',
              options.uri.pathSegments.last: <String, Object?>{},
            }),
            200,
          ),
        ),
      );
      probe.watch(ip, automatic: false);
      probe.watch('8.8.8.8', automatic: false);
      probe.refresh([ip, '8.8.8.8']);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(1));
      expect(
        container.read(ipQualityProbeProvider).entryOf('8.8.8.8').phase,
        ProbePhase.queued,
      );
      probe.elapsed = const Duration(seconds: 30);
      probe.refresh(['8.8.8.8']);
      await pumpEventQueue();
      expect(adapter.requests, hasLength(2));
    },
  );
  for (final status in ['denied', 'error', 'warning']) {
    test(
      'API $status honors source backoff without changing route or receiver',
      () async {
        await setup(
          custom: IpTestAdapter(
            (_, _) async => ResponseBody.fromString(
              jsonEncode({
                'status': status,
                ip: {
                  'network': {'type': 'Wireless'},
                },
              }),
              200,
              headers: {
                'retry-after': ['120'],
              },
            ),
          ),
        );
        probe.watch(ip, automatic: false);
        probe.refresh([ip]);
        await pumpEventQueue();
        expect(adapter.requests, hasLength(1));
        final entry = container.read(ipQualityProbeProvider).entryOf(ip);
        if (status == 'warning') {
          expect(entry.value?.warning, isTrue);
          expect(entry.phase, ProbePhase.fresh);
        } else {
          expect(entry.phase, ProbePhase.failed);
          expect(entry.reason, 'source-$status');
        }
        probe.elapsed = const Duration(seconds: 31);
        probe.refresh([ip]);
        await pumpEventQueue();
        expect(adapter.requests, hasLength(1));
        expect(client.triggers, [false]);
      },
    );
  }
}
