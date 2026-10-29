import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/ip_quality.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/enum/enum.dart';

import 'app.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/ip_quality.g.dart';

@Riverpod(keepAlive: true)
class IpQualityProbe extends _$IpQualityProbe
    with RoutedProbe<String, IpQuality> {
  @override
  RoutedProbeState<String, IpQuality> build() {
    ref.listen(currentPageLabelProvider, (_, _) => reconcileEligibility());
    return buildProbe();
  }

  @override
  bool isEligible(String target) =>
      ref.read(currentPageLabelProvider) == PageLabel.dashboard;

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
  bool allowsAutomatic(String target) => false;

  @override
  void cancelProbe(String target) =>
      requestClient.cancelKey('ipQuality:$target');

  Request get requestClient => request;

  Duration _retryNotBefore = Duration.zero;

  @override
  Future<Map<String, ProbeAnswer<IpQuality>>> probe(
    String target,
    RouteState route,
  ) async {
    if (monotonicElapsed < _retryNotBefore) {
      return {target: const ProbeAnswer(reason: 'rate-limited')};
    }
    final current = captureProbeGuard(target);
    final address = publicIp(target);
    if (address == null) {
      return {target: const ProbeAnswer(reason: 'invalid-ip')};
    }
    final url = classificationUri(address.address);
    try {
      final value = await withIpSession(
        client: requestClient,
        key: 'ipQuality:$target',
        url: url.toString(),
        timeout: const Duration(seconds: 8),
        current: current,
        action: (session, _) => lookupIpQuality(
          session.dio,
          address.address,
          cancelToken: session.cancelToken,
        ),
      );
      if (value.retryAfter != null) {
        _retryNotBefore = monotonicElapsed + value.retryAfter!;
      }
      return {target: ProbeAnswer(value: value)};
    } on IpLookupException catch (error) {
      if (error.retryAfter != null) {
        _retryNotBefore = monotonicElapsed + error.retryAfter!;
      }
      return {target: ProbeAnswer(reason: error.code)};
    }
  }
}
