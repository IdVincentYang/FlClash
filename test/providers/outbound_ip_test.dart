import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/ip_lookup_request.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Probe extends OutboundIpProbe {
  _Probe(this.client);
  final Request client;
  Duration elapsed = Duration.zero;
  @override
  Request get requestClient => client;
  @override
  Duration get monotonicElapsed => elapsed;
}

const _route = RouteState(
  coreEpoch: 1,
  picksVersion: 1,
  hostEpoch: 1,
  proxied: true,
  synced: true,
  live: true,
);
const _answer = OutboundIpResult(
  url: 'https://www.cloudflare.com/cdn-cgi/trace',
  body: 'ip=1.1.1.1\nloc=AU\n',
  chains: ['node'],
  coreEpoch: 1,
  picksVersion: 1,
);
void main() {
  setUpAll(() => registerFallbackValue(const OutboundIpParams(timeout: 0)));
  late _Core core;
  late IpTestRequest client;
  late _Probe probe;
  late ProviderContainer container;
  Future<void> setup({bool automatic = false, bool proxied = true}) async {
    core = _Core();
    when(() => core.outboundIp(any())).thenAnswer((_) async => _answer);
    client = IpTestRequest(
      IpTestAdapter((_, _) async => ResponseBody.fromString('', 500)),
    );
    probe = _Probe(client);
    container = ProviderContainer(
      overrides: [
        outboundIpProbeProvider.overrideWith(() => probe),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        routeTrackerProvider.overrideWithBuild(
          (_, _) => _route.copyWith(proxied: proxied),
        ),
        appSettingProvider.overrideWithBuild(
          (_, _) => AppSettingProps(automaticOutboundIp: automatic),
        ),
      ],
    );
    addTearDown(() async {
      await client.detach();
      container.dispose();
    });
    client.attach(container);
    await client.ready();
    container.listen(outboundIpProbeProvider, (_, _) {});
    container.listen(appSettingProvider, (_, _) {});
  }

  test(
    'default watch sends nothing; explicit refresh is manual and has no node alias',
    () async {
      await setup();
      probe.watch(routedOutbound);
      await pumpEventQueue();
      verifyNever(() => core.outboundIp(any()));
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      final params =
          verify(() => core.outboundIp(captureAny())).captured.single
              as OutboundIpParams;
      expect(params.urls, ['https://www.cloudflare.com/cdn-cgi/trace']);
      expect(params.proxyName, '');
      expect(client.triggers, [false]);
      expect(
        container.read(outboundIpProbeProvider).valueOf(routedOutbound)?.ip,
        '1.1.1.1',
      );
      expect(container.read(outboundIpProbeProvider).valueOf('node'), isNull);
    },
  );
  test('idle manual pins DIRECT while idle automatic stays silent', () async {
    await setup(automatic: true, proxied: false);
    probe.watch(routedOutbound);
    await pumpEventQueue();
    verifyNever(() => core.outboundIp(any()));
    probe.refresh([routedOutbound]);
    await pumpEventQueue();
    expect(
      (verify(() => core.outboundIp(captureAny())).captured.single
              as OutboundIpParams)
          .proxyName,
      directOutbound,
    );
    expect(client.triggers, [false]);
  });
  test(
    'opt-in running watch is automatic; disabled setting cancels demand',
    () async {
      await setup(automatic: true);
      probe.watch(routedOutbound);
      await pumpEventQueue();
      verify(() => core.outboundIp(any())).called(1);
      expect(client.triggers, [true]);
      container
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(automaticOutboundIp: false));
      await pumpEventQueue();
      probe.elapsed = const Duration(minutes: 6);
      probe.watch(routedOutbound);
      await pumpEventQueue();
      verifyNever(() => core.outboundIp(any()));
    },
  );
  for (final revoke in ['unwatch', 'page', 'background']) {
    test(
      '$revoke while begin waits prevents the real Core consumer call',
      () async {
        await setup();
        probe.watch(routedOutbound);
        final release = Completer<void>(), entered = Completer<void>();
        final blocked = dataMutations.run(() {
          entered.complete();
          return release.future;
        });
        await entered.future;
        probe.refresh([routedOutbound]);
        await pumpEventQueue();
        if (revoke == 'unwatch') probe.unwatch(routedOutbound);
        if (revoke == 'page') {
          container
              .read(currentPageLabelProvider.notifier)
              .toPage(PageLabel.tools);
        }
        if (revoke == 'background') {
          container.read(appVisibleProvider.notifier).value = false;
        }
        release.complete();
        await blocked;
        await pumpEventQueue();
        verifyNever(() => core.outboundIp(any()));
      },
    );
  }
  test(
    'enabled automatic setting does not retain an unwatched manual begin',
    () async {
      await setup(automatic: true);
      probe.watch(routedOutbound, automatic: false);
      final release = Completer<void>(), entered = Completer<void>();
      final blocked = dataMutations.run(() {
        entered.complete();
        return release.future;
      });
      await entered.future;
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      probe.unwatch(routedOutbound, automatic: false);
      release.complete();
      await blocked;
      await pumpEventQueue();
      verifyNever(() => core.outboundIp(any()));
      expect(
        container
            .read(outboundIpProbeProvider)
            .entryOf(routedOutbound)
            .isLoading,
        isFalse,
      );
    },
  );
  for (final merged in [false, true]) {
    test(
      'removing the card cancels manual work with automatic enabled, merged=$merged',
      () async {
        await setup(automatic: true);
        final answer = Completer<OutboundIpResult?>();
        when(() => core.outboundIp(any())).thenAnswer((_) => answer.future);
        probe.watch(routedOutbound, automatic: merged);
        if (!merged) probe.refresh([routedOutbound]);
        await pumpEventQueue();
        if (merged) probe.refresh([routedOutbound]);
        probe.unwatch(routedOutbound, automatic: merged);
        await pumpEventQueue();
        answer.complete(_answer);
        await pumpEventQueue();
        verify(() => core.outboundIp(any())).called(1);
        expect(
          container.read(outboundIpProbeProvider).valueOf(routedOutbound),
          isNull,
        );
        expect(
          container
              .read(outboundIpProbeProvider)
              .entryOf(routedOutbound)
              .isLoading,
          isFalse,
        );
      },
    );
  }
  test(
    'minimum interval queues another action until enough monotonic time passed',
    () async {
      await setup();
      probe.watch(routedOutbound);
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      verify(() => core.outboundIp(any())).called(1);
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      verifyNever(() => core.outboundIp(any()));
      expect(
        container.read(outboundIpProbeProvider).entryOf(routedOutbound).phase,
        ProbePhase.queued,
      );
      probe.elapsed = const Duration(seconds: 30);
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      verify(() => core.outboundIp(any())).called(1);
    },
  );
  test(
    'late result after route mutation is discarded without automatic replay',
    () async {
      await setup();
      final answer = Completer<OutboundIpResult?>();
      when(() => core.outboundIp(any())).thenAnswer((_) => answer.future);
      probe.watch(routedOutbound);
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      container.read(routeTrackerProvider.notifier).bumpHostEpoch();
      answer.complete(_answer);
      await pumpEventQueue();
      expect(
        container.read(outboundIpProbeProvider).valueOf(routedOutbound),
        isNull,
      );
      verify(() => core.outboundIp(any())).called(1);
    },
  );
  for (final automatic in [false, true]) {
    test(
      'TTL expiry with automatic=$automatic respects the selected purpose',
      () async {
        await setup(automatic: automatic);
        probe.watch(routedOutbound);
        if (!automatic) probe.refresh([routedOutbound]);
        await pumpEventQueue();
        verify(() => core.outboundIp(any())).called(1);
        probe.elapsed = const Duration(minutes: 6);
        probe.watch(routedOutbound);
        await pumpEventQueue();
        if (automatic) {
          verify(() => core.outboundIp(any())).called(1);
        } else {
          verifyNever(() => core.outboundIp(any()));
          expect(
            container
                .read(outboundIpProbeProvider)
                .entryOf(routedOutbound)
                .expired,
            isTrue,
          );
        }
      },
    );
  }
  test(
    'unavailable route fails the manual intent instead of replaying on recovery',
    () async {
      await setup();
      probe.watch(routedOutbound);
      container.read(routeTrackerProvider.notifier).detach();
      await pumpEventQueue();
      probe.refresh([routedOutbound]);
      await pumpEventQueue();
      verifyNever(() => core.outboundIp(any()));
      expect(
        container.read(outboundIpProbeProvider).entryOf(routedOutbound).reason,
        'route-unavailable',
      );
      container
          .read(routeTrackerProvider.notifier)
          .applySnapshot(const RouteSnapshot(coreEpoch: 1, picksVersion: 1));
      await pumpEventQueue();
      verifyNever(() => core.outboundIp(any()));
    },
  );
}
