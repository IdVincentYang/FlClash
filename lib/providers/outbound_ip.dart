import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  @override
  RoutedProbeState<String, IpInfo> build() {
    ref.listen(appSettingProvider.select((s) => s.automaticOutboundIp), (_, _) {
      if (!isManualProbe(routedOutbound) &&
          state.entryOf(routedOutbound).isLoading) {
        cancel([routedOutbound]);
      }
      reconcileEligibility();
    });
    ref.listen(currentPageLabelProvider, (_, _) => reconcileEligibility());
    ref.listen(
      routeTrackerProvider.select((s) => (s.live, s.proxied)),
      (_, _) => reconcileEligibility(),
    );
    return buildProbe();
  }

  @override
  bool get waitsForRoute => false;

  @override
  bool get sharedInterval => true;

  @override
  ProbeSchedule get probeSchedule => const ProbeSchedule(
    minimumInterval: Duration(seconds: 30),
    maxAge: Duration(minutes: 5),
  );

  @override
  bool isEligible(String target) =>
      ref.read(currentPageLabelProvider) == PageLabel.dashboard;

  @override
  bool allowsAutomatic(String target) =>
      ref.read(appSettingProvider).automaticOutboundIp &&
      ref.read(routeTrackerProvider).proxied;

  @override
  bool cancelManualOnUnwatch(String target) => true;

  @override
  void cancelProbe(String target) =>
      requestClient.cancelKey('outboundIp:$target');

  Request get requestClient => request;

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final valid = captureProbeGuard(target);
    final automatic = !isManualProbe(target);
    bool current() => valid() && (!automatic || allowsAutomatic(target));
    final proxy = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    try {
      final result = await withIpSession(
        client: requestClient,
        key: 'outboundIp:$target',
        url: outboundIpUrl,
        timeout: const Duration(seconds: 6),
        automatic: automatic,
        explicitTarget: proxy,
        current: current,
        action: (session, remaining) => lookupOutboundIp(
          ref.read(coreHandlerProvider),
          proxy,
          timeout: remaining,
        ),
      );
      final value = parseOutboundIp(result);
      return {
        target: ProbeAnswer(
          value: value,
          reason: value == null ? result?.error ?? 'invalid-response' : null,
          coreEpoch: result?.coreEpoch,
          picksVersion: result?.picksVersion,
          chains: result?.chains ?? const [],
        ),
      };
    } on IpLookupException catch (error) {
      return {target: ProbeAnswer(reason: error.code)};
    }
  }
}
