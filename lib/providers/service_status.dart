import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'config.dart';
import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/service_status.g.dart';

@Riverpod(keepAlive: true)
class ServiceStatus extends _$ServiceStatus
    with RoutedProbe<ServiceProbeKey, ServiceCheck> {
  @override
  RoutedProbeState<ServiceProbeKey, ServiceCheck> build() {
    ref.listen(
      appSettingProvider.select(
        (settings) => SelectValue(settings.disabledServices),
      ),
      (_, _) => reconcileEligibility(),
    );
    return buildProbe();
  }

  @override
  ProbeSchedule get probeSchedule => const ProbeSchedule(
    minimumInterval: Duration(seconds: 30),
    maxAge: Duration(minutes: 5),
  );

  @override
  bool isEligible(ServiceProbeKey target) =>
      !ref
          .read(appSettingProvider)
          .disabledServices
          .contains(target.target.id) &&
      (target.purpose == ServiceProbePurpose.basic ||
          target.target.hasAdvanced);

  @override
  bool allowsAutomatic(ServiceProbeKey target) =>
      target.purpose == ServiceProbePurpose.basic;

  @override
  void cancelProbe(ServiceProbeKey target) =>
      request.cancelKey('service:${target.target.id}:${target.purpose.name}');

  @override
  bool isFailure(ServiceCheck value) =>
      value.status == ServiceProbeStatus.timeout ||
      value.status == ServiceProbeStatus.failed;

  @override
  Future<Map<ServiceProbeKey, ProbeAnswer<ServiceCheck>>> probe(
    ServiceProbeKey target,
    RouteState route,
  ) async {
    final current = captureProbeGuard(target);
    final proxy = route.proxied ? '' : directOutbound;
    final checks = await request.withSession(
      key: 'service:${target.target.id}:${target.purpose.name}',
      url: 'https://diagnostic.invalid',
      explicitTarget: proxy,
      action: (session) async {
        if (!current()) {
          throw const RequestUnavailable('request_cancelled');
        }
        await session.check();
        if (!current()) throw const RequestUnavailable('request_cancelled');
        final result = await checkServices(
          ref.read(coreHandlerProvider),
          proxyName: proxy,
          targets: [target.target],
          purpose: target.purpose,
        );
        await session.check();
        return result;
      },
    );
    final check = checks[target.target];
    return {
      if (check != null)
        target: ProbeAnswer(
          value: check,
          coreEpoch: check.coreEpoch,
          picksVersion: check.picksVersion,
          chains: check.chains,
        ),
    };
  }
}

@riverpod
List<ServiceTarget> serviceTargets(Ref ref) {
  final order = ref.watch(
    appSettingProvider.select((state) => SelectValue(state.serviceOrder)),
  );
  return orderServiceTargets(order.value);
}

@riverpod
List<ServiceTarget> enabledServiceTargets(Ref ref) {
  final targets = ref.watch(serviceTargetsProvider);
  final disabled = ref.watch(
    appSettingProvider.select((state) => SelectValue(state.disabledServices)),
  );
  final enabled = [
    for (final target in targets)
      if (!disabled.value.contains(target.id)) target,
  ];
  return enabled;
}
