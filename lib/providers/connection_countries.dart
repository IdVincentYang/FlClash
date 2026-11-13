import 'dart:convert';

import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core.dart';
import 'outbound_ip.dart';
import 'route_state.dart';
import 'routed_probe.dart';

String? connectionProxyServerIp(TrackerInfo info) {
  if (info.chains.isEmpty ||
      const {
        'DIRECT',
        'COMPATIBLE',
        'REJECT',
        'REJECT-DROP',
        'PASS',
      }.contains(info.chains.first.toUpperCase())) {
    return null;
  }
  final ip = publicIp(info.metadata.remoteDestination)?.address;
  if (ip == publicIp(info.metadata.destinationIP)?.address ||
      ip == publicIp(info.metadata.host)?.address) {
    return null;
  }
  return ip;
}

final observedLocalPublicIpProvider = Provider<String?>((ref) {
  final probes = ref.watch(outboundIpProbeProvider);
  final route = ref.watch(routeTrackerProvider);
  for (final entry in probes.entries.values) {
    final stamp = entry.stamp;
    final time = entry.value?.checkedAt;
    if (entry.phase == ProbePhase.fresh &&
        !entry.expired &&
        stamp != null &&
        stamp.chains.length == 1 &&
        stamp.chains.single == directOutbound &&
        route.isFresh(stamp) &&
        time != null &&
        DateTime.now().difference(time) <= const Duration(minutes: 5)) {
      return publicIp(entry.value!.ip)?.address;
    }
  }
  return null;
});

final connectionCountriesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, key) async {
      if (!ref.watch(initProvider)) return const {};
      final ips = List<String>.from(jsonDecode(key) as List);
      final result = <String, String>{};
      for (var offset = 0; offset < ips.length && ref.mounted; offset += 128) {
        result.addAll(
          await ref
              .read(coreHandlerProvider)
              .lookupIpCountries(ips.skip(offset).take(128).toList()),
        );
      }
      return Map.unmodifiable(result);
    }, retry: (_, _) => null);
