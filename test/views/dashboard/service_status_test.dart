import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/service_status.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/views/dashboard/widget_metrics.dart';
import 'package:fl_clash/views/dashboard/widget_registry.dart';
import 'package:fl_clash/views/dashboard/widgets/service_status.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/glyph_finders.dart';
import '../../helpers/test_app.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _WidgetClockServiceStatus extends ServiceStatus {
  _WidgetClockServiceStatus(this.requestZone)
    : now = TestWidgetsFlutterBinding.instance.clock.now;
  final DateTime Function() now;
  final Zone requestZone;

  @override
  Future<Map<ServiceProbeKey, ProbeAnswer<ServiceCheck>>> probe(
    ServiceProbeKey target,
    RouteState route,
  ) {
    final completion =
        Completer<Map<ServiceProbeKey, ProbeAnswer<ServiceCheck>>>();
    requestZone.run(() async {
      try {
        completion.complete(await super.probe(target, route));
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  @override
  Duration get monotonicElapsed =>
      Duration(microseconds: now().microsecondsSinceEpoch);
}

ServiceCheckItem _item(
  String name,
  ServiceProbeStatus status, {
  int delay = 0,
  List<String> chains = const [],
  String region = '',
  int coreEpoch = 1,
}) => ServiceCheckItem(
  name: name,
  status: status.id,
  delay: delay,
  chains: chains,
  region: region,
  checkedAt: 1700000000000,
  coreEpoch: coreEpoch,
  picksVersion: 1,
);

OutboundIpResult _address(String ip, String country) => OutboundIpResult(
  url: 'https://www.cloudflare.com/cdn-cgi/trace',
  body: 'ip=$ip\nloc=$country\n',
  coreEpoch: 1,
  picksVersion: 1,
);

void main() {
  final requestZone = Zone.current;
  setUpAll(() {
    registerFallbackValue(const ServiceCheckParams(timeout: 0));
    registerFallbackValue(const OutboundIpParams(timeout: 0));
  });

  late _MockCore core;

  setUp(() {
    core = _MockCore();
    when(() => core.watchRoute(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as bool
          ? const RouteSnapshot(coreEpoch: 1, picksVersion: 1)
          : null,
    );
  });
  tearDown(() => verifyNever(() => core.outboundIp(any())));

  void answer(
    FutureOr<List<ServiceCheckItem>> Function(ServiceCheckParams params) check,
  ) {
    when(() => core.serviceCheck(any())).thenAnswer((invocation) async {
      final params =
          invocation.positionalArguments.single as ServiceCheckParams;
      final items = await check(params);
      return [
        for (final item in items)
          item.copyWith(
            purpose: params.purpose,
            status: params.purpose == 'advanced' && item.status == 'available'
                ? 'observed'
                : item.status,
          ),
      ];
    });
  }

  Future<void> settleDiagnostics(WidgetTester tester) async {
    for (var turn = 0; turn < 1000; turn++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => pumpEventQueue());
      if (turn >= 5 && !tester.binding.hasScheduledFrame) return;
    }
    fail('Diagnostics did not settle');
  }

  Widget app({
    FutureOr<OutboundIpResult?> Function(OutboundIpParams params)? outboundIp,
    bool started = true,
    AppSettingProps settings = const AppSettingProps(),
    double width = 360,
    double height = 84,
    Locale locale = const Locale('en'),
    Widget body = const ServiceStatusCard(),
  }) {
    when(() => core.outboundIp(any())).thenAnswer((invocation) async {
      if (outboundIp == null) return Completer<OutboundIpResult?>().future;
      return outboundIp(
        invocation.positionalArguments.single as OutboundIpParams,
      );
    });
    return TestApp(
      locale: locale,
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        serviceStatusProvider.overrideWith(
          () => _WidgetClockServiceStatus(requestZone),
        ),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 800)),
        appSettingProvider.overrideWithBuild((_, _) => settings),
        runTimeProvider.overrideWithBuild((_, _) => started ? 1 : null),
        routeTrackerProvider.overrideWithBuild(
          (ref, _) => RouteState(
            coreEpoch: 1,
            picksVersion: 1,
            hostEpoch: 1,
            proxied: ref.watch(isStartProvider),
            synced: true,
            live: true,
          ),
        ),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ipQualityProbeProvider.overrideWithBuild(
          (_, _) => throw StateError('Diagnostics requested IP quality'),
        ),
      ],
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: DashboardWidgetMetrics(unitHeight: height, child: body),
          ),
        ),
      ),
    );
  }

  test('service status is registered as an eight-column dashboard widget', () {
    final item = DashboardWidget.serviceStatus.widget;
    expect(item.crossAxisCellCount, 8);
    expect(item.child, isA<ServiceStatusCard>());
    expect(dashboardWidgetOf(item), DashboardWidget.serviceStatus);
  });

  testWidgets('holds the status and the latency with skeletons until checked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final completion = Completer<List<ServiceCheckItem>>();
    answer((_) => completion.future);
    await tester.pumpWidget(app(width: 552, height: 120));
    await tester.pump();
    await tester.pump(commonDuration);
    expect(find.byType(SkeletonText), findsNWidgets(3));
    expect(find.bySemanticsLabel(RegExp('Loading…')), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);

    completion.complete([
      _item('google', ServiceProbeStatus.available, delay: 123),
    ]);
    await settleDiagnostics(tester);
    expect(find.byType(SkeletonText), findsNothing);
    expect(find.text('Responded'), findsOneWidget);
    expect(find.text('123 ms'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('names the shown service on the tile', (tester) async {
    final semantics = tester.ensureSemantics();
    answer((_) => [_item('google', ServiceProbeStatus.available, delay: 45)]);
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);

    expect(find.text(ServiceTarget.google.label), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Google')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('Responded')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('checks the shown service directly while the proxy is off', (
    tester,
  ) async {
    final asked = <ServiceCheckParams>[];
    answer((params) {
      asked.add(params);
      return [_item('google', ServiceProbeStatus.available, delay: 45)];
    });
    await tester.pumpWidget(app(started: false));
    await settleDiagnostics(tester);

    expect(asked.single.proxyName, directOutbound);
    expect(find.text('Responded'), findsOneWidget);
    expect(find.text('45 ms'), findsOneWidget);
  });

  testWidgets('the tile shows the actual node without an IP or region lookup', (
    tester,
  ) async {
    answer(
      (_) => [
        _item(
          'google',
          ServiceProbeStatus.available,
          delay: 88,
          chains: ['HK-01'],
          region: 'JP',
        ),
      ],
    );
    await tester.pumpWidget(app(width: 288));
    await settleDiagnostics(tester);
    expect(find.text('HK-01'), findsOneWidget);
    expect(find.text('203.0.113.7'), findsNothing);
    expect(find.text('🇯🇵'), findsNothing);
    expect(find.byType(SkeletonText), findsNothing);
  });

  Future<void> openAdvanced(WidgetTester tester, ServiceTarget target) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump();
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);
    await tester.scrollUntilVisible(
      find.text(target.label),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    final row = find.widgetWithText(DecorationListItem, target.label);
    final detail = find.descendant(
      of: row,
      matching: find.byTooltip('Region / service check'),
    );
    await Scrollable.ensureVisible(tester.element(detail), alignment: 0.5);
    await settleDiagnostics(tester);
    await tester.tap(detail);
    await settleDiagnostics(tester);
  }

  testWidgets(
    'the sheet shows nodes without starting address or quality work',
    (tester) async {
      answer(
        (params) => [
          for (final name in params.names)
            _item(
              name,
              ServiceProbeStatus.available,
              chains: ['HK-01'],
              region: 'JP',
            ),
        ],
      );
      await tester.pumpWidget(app());
      await settleDiagnostics(tester);
      await tester.tap(find.byType(ServiceStatusCard));
      await settleDiagnostics(tester);
      await tester.tap(find.byTooltip('Check all'));
      await settleDiagnostics(tester);
      expect(find.text('HK-01'), findsWidgets);
      expect(find.text('203.0.113.7'), findsNothing);
      expect(find.text('🇯🇵'), findsNothing);
      await tester.tap(find.text('HK-01').first, warnIfMissed: false);
      await settleDiagnostics(tester);
      expect(find.text('Outbound IP'), findsNothing);
    },
  );

  testWidgets(
    'advanced details disclose recipients and wait for an explicit start',
    (tester) async {
      final asked = <ServiceCheckParams>[];
      answer((params) {
        asked.add(params);
        return [
          for (final name in params.names)
            _item(name, ServiceProbeStatus.available, region: 'JP'),
        ];
      });
      await tester.pumpWidget(app());
      await settleDiagnostics(tester);
      await openAdvanced(tester, ServiceTarget.youtube);
      expect(asked.map((p) => p.purpose), ['basic']);
      expect(find.text('Recipients: www.youtube.com'), findsOneWidget);
      expect(find.textContaining('No automatic reruns'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('Start one-time check')),
        alignment: 0.5,
      );
      await settleDiagnostics(tester);
      await tester.tap(find.text('Start one-time check'));
      await settleDiagnostics(tester);
      expect(asked.map((p) => p.purpose), ['basic', 'advanced']);
      expect(asked.last.names, ['youtube']);
      expect(find.textContaining('JP'), findsWidgets);
      await tester.pump(const Duration(minutes: 6));
      await settleDiagnostics(tester);
      expect(asked.where((p) => p.purpose == 'advanced'), hasLength(1));
      await tester.tap(find.byTooltip('Back'));
      await settleDiagnostics(tester);
      final row = find.widgetWithText(DecorationListItem, 'YouTube');
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byTooltip('Region / service check'),
        ),
      );
      await settleDiagnostics(tester);
      expect(asked.where((p) => p.purpose == 'advanced'), hasLength(1));
    },
  );

  testWidgets(
    'Disney registration and temporary token are explained before starting',
    (tester) async {
      final asked = <ServiceCheckParams>[];
      answer((params) {
        asked.add(params);
        return const [];
      });
      await tester.pumpWidget(app());
      await settleDiagnostics(tester);
      await openAdvanced(tester, ServiceTarget.disneyPlus);
      expect(
        find.text('Recipients: disney.api.edge.bamgrid.com'),
        findsOneWidget,
      );
      expect(
        find.textContaining('registers an anonymous browser device'),
        findsOneWidget,
      );
      expect(find.textContaining('temporary token'), findsOneWidget);
      expect(asked.every((p) => p.purpose == 'basic'), isTrue);
    },
  );

  testWidgets('advanced steps keep multiple exits and total time separate', (
    tester,
  ) async {
    answer(
      (params) => [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available).copyWith(
            elapsed: 432,
            steps: params.purpose == 'advanced'
                ? const [
                    ServiceCheckStep(
                      endpoint: 'registration',
                      httpStatus: 200,
                      delay: 12,
                      outcome: 'complete',
                      chains: ['Node A'],
                    ),
                    ServiceCheckStep(
                      endpoint: 'session',
                      httpStatus: 200,
                      delay: 34,
                      outcome: 'complete',
                      chains: ['Node B'],
                    ),
                  ]
                : const [],
          ),
      ],
    );
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    await openAdvanced(tester, ServiceTarget.disneyPlus);
    await Scrollable.ensureVisible(
      tester.element(find.text('Start one-time check')),
      alignment: 0.5,
    );
    await settleDiagnostics(tester);
    await tester.tap(find.text('Start one-time check'));
    await settleDiagnostics(tester);
    expect(find.text('Multiple exits · see each request'), findsOneWidget);
    expect(
      find.text('Total elapsed (including queue and body): 432 ms'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('session'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Node A'), findsOneWidget);
    expect(find.textContaining('Node B'), findsOneWidget);
    expect(find.text('12 ms'), findsOneWidget);
    expect(find.text('34 ms'), findsOneWidget);
  });

  testWidgets(
    'leaving advanced details cancels pending work and drops late results',
    (tester) async {
      final pending = Completer<List<ServiceCheckItem>>();
      var advancedCalls = 0;
      answer((params) {
        if (params.purpose == 'advanced') {
          advancedCalls++;
          return pending.future;
        }
        return [
          for (final name in params.names)
            _item(name, ServiceProbeStatus.available),
        ];
      });
      await tester.pumpWidget(app());
      await settleDiagnostics(tester);
      await openAdvanced(tester, ServiceTarget.youtube);
      await Scrollable.ensureVisible(
        tester.element(find.text('Start one-time check')),
        alignment: 0.5,
      );
      await settleDiagnostics(tester);
      await tester.tap(find.text('Start one-time check'));
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(commonDuration * 2);
      pending.complete([
        _item('youtube', ServiceProbeStatus.available, region: 'JP'),
      ]);
      await settleDiagnostics(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ServiceStatusCard)),
      );
      expect(
        container
            .read(serviceStatusProvider)
            .entryOf(ServiceTarget.youtube.advanced)
            .value,
        isNull,
      );
      expect(advancedCalls, 1);
    },
  );

  for (final ios in ['blocked', 'disallowed-isp']) {
    testWidgets(
      'ChatGPT details retain $ios beside trace and Web observations',
      (tester) async {
        answer(
          (params) => [
            for (final name in params.names)
              _item(name, ServiceProbeStatus.failed).copyWith(
                steps: params.purpose == 'advanced'
                    ? [
                        ServiceCheckStep(
                          endpoint: 'ios.chat.openai.com/',
                          httpStatus: 403,
                          outcome: 'complete',
                          observation: ios,
                          chains: const ['Node A'],
                        ),
                        const ServiceCheckStep(
                          endpoint: 'chat.openai.com/cdn-cgi/trace',
                          httpStatus: 200,
                          outcome: 'complete',
                          observation: 'observed',
                          region: 'JP',
                          chains: ['Node A'],
                        ),
                        const ServiceCheckStep(
                          endpoint:
                              'api.openai.com/compliance/cookie_requirements',
                          httpStatus: 403,
                          outcome: 'complete',
                          observation: 'unsupported-region',
                          chains: ['Node B'],
                        ),
                      ]
                    : const [],
              ),
          ],
        );
        await tester.pumpWidget(app());
        await settleDiagnostics(tester);
        await openAdvanced(tester, ServiceTarget.chatgpt);
        await Scrollable.ensureVisible(
          tester.element(find.text('Start one-time check')),
          alignment: 0.5,
        );
        await settleDiagnostics(tester);
        await tester.tap(find.text('Start one-time check'));
        await settleDiagnostics(tester);
        await tester.scrollUntilVisible(
          find.text('ios.chat.openai.com/'),
          80,
          scrollable: find.byType(Scrollable).last,
        );
        final iosRow = find.widgetWithText(ListTile, 'ios.chat.openai.com/');
        expect(
          find.descendant(
            of: iosRow,
            matching: find.textContaining(
              ios == 'blocked' ? 'Blocked' : 'Disallowed ISP',
            ),
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('api.openai.com/compliance/cookie_requirements'),
          80,
          scrollable: find.byType(Scrollable).last,
        );
        final trace = find.widgetWithText(
          ListTile,
          'chat.openai.com/cdn-cgi/trace',
        );
        expect(
          find.descendant(of: trace, matching: find.textContaining('JP')),
          findsOneWidget,
        );
        final web = find.widgetWithText(
          ListTile,
          'api.openai.com/compliance/cookie_requirements',
        );
        expect(
          find.descendant(
            of: web,
            matching: find.textContaining('Region not supported'),
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('the sheet marks the service the tile shows', (tester) async {
    answer((params) => const []);
    await tester.pumpWidget(
      app(settings: const AppSettingProps(currentService: 'github')),
    );
    await settleDiagnostics(tester);
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);

    final selected = tester
        .widgetList<DecorationListItem>(
          find.descendant(
            of: find.byType(ServiceStatusSheet),
            matching: find.byType(DecorationListItem),
          ),
        )
        .where((item) => item.isSelected ?? false);
    expect(selected, hasLength(1));
    expect(
      find.descendant(
        of: find.byWidget(selected.single),
        matching: find.text(ServiceTarget.github.label),
      ),
      findsOneWidget,
    );
  });

  testWidgets('horizontal dragging selects and checks the next service', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.restricted, delay: 42),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    expect(asked, ['google']);

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await settleDiagnostics(tester);

    expect(asked.last, 'github');
    expect(find.text('Access restricted'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);
  });

  testWidgets('mouse wheel and arrow keys move the horizontal picker', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.timeout),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    final position = tester.getCenter(find.byType(PageView));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, 40),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await settleDiagnostics(tester);
    expect(asked.last, 'github');
    // The tile itself takes focus first now that tapping it opens the sheet.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settleDiagnostics(tester);
    expect(asked.last, 'youtube');
  });

  testWidgets('tapping the tile lists every service in a sheet', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available, delay: 30),
      ];
    });
    await tester.pumpWidget(app(width: 552, height: 120));
    await settleDiagnostics(tester);

    await tester.tap(find.text('Responded'));
    await settleDiagnostics(tester);

    expect(find.text('Service status'), findsOneWidget);
    expect(asked, ['google']);
    expect(find.text('Not checked'), findsWidgets);
    expect(find.text(ServiceTarget.github.label), findsOneWidget);
    expect(
      find.text(
        DateTime.fromMillisecondsSinceEpoch(1700000000000).showTime.trim(),
      ),
      findsWidgets,
    );
    final list = tester.widget<SliverList>(
      find.descendant(
        of: find.byType(ServiceStatusSheet),
        matching: find.byType(SliverList),
      ),
    );
    final delegate = list.delegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, ServiceTarget.values.length);
    for (final tooltip in ['Check all', 'Manage services']) {
      expect(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(AppBar),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('the sheet is only as tall as the services it lists', (
    tester,
  ) async {
    answer((params) => const []);
    await tester.pumpWidget(
      app(
        width: 552,
        height: 120,
        settings: AppSettingProps(
          disabledServices: [
            for (final target in ServiceTarget.values)
              if (target != ServiceTarget.google) target.id,
          ],
        ),
      ),
    );
    await settleDiagnostics(tester);
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);

    final sheet = tester.getSize(find.byType(ServiceStatusSheet)).height;
    final row = tester.getSize(find.byType(ListTile)).height;
    expect(sheet, lessThan(800 * 0.7));
    expect(sheet, greaterThan(sheetAppBarHeight + row));
  });

  Finder checkAllButton() => find.ancestor(
    of: find.byTooltip('Check all'),
    matching: find.byType(IconButton),
  );

  testWidgets('the sheet checks every service, each on its own', (
    tester,
  ) async {
    final asked = <List<String>>[];
    final sweep = Completer<void>();
    answer((params) async {
      asked.add(params.names);
      if (asked.length > 1) await sweep.future;
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available, delay: 30),
      ];
    });
    await tester.pumpWidget(app(width: 552, height: 120));
    await settleDiagnostics(tester);
    await tester.tap(find.text('Responded'));
    await settleDiagnostics(tester);
    expect(asked, [
      ['google'],
    ]);

    await tester.tap(checkAllButton());
    for (var turn = 0; turn < 6; turn++) {
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
    }
    expect(asked.skip(1), [
      for (final target in ServiceTarget.values)
        if (target != ServiceTarget.google) [target.id],
    ]);
    expect(tester.widget<IconButton>(checkAllButton()).onPressed, isNull);

    sweep.complete();
    await settleDiagnostics(tester);
    expect(asked, hasLength(ServiceTarget.values.length + 1));
    expect(find.text('Not checked'), findsNothing);
    expect(tester.widget<IconButton>(checkAllButton()).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('picking a service in the sheet switches the tile to it', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available, delay: 30),
      ];
    });
    await tester.pumpWidget(app(width: 552, height: 120));
    await settleDiagnostics(tester);
    await tester.tap(find.text('Responded'));
    await settleDiagnostics(tester);

    await tester.scrollUntilVisible(
      find.text(ServiceTarget.spotify.label),
      60,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(find.text(ServiceTarget.spotify.label));
    await settleDiagnostics(tester);

    expect(find.text('Service status'), findsNothing);
    expect(asked, ['google', ServiceTarget.spotify.id]);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(ServiceStatusCard)),
      ).read(appSettingProvider).currentService,
      ServiceTarget.spotify.id,
    );
  });

  testWidgets('returning to a service checked on this route asks nothing', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await settleDiagnostics(tester);
    await tester.drag(find.byType(PageView), const Offset(200, 0));
    await settleDiagnostics(tester);

    expect(asked, ['google', 'github']);
  });

  testWidgets('returning to a timed-out service checks it again', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(
            name,
            asked.length == 1
                ? ServiceProbeStatus.timeout
                : ServiceProbeStatus.available,
          ),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    expect(find.text('Timeout'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await settleDiagnostics(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(120, 0));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    expect(find.text('Timeout'), findsNothing);
    await gesture.up();
    await settleDiagnostics(tester);

    expect(asked, ['google', 'github']);
    await tester.pump(const Duration(seconds: 30));
    await settleDiagnostics(tester);
    expect(asked, ['google', 'github', 'google']);
    expect(find.text('Timeout'), findsNothing);
  });

  testWidgets('a route change checks the shown service again once', (
    tester,
  ) async {
    final asked = <String>[];
    var epoch = 1;
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available, coreEpoch: epoch),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    expect(asked, ['google']);

    epoch = 2;
    ProviderScope.containerOf(tester.element(find.byType(ServiceStatusCard)))
        .read(routeTrackerProvider.notifier)
        .applySnapshot(const RouteSnapshot(coreEpoch: 2, picksVersion: 1));
    await settleDiagnostics(tester);

    expect(asked, ['google']);
    await tester.pump(const Duration(seconds: 30));
    await settleDiagnostics(tester);
    expect(asked, ['google', 'google']);
    expect(find.text('Responded'), findsOneWidget);
  });

  testWidgets('a row re-checks its service on its own button', (tester) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available, delay: 30),
      ];
    });
    await tester.pumpWidget(app(width: 552, height: 120));
    await settleDiagnostics(tester);
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);
    expect(asked, ['google']);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, ServiceTarget.github.label),
        matching: find.byTooltip('Check'),
      ),
    );
    await settleDiagnostics(tester);
    expect(asked, ['google', 'github']);
  });

  testWidgets('a row keeps its height through a check', (tester) async {
    final github = Completer<void>();
    answer((params) async {
      if (params.names.contains('github')) await github.future;
      return [
        for (final name in params.names)
          _item(
            name,
            ServiceProbeStatus.available,
            delay: 30,
            chains: const ['Node A'],
          ),
      ];
    });
    await tester.pumpWidget(
      app(
        width: 552,
        height: 120,
        outboundIp: (_) => _address('203.0.113.7', 'US'),
      ),
    );
    await settleDiagnostics(tester);
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);

    final row = find.widgetWithText(ListTile, ServiceTarget.github.label);
    final unchecked = tester.getSize(row).height;
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Check')),
    );
    await tester.pump();
    expect(tester.getSize(row).height, unchecked);

    github.complete();
    await settleDiagnostics(tester);
    expect(find.descendant(of: row, matching: find.text('Node A')), findsOne);
    expect(tester.getSize(row).height, unchecked);
  });

  testWidgets('the sheet still offers checks while the proxy is off', (
    tester,
  ) async {
    answer((params) => const []);
    await tester.pumpWidget(app(started: false, width: 552, height: 120));
    await settleDiagnostics(tester);
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);

    final buttons = tester.widgetList<IconButton>(
      find.ancestor(
        of: find.byGlyph(AppGlyphs.refresh),
        matching: find.byType(IconButton),
      ),
    );
    expect(buttons, isNotEmpty);
    expect(buttons.every((button) => button.onPressed != null), isTrue);
    expect(tester.widget<IconButton>(checkAllButton()).onPressed, isNotNull);
  });

  AppSettingProps settingsOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(ServiceStatusCard)),
  ).read(appSettingProvider);

  Future<void> openManage(WidgetTester tester) async {
    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);
    await tester.tap(find.byTooltip('Manage services'));
    await settleDiagnostics(tester);
  }

  Finder switchOf(ServiceTarget target) => find.descendant(
    of: find.widgetWithText(DecorationListItem, target.label),
    matching: find.byType(Switch),
  );

  testWidgets('the tile and the sheet follow the saved order', (tester) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available),
      ];
    });
    await tester.pumpWidget(
      app(
        width: 552,
        height: 120,
        settings: const AppSettingProps(
          serviceOrder: ['claude', 'google'],
          disabledServices: ['github'],
        ),
      ),
    );
    await settleDiagnostics(tester);
    expect(asked, ['claude']);

    await tester.tap(find.byType(ServiceStatusCard));
    await settleDiagnostics(tester);
    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ServiceStatusSheet),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  ServiceTarget.values.any(
                    (target) => target.label == widget.data,
                  ),
            ),
          ),
        )
        .map((text) => text.data)
        .take(3);
    expect(labels, ['Claude', 'Google', 'YouTube']);
    expect(find.text(ServiceTarget.github.label), findsNothing);
  });

  testWidgets('services are turned off from a page pushed inside the sheet', (
    tester,
  ) async {
    answer((params) => const []);
    await tester.pumpWidget(app(width: 552, height: 120));
    await settleDiagnostics(tester);
    await openManage(tester);

    expect(find.text('Manage services'), findsOneWidget);
    expect(find.text('Service status'), findsNothing);
    await tester.tap(switchOf(ServiceTarget.youtube));
    await settleDiagnostics(tester);
    expect(settingsOf(tester).disabledServices, ['youtube']);

    await tester.tap(find.byTooltip('Back'));
    await settleDiagnostics(tester);
    expect(find.text('Service status'), findsOneWidget);
    expect(find.text(ServiceTarget.youtube.label), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await settleDiagnostics(tester);
    expect(find.text('Service status'), findsNothing);
    expect(find.byType(ServiceStatusCard), findsOneWidget);
  });

  testWidgets('all services can be disabled and managed again', (tester) async {
    answer((params) => const []);
    await tester.pumpWidget(
      app(
        width: 552,
        height: 120,
        settings: AppSettingProps(
          disabledServices: [
            for (final target in ServiceTarget.values)
              if (target != ServiceTarget.google) target.id,
          ],
        ),
      ),
    );
    await settleDiagnostics(tester);
    await openManage(tester);

    await tester.tap(switchOf(ServiceTarget.google));
    await settleDiagnostics(tester);
    expect(
      settingsOf(tester).disabledServices,
      hasLength(ServiceTarget.values.length),
    );
    await tester.tap(find.byTooltip('Back'));
    await settleDiagnostics(tester);
    expect(find.text('All services disabled · Manage services'), findsWidgets);
    expect(tester.widget<IconButton>(checkAllButton()).onPressed, isNull);
    await tester.tap(find.byTooltip('Close'));
    await settleDiagnostics(tester);
    await openManage(tester);
    await tester.tap(switchOf(ServiceTarget.github));
    await settleDiagnostics(tester);
    expect(settingsOf(tester).disabledServices, isNot(contains('github')));
  });

  testWidgets('dragging a service in the manage page saves the new order', (
    tester,
  ) async {
    answer((params) => const []);
    await tester.pumpWidget(app(width: 552, height: 120));
    await settleDiagnostics(tester);
    await openManage(tester);

    final handle = find.descendant(
      of: find.widgetWithText(DecorationListItem, ServiceTarget.google.label),
      matching: find.byGlyph(AppGlyphs.dragHandle),
    );
    final rowHeight = tester
        .getSize(
          find.widgetWithText(DecorationListItem, ServiceTarget.google.label),
        )
        .height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.3));
      await tester.pump();
    }
    await gesture.up();
    await settleDiagnostics(tester);

    expect(settingsOf(tester).serviceOrder.take(2), ['github', 'google']);
  });

  testWidgets('the tile moves on when its service is turned off', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    expect(asked, ['google']);

    ProviderScope.containerOf(
      tester.element(find.byType(ServiceStatusCard)),
    ).read(appSettingProvider.notifier).value = const AppSettingProps(
      disabledServices: ['google'],
    );
    await settleDiagnostics(tester);

    expect(asked, ['google', 'github']);
    final picker = tester.widget<PageView>(find.byType(PageView));
    expect(picker.controller!.page, 0);
    expect(settingsOf(tester).currentService, 'github');
  });

  testWidgets('the service scrolled to is saved', (tester) async {
    answer((params) => const []);
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);

    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await settleDiagnostics(tester);

    expect(settingsOf(tester).currentService, 'github');
  });

  testWidgets('the tile opens on the saved service', (tester) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return const [];
    });
    await tester.pumpWidget(
      app(settings: const AppSettingProps(currentService: 'claude')),
    );
    await settleDiagnostics(tester);

    expect(asked, ['claude']);
    final picker = tester.widget<PageView>(find.byType(PageView));
    expect(
      picker.controller!.page,
      ServiceTarget.values.indexOf(ServiceTarget.claude),
    );
  });

  testWidgets('a saved service that is turned off falls back to the first', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return const [];
    });
    await tester.pumpWidget(
      app(
        settings: const AppSettingProps(
          currentService: 'claude',
          disabledServices: ['claude'],
        ),
      ),
    );
    await settleDiagnostics(tester);

    expect(asked, ['google']);
  });

  testWidgets('an unexpected error shows the check as failed', (tester) async {
    answer(
      (params) => [
        for (final name in params.names) _item(name, ServiceProbeStatus.failed),
      ],
    );
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    expect(find.text('Unable to determine'), findsOneWidget);
  });

  testWidgets('a check without a node keeps the title in place', (
    tester,
  ) async {
    final completion = Completer<List<ServiceCheckItem>>();
    answer((_) => completion.future);
    await tester.pumpWidget(app(width: 552, height: 120));
    await tester.pump();
    await tester.pump(commonDuration);
    final title = find.text(ServiceTarget.google.label);
    final checking = tester.getTopLeft(title).dy;

    completion.complete([_item('google', ServiceProbeStatus.failed)]);
    await settleDiagnostics(tester);
    expect(find.text('Unable to determine'), findsOneWidget);
    expect(tester.getTopLeft(title).dy, checking);
  });

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ServiceStatusCard)));

  void setStarted(WidgetTester tester, bool started) {
    final runTime = containerOf(tester).read(runTimeProvider.notifier);
    runTime.value = started ? 1 : null;
  }

  ProbePhase checkPhase(WidgetTester tester) => containerOf(
    tester,
  ).read(serviceStatusProvider).entryOf(ServiceTarget.google.basic).phase;

  testWidgets(
    'starting the proxy waits for the interval and uses the latest route',
    (tester) async {
      var epoch = 1;
      answer(
        (params) => [
          for (final name in params.names)
            _item(name, ServiceProbeStatus.available, coreEpoch: epoch),
        ],
      );
      await tester.pumpWidget(app(started: false));
      await settleDiagnostics(tester);
      setStarted(tester, true);
      await settleDiagnostics(tester);
      expect(checkPhase(tester), ProbePhase.queued);
      expect(find.text('Unable to determine'), findsNothing);
      epoch = 2;
      containerOf(tester)
          .read(routeTrackerProvider.notifier)
          .applySnapshot(const RouteSnapshot(coreEpoch: 2, picksVersion: 1));
      await tester.pump(const Duration(seconds: 30));
      await settleDiagnostics(tester);
      expect(find.text('Responded'), findsOneWidget);
    },
  );

  testWidgets('a failed request is shown after the start interval', (
    tester,
  ) async {
    answer(
      (params) => [
        for (final name in params.names)
          _item(
            name,
            params.proxyName == directOutbound
                ? ServiceProbeStatus.available
                : ServiceProbeStatus.failed,
          ),
      ],
    );
    await tester.pumpWidget(app(started: false));
    await settleDiagnostics(tester);
    setStarted(tester, true);
    await settleDiagnostics(tester);
    expect(checkPhase(tester), ProbePhase.queued);
    await tester.pump(const Duration(seconds: 30));
    await settleDiagnostics(tester);
    expect(checkPhase(tester), ProbePhase.failed);
    expect(find.text('Unable to determine'), findsOneWidget);
  });

  testWidgets('stopping during a queued check uses the direct route', (
    tester,
  ) async {
    final asked = <ServiceCheckParams>[];
    answer((params) {
      asked.add(params);
      return [
        for (final name in params.names) _item(name, ServiceProbeStatus.failed),
      ];
    });
    await tester.pumpWidget(app(started: false));
    await settleDiagnostics(tester);
    setStarted(tester, true);
    await settleDiagnostics(tester);
    expect(checkPhase(tester), ProbePhase.queued);
    setStarted(tester, false);
    await tester.pump(const Duration(seconds: 30));
    await settleDiagnostics(tester);
    expect(asked.last.proxyName, directOutbound);
    expect(find.text('Unable to determine'), findsOneWidget);
  });

  testWidgets('starting the proxy does not start IP work from diagnostics', (
    tester,
  ) async {
    answer(
      (params) => [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available, chains: ['HK-01']),
      ],
    );
    await tester.pumpWidget(app(started: false));
    await settleDiagnostics(tester);
    setStarted(tester, true);
    await tester.pump(const Duration(seconds: 30));
    await settleDiagnostics(tester);
    expect(find.text('Responded'), findsOneWidget);
    expect(find.text('HK-01'), findsOneWidget);
  });

  testWidgets('leaving the dashboard releases the shown service', (
    tester,
  ) async {
    final asked = <String>[];
    answer((params) {
      asked.addAll(params.names);
      return [
        for (final name in params.names)
          _item(name, ServiceProbeStatus.available),
      ];
    });
    await tester.pumpWidget(app());
    await settleDiagnostics(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ServiceStatusCard)),
    );

    await tester.pumpWidget(app(body: const SizedBox.shrink()));
    container.read(routeTrackerProvider.notifier).bumpHostEpoch();
    await tester.pump();

    expect(asked, ['google']);
    expect(container.read(serviceStatusProvider).entries, isEmpty);
  });

  testWidgets('fits one row at narrow and wide sizes in every locale', (
    tester,
  ) async {
    answer(
      (params) => [
        for (final name in params.names)
          _item(
            name,
            ServiceProbeStatus.unavailable,
            delay: 1234,
            chains: ['HK-01'],
          ),
      ],
    );
    for (final locale in [
      const Locale('en'),
      const Locale('zh', 'CN'),
      const Locale('ja'),
      const Locale('ru'),
    ]) {
      for (final size in [const Size(288, 84), const Size(552, 120)]) {
        await tester.pumpWidget(
          app(
            outboundIp: (_) => _address('203.0.113.7', 'US'),
            width: size.width,
            height: size.height,
            locale: locale,
          ),
        );
        await settleDiagnostics(tester);
        expect(
          tester.getSize(find.byType(ServiceStatusCard)).height,
          size.height,
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('1234 ms'))
              .didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}
