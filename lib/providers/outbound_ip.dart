import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/outbound_ip.g.dart';

/// Keyed by the outbound a lookup pins: a node name, `DIRECT`, or
/// [routedOutbound] for whatever the rules pick right now.
@Riverpod(keepAlive: true)
class OutboundIpProbe extends _$OutboundIpProbe
    with RoutedProbe<String, IpInfo> {
  @override
  RoutedProbeState<String, IpInfo> build() => buildProbe();

  @override
  void cancelProbe(String target) => request.cancelKey('outboundIp:$target');

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    final proxyName = target == routedOutbound && !route.proxied
        ? directOutbound
        : target;
    final result = await request.withSession(
      key: 'outboundIp:$target',
      url: 'https://diagnostic.invalid',
      explicitTarget: proxyName,
      action: (session) async {
        if (!ref.mounted) throw const RequestUnavailable('request_cancelled');
        final result = await lookupOutboundIp(
          ref.read(coreHandlerProvider),
          proxyName,
        );
        await session.check();
        return result;
      },
    );
    final value = parseOutboundIp(result);
    final chains = result?.chains ?? const <String>[];
    final exit = chains.firstOrNull;
    return {
      target: ProbeAnswer(
        value: value,
        coreEpoch: result?.coreEpoch,
        picksVersion: result?.picksVersion,
        chains: chains,
      ),
      // A node leaves through the same address whatever it is asked for.
      if (value != null && exit != null && exit != target)
        exit: ProbeAnswer(
          value: value,
          coreEpoch: result?.coreEpoch,
          picksVersion: result?.picksVersion,
          chains: [exit],
        ),
    };
  }
}
