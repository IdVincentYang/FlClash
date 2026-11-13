import 'dart:convert';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/connection_countries.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Core extends Fake implements CoreHandlerInterface {
  final calls = <List<String>>[];
  @override
  Future<Map<String, String>> lookupIpCountries(List<String> ips) async {
    calls.add(ips);
    return {for (final ip in ips) ip: 'US'};
  }
}

class _Probe extends OutboundIpProbe {
  _Probe(this.value);
  final RoutedProbeState<String, IpInfo> value;
  @override
  RoutedProbeState<String, IpInfo> build() => value;
}

class _Route extends RouteTracker {
  _Route(this.value);
  final RouteState value;
  @override
  RouteState build() => value;
}

void main() {
  for (final ready in [false, true]) {
    test(
      'offline lookup batches up to 128 addresses only when Core is ready: $ready',
      () async {
        final core = _Core();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => ready),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          ],
        );
        addTearDown(container.dispose);
        final ips = [for (var i = 1; i <= 130; i++) '8.8.0.$i'];
        final provider = connectionCountriesProvider(jsonEncode(ips));
        container.listen(provider, (_, _) {});
        final countries = await container.read(provider.future);
        expect(
          core.calls.map((call) => call.length),
          ready ? [128, 2] : isEmpty,
        );
        expect(countries.length, ready ? 130 : 0);
      },
    );
  }

  for (final reason in [
    'valid',
    'expired',
    'route changed',
    'proxy route',
    'private',
    'not checked',
  ]) {
    test(
      'local country source uses only a current measured DIRECT address: $reason',
      () {
        final entry = ProbeEntry<IpInfo>(
          phase: ProbePhase.fresh,
          value: IpInfo(
            ip: reason == 'private' ? '192.168.1.1' : '8.8.8.8',
            countryCode: 'US',
            checkedAt: reason == 'not checked' ? null : DateTime.now(),
          ),
          expired: reason == 'expired',
          stamp: RouteStamp(
            coreEpoch: 1,
            picksVersion: 1,
            hostEpoch: reason == 'route changed' ? 0 : 1,
            proxied: true,
            chains: [reason == 'proxy route' ? 'node' : 'DIRECT'],
          ),
        );
        final container = ProviderContainer(
          overrides: [
            outboundIpProbeProvider.overrideWith(
              () => _Probe(RoutedProbeState({'DIRECT': entry})),
            ),
            routeTrackerProvider.overrideWith(
              () => _Route(
                const RouteState(
                  coreEpoch: 1,
                  picksVersion: 1,
                  hostEpoch: 1,
                  proxied: true,
                  synced: true,
                  live: true,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(observedLocalPublicIpProvider),
          reason == 'valid' ? '8.8.8.8' : null,
        );
      },
    );
  }
}
