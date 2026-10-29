import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/views/dashboard/widget_metrics.dart';
import 'package:fl_clash/views/dashboard/widgets/network_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';

class _Outbound extends OutboundIpProbe {
  int calls = 0;
  @override
  RoutedProbeState<String, IpInfo> build() {
    buildProbe();
    return const RoutedProbeState({
      routedOutbound: ProbeEntry(
        phase: ProbePhase.fresh,
        value: IpInfo(ip: '1.1.1.1', countryCode: 'AU'),
      ),
    });
  }

  @override
  Future<Map<String, ProbeAnswer<IpInfo>>> probe(
    String target,
    RouteState route,
  ) async {
    calls++;
    return {
      target: const ProbeAnswer(
        value: IpInfo(ip: '1.1.1.1', countryCode: 'AU'),
      ),
    };
  }
}

class _Quality extends IpQualityProbe {
  int calls = 0;
  Duration elapsed = Duration.zero;
  @override
  Duration get monotonicElapsed => elapsed;
  @override
  Future<Map<String, ProbeAnswer<IpQuality>>> probe(
    String target,
    RouteState route,
  ) async {
    calls++;
    return {
      target: ProbeAnswer(
        value: IpQuality(
          ip: target,
          source: IpQualitySource.proxyCheck,
          organization: 'Fixture org',
          checkedAt: DateTime(2026),
        ),
      ),
    };
  }
}

void main() {
  late _Outbound outbound;
  late _Quality quality;
  Widget app({bool preview = false, bool hidden = false}) => TestApp(
    locale: const Locale('en'),
    overrides: [
      outboundIpProbeProvider.overrideWith(() => outbound = _Outbound()),
      ipQualityProbeProvider.overrideWith(() => quality = _Quality()),
      appSettingProvider.overrideWithBuild(
        (_, _) => AppSettingProps(hideIp: hidden),
      ),
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
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 260,
          child: DashboardWidgetMetrics(
            unitHeight: 84,
            child: NetworkDetection(preview: preview),
          ),
        ),
      ),
    ),
  );
  setUp(() {
    outbound = _Outbound();
    quality = _Quality();
  });
  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'default card and opening details do not classify; explicit action does',
    (tester) async {
      await tall(tester);
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('1.1.1.1'), findsOneWidget);
      expect(quality.calls, 0);
      expect(outbound.calls, 0);
      await tester.tap(find.text('1.1.1.1'));
      await tester.pumpAndSettle();
      expect(quality.calls, 0);
      expect(find.text('Good'), findsNothing);
      await tester.tap(find.text('Classify this IP'));
      await tester.pumpAndSettle();
      expect(quality.calls, 1);
      expect(find.text('Fixture org'), findsOneWidget);
      expect(find.text('Unknown'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Hide IP'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('1.1.1.1'), findsNothing);
      expect(quality.calls, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('hidden display and tooltip do not request classification', (
    tester,
  ) async {
    await tester.pumpWidget(app(hidden: true));
    await tester.pump();
    expect(find.text('1.1.1.1'), findsNothing);
    expect(find.text('*****'), findsOneWidget);
    expect(find.byTooltip('*****'), findsOneWidget);
    expect(quality.calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('component preview never observes either network provider', (
    tester,
  ) async {
    await tester.pumpWidget(app(preview: true));
    await tester.pumpAndSettle();
    expect(outbound.calls, 0);
    expect(quality.calls, 0);
    expect(find.byTooltip('Check exit IP'), findsNothing);
  });
  testWidgets(
    'manual card action and disclosed automatic switch remain distinct',
    (tester) async {
      await tall(tester);
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.byTooltip('Check exit IP'));
      await tester.pumpAndSettle();
      expect(outbound.calls, 1);
      expect(quality.calls, 0);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cloudflare over HTTPS'), findsOneWidget);
      expect(find.text('Automatic on dashboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('preview can become a normal card without an implicit request', (
    tester,
  ) async {
    await tester.pumpWidget(app(preview: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pump();
    expect(outbound.calls, 0);
    expect(quality.calls, 0);
    await tester.tap(find.byTooltip('Check exit IP'));
    await tester.pumpAndSettle();
    expect(outbound.calls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'provider recreation retains passive ownership without replaying classification',
    (tester) async {
      await tall(tester);
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('1.1.1.1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classify this IP'));
      await tester.pumpAndSettle();
      expect(quality.calls, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NetworkDetection)),
      );
      final previous = quality;
      container.invalidate(ipQualityProbeProvider);
      await tester.pumpAndSettle();
      final retained = identical(previous, quality) ? 1 : 0;
      expect(quality.calls, retained);
      quality.elapsed = const Duration(seconds: 30);
      await tester.tap(find.text('Classify this IP'));
      await tester.pumpAndSettle();
      expect(quality.calls, retained + 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
