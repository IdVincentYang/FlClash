import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/application_activity.dart';
import 'package:fl_clash/common/datetime.dart';
import 'package:fl_clash/features/connection/tracker_info_item.dart';
import 'package:fl_clash/widgets/connection_exit.dart';
import 'package:fl_clash/providers/connection_exits.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/common/connection_address.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/application_connections.dart';
import 'package:fl_clash/views/application_targets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/application_activity.dart';
import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';

class _Activity extends ApplicationActivity {
  _Activity(this.initial);
  final ApplicationActivityState initial;
  int refreshes = 0;
  @override
  ApplicationActivityState build() => initial;
  void replace(ApplicationActivityState next) => state = next;
  @override
  Future<void> refresh() async => refreshes++;
}

class _Core extends Fake implements CoreHandlerInterface {
  final calls = <List<String>>[];
  bool fail = false;
  @override
  Future<Map<String, String>> lookupIpCountries(List<String> ips) async {
    calls.add(ips);
    if (fail) throw StateError('database unavailable');
    return {
      for (final ip in ips)
        if (ip == '8.8.8.8')
          ip: 'US'
        else if (ip == '114.114.114.114')
          ip: 'CN'
        else if (ip == '8.210.0.1')
          ip: 'HK'
        else if (ip == '202.175.1.1')
          ip: 'MO'
        else if (ip == '168.95.1.1')
          ip: 'TW',
    };
  }
}

class _Exits extends ConnectionExits {
  _Exits(this.core);
  final _Core core;
  final requests = <ConnectionExitTarget>[];
  @override
  Map<ConnectionExitTarget, ConnectionExitEntry> build() => const {};
  @override
  bool isExpired(ConnectionExitTarget target) => state[target]?.value == null;
  void _answer(ConnectionExitTarget target) {
    requests.add(target);
    final country = target.node.contains('🇭🇰')
        ? 'HK'
        : switch (target.entry) {
            '114.114.114.114' => 'CN',
            '8.210.0.1' => 'HK',
            '202.175.1.1' => 'MO',
            '168.95.1.1' => 'TW',
            _ => 'US',
          };
    state = {
      ...state,
      target: ConnectionExitEntry(
        core.fail ? ProbePhase.failed : ProbePhase.fresh,
        value: core.fail
            ? null
            : IpInfo(
                ip: '8.210.0.1',
                countryCode: country,
                checkedAt: DateTime(2026, 11, 13, 14, 33),
              ),
      ),
    };
  }

  @override
  void watch(ConnectionExitTarget target, {required bool automatic}) {
    if (automatic && !state.containsKey(target)) _answer(target);
  }

  @override
  void unwatch(ConnectionExitTarget target, {required bool automatic}) {}
  @override
  ExitRefreshResult refresh(ConnectionExitTarget target) {
    _answer(target);
    return ExitRefreshResult.accepted;
  }
}

const _page = ApplicationConnectionsView(
  appKey: 'package:test.app.a',
  hostKey: 'host:example.test',
  appLabel: 'Browser A',
);

const _targets = ApplicationTargetsView(
  appKey: 'package:test.app.a',
  label: 'Browser A',
  packageName: 'test.app.a',
  identity: ApplicationIdentity(
    status: 'known',
    uid: 10001,
    userScope: 'current',
    packages: ['test.app.a'],
  ),
);

TrackerInfo connection(
  String id, {
  String package = 'test.app.a',
  int offset = 0,
  String server = '8.8.8.8',
  String exit = 'US 01',
}) {
  final value = activityConnection(
    id,
    package: package,
    start: DateTime(2026, 11, 13, 14, 32, offset),
    exit: exit,
  );
  return value.copyWith(
    metadata: value.metadata.copyWith(
      destinationPort: '443',
      remoteDestination: server,
      sourceIP: '10.0.2.15',
      sourcePort: '${30000 + offset}',
      destinationGeoIP: ['JP'],
    ),
  );
}

void main() {
  final font = Platform.environment['FLCLASH_ACTIVITY_FONT'];
  setUpAll(() async {
    if (font == null) return;
    final loader = FontLoader('ActivityPreview')
      ..addFont(
        Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
      );
    await loader.load();
    final emoji = FontLoader('Apple Color Emoji')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '/System/Library/Fonts/Apple Color Emoji.ttc',
            ).readAsBytesSync(),
          ),
        ),
      );
    await emoji.load();
  });
  late ProviderContainer container;
  late _Activity notifier;
  late _Core core;
  late _Exits exits;
  late ApplicationActivityStore store;
  final now = DateTime(2026, 11, 13, 14, 33);
  setUp(() {
    store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: now);
    core = _Core();
    exits = _Exits(core);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Future<void> pump(
    WidgetTester tester, {
    Widget child = _page,
    double width = 420,
    double scale = 1,
    Locale? locale,
    bool confirm = true,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (confirm && !store.snapshot().hasSnapshot) {
      store.applySnapshot(
        store.snapshot().connections.map((item) => item.info).toList(),
        startedRevision: store.revision,
        now: now,
      );
    }
    notifier = _Activity(store.snapshot());
    container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(
          () => TestConfigState(const ConfigFact(inputId: 'input-a')),
        ),
        connectionExitsProvider.overrideWith(() => exits),
        initProvider.overrideWithBuild((_, _) => true),
        applicationActivityProvider.overrideWith(() => notifier),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        applicationCatalogueProvider.overrideWith(
          (_) async => const ApplicationCatalogue(
            packages: [
              Package(
                packageName: 'test.app.b',
                label: 'Mail B',
                system: false,
                internet: true,
                lastUpdateTime: 0,
              ),
            ],
            accessible: true,
          ),
        ),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: const ValueKey('connections-capture'),
          child: TestApp(
            locale: locale,
            homeBuilder: (child) => Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Theme(
                  data: font == null
                      ? Theme.of(context)
                      : Theme.of(context).copyWith(
                          textTheme: Theme.of(
                            context,
                          ).textTheme.apply(fontFamily: 'ActivityPreview'),
                        ),
                  child: child,
                ),
              ),
            ),
            child: StatusManager(child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    final output = Platform.environment['FLCLASH_ACTIVITY_SCREENSHOTS'];
    if (output == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('connections-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(output).createSync(recursive: true);
      File('$output/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  Finder row(String id) => find.byKey(ValueKey('connection:runtime-a:$id'));

  TextStyle timestampStyle(WidgetTester tester, String id) =>
      DefaultTextStyle.of(
        tester.element(
          find.descendant(of: row(id), matching: find.byType(RecordTimestamp)),
        ),
      ).style;

  testWidgets('measured HK exit wins over a mainland entry and a node label', (
    tester,
  ) async {
    store.addEvent(
      connection('hk-exit', server: '114.114.114.114', exit: '🇭🇰 V香港 01'),
    );
    await pump(tester, child: _targets);
    expect(find.text('🇭🇰'), findsOneWidget);
    expect(find.text('🇨🇳'), findsNothing);
    expect(exits.requests.single.node, '🇭🇰 V香港 01');
    await screenshot(tester, 'measured-exit-target-hk');
    await tester.tap(find.text('example.test'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('🇭🇰'), findsOneWidget);
    expect(exits.requests, hasLength(1));
    expect(
      find.byTooltip(
        'Measured exit: 8.210.0.1 · HK\nChecked: 2026-11-13 14:33:00\nTap to check again. Other destinations may use a different exit.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'ended connections do not probe automatically and support an explicit check',
    (tester) async {
      store.addEvent(connection('ended'));
      store.applySnapshot([], startedRevision: store.revision, now: now);
      await pump(tester);
      expect(exits.requests, isEmpty);
      expect(find.text('🇺🇸'), findsNothing);
      await tester.tap(
        find.byTooltip(
          'No active connections. Tap to check the node’s exit manually.',
        ),
      );
      await tester.pumpAndSettle();
      expect(exits.requests, hasLength(1));
      expect(find.text('🇺🇸'), findsOneWidget);
    },
  );

  testWidgets('DIRECT has no proxy exit and does not launch a check', (
    tester,
  ) async {
    store.addEvent(connection('direct').copyWith(chains: ['DIRECT']));
    await pump(tester, child: _targets);
    expect(
      find.byTooltip('No proxy exit for this connection.'),
      findsOneWidget,
    );
    expect(exits.requests, isEmpty);
  });

  testWidgets(
    'target picks its newest active connection before older retained paths',
    (tester) async {
      final active = connection('active', offset: 1);
      store
        ..addEvent(active)
        ..addEvent(
          connection('newer-ended', offset: 2, server: '114.114.114.114'),
        );
      store.applySnapshot([active], startedRevision: store.revision, now: now);
      await pump(tester, child: _targets);
      expect(find.text('🇺🇸'), findsOneWidget);
      expect(exits.requests.single.entry, '8.8.8.8');
      expect(
        tester
            .widget<ConnectionExitIcon>(find.byType(ConnectionExitIcon))
            .info
            .id,
        'active',
      );
    },
  );

  testWidgets(
    'connections stay separate and show frozen routes, latest bytes and measured exits',
    (tester) async {
      final a = connection('8c71f2a9-1111', offset: 1);
      final b = connection(
        '8c71f2aa-2222',
        offset: 2,
        server: '114.114.114.114',
        exit: 'Other node',
      );
      store
        ..addEvent(a)
        ..addEvent(b)
        ..addEvent(connection('other-app', package: 'test.app.b'));
      store.applySnapshot(
        [a.copyWith(upload: 12288, download: 333824)],
        startedRevision: store.revision,
        now: now,
      );
      await pump(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(a.start.showFull), findsOneWidget);
      expect(find.text('#8c71f2a9'), findsNothing);
      expect(find.text(b.start.showFull), findsOneWidget);
      expect(row('other-app'), findsNothing);
      expect(find.text('Proxy → US 01'), findsOneWidget);
      expect(find.text('Proxy → Other node'), findsOneWidget);
      expect(find.text('↑ 12KB   ↓ 326KB'), findsOneWidget);
      expect(timestampStyle(tester, a.id).fontWeight, FontWeight.w600);
      expect(timestampStyle(tester, b.id).fontWeight, FontWeight.normal);
      expect(find.text('🇺🇸'), findsOneWidget);
      expect(find.text('🇨🇳'), findsNothing);
      expect(find.text('🇯🇵'), findsNothing);
      expect(exits.requests, hasLength(1));
      expect(
        find.byTooltip(
          'Measured exit: 8.210.0.1 · US\nChecked: 2026-11-13 14:33:00\nTap to check again. Other destinations may use a different exit.',
        ),
        findsOneWidget,
      );
      expect(find.byType(ExpansionTile), findsNothing);
      await screenshot(tester, 'host-connections');
      await tester.tap(find.text('Proxy → US 01'));
      await tester.pumpAndSettle();
      expect(find.byType(TrackerInfoDetailView), findsOneWidget);
      final detail = tester
          .widget<TrackerInfoDetailView>(find.byType(TrackerInfoDetailView))
          .trackerInfo;
      expect(detail.id, a.id);
      expect(detail.upload, 12288);
      expect(detail.download, 333824);
      expect(detail.metadata, a.metadata);
      expect(detail.chains, a.chains);
    },
  );

  testWidgets(
    'cross-app scope and filtering do not mix identities or lose return context',
    (tester) async {
      final a = connection('a');
      final b = connection('b', package: 'test.app.b');
      store
        ..addEvent(a)
        ..addEvent(b);
      store.applySnapshot([a], startedRevision: store.revision, now: now);
      await pump(tester);
      await menu(tester, 'All apps for this target');
      expect(row('a'), findsOneWidget);
      expect(row('b'), findsOneWidget);
      expect(find.text('Mail B'), findsOneWidget);
      await menu(tester, 'Only show active connections');
      expect(row('b'), findsNothing);
      store.markUncertain(failed: true);
      notifier.replace(store.snapshot());
      await tester.pumpAndSettle();
      expect(row('b'), findsOneWidget);
      expect(
        find.text('Active state is unconfirmed. Showing retained connections.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(notifier.refreshes, 1);
      expect(timestampStyle(tester, 'a').fontWeight, FontWeight.normal);
    },
  );

  testWidgets('target tap enters connections, return retains target search', (
    tester,
  ) async {
    store
      ..addEvent(connection('a'))
      ..addEvent(activityConnection('unrelated', host: 'other.test'));
    await pump(
      tester,
      child: const ApplicationTargetsView(
        appKey: 'package:test.app.a',
        label: 'Browser A',
      ),
    );
    await tester.enterText(find.byType(TextField), 'example');
    await tester.pumpAndSettle();
    await tester.tap(find.text('example.test'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationConnectionsView), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'example',
    );
    expect(find.text('other.test'), findsNothing);
  });

  for (final reason in ['stopped', 'cleared', 'runtime']) {
    testWidgets('retained connection lifecycle: $reason', (tester) async {
      final a = connection('a');
      store
        ..addEvent(a)
        ..applySnapshot([a], startedRevision: store.revision, now: now);
      await pump(tester);
      if (reason == 'stopped') {
        store.setContext('runtime-a', observing: false, now: now);
      } else if (reason == 'cleared') {
        store.clear(now);
      } else {
        store.setContext('runtime-b', observing: true, now: now);
      }
      notifier.replace(store.snapshot());
      await tester.pumpAndSettle();
      if (reason == 'stopped') {
        expect(row('a'), findsOneWidget);
        expect(timestampStyle(tester, 'a').fontWeight, FontWeight.normal);
      } else {
        expect(row('a'), findsNothing);
        expect(find.text('No activity observed yet'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'DIRECT, unknown server and failed country lookup never borrow destination countries',
    (tester) async {
      final direct = connection(
        'direct',
        exit: 'DIRECT',
      ).copyWith(chains: ['DIRECT']);
      store
        ..addEvent(direct)
        ..addEvent(connection('hostname', server: 'proxy.test'));
      core.fail = true;
      await pump(tester);
      expect(find.text('🇺🇸'), findsNothing);
      expect(find.text('🇯🇵'), findsNothing);
      expect(core.calls, isEmpty);
    },
  );

  testWidgets(
    'country query failure keeps connection content visible without a flag',
    (tester) async {
      store.addEvent(connection('available'));
      core.fail = true;
      await pump(tester);
      expect(row('available'), findsOneWidget);
      expect(find.text('🇺🇸'), findsNothing);
      expect(exits.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared details retain the selected connection and use latest observed counters on reopening',
    (tester) async {
      final a = connection('original', offset: 1);
      store.addEvent(a);
      await pump(tester);
      await tester.tap(row(a.id));
      await tester.pumpAndSettle();
      expect(find.byType(TrackerInfoDetailView), findsOneWidget);
      final b = connection('new', offset: 2);
      store.addEvent(b);
      store.applySnapshot(
        [
          a.copyWith(upload: 2048, chains: ['Changed node']),
          b,
        ],
        startedRevision: store.revision,
        now: now,
      );
      notifier.replace(store.snapshot());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TrackerInfoDetailView>(find.byType(TrackerInfoDetailView))
            .trackerInfo
            .id,
        a.id,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('↑ 2KB   ↓ 0B'), findsOneWidget);
      expect(find.text(a.start.showFull), findsOneWidget);
      expect(find.text(b.start.showFull), findsOneWidget);
      await tester.tap(row(a.id));
      await tester.pumpAndSettle();
      final detail = tester
          .widget<TrackerInfoDetailView>(find.byType(TrackerInfoDetailView))
          .trackerInfo;
      expect(detail.id, a.id);
      expect(detail.upload, 2048);
      expect(detail.chains, a.chains);
      expect(detail.metadata.sourcePort, '30001');
      expect(exits.requests, hasLength(1));
    },
  );

  testWidgets('observed address copy reports clipboard failure and can retry', (
    tester,
  ) async {
    store.addEvent(connection('12345678-complete-id'));
    var fail = true;
    final copied = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (fail) throw PlatformException(code: 'unavailable');
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pump(tester);
    await tester.tap(find.text('192.0.2.1:443'));
    await tester.pumpAndSettle();
    expect(find.textContaining('copy to the clipboard'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('192.0.2.1:443'));
    await tester.pumpAndSettle();
    expect(copied, ['192.0.2.1:443']);
  });

  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ru'),
  ]) {
    testWidgets('target country layout supports narrow large text in $locale', (
      tester,
    ) async {
      store.addEvent(
        connection('latest', exit: 'A very long proxy group name'),
      );
      await pump(
        tester,
        child: _targets,
        width: 320,
        scale: 1.7,
        locale: locale,
      );
      expect(find.text('🇺🇸'), findsOneWidget);
      expect(find.text('example.test'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'target-country-${locale.languageCode}');
    });

    testWidgets('connections support narrow large text in $locale', (
      tester,
    ) async {
      store.addEvent(
        connection(
          '12345678-long-id',
          exit: 'A very long proxy group name',
          server: '114.114.114.114',
        ),
      );
      await pump(tester, width: 320, scale: 1.7, locale: locale);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'host-connections-${locale.languageCode}');
      await tester.tap(find.textContaining('A very long proxy group name'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'server-address candidates reject direct, private, hostnames and the target itself',
    () {
      expect(connectionProxyServerIp(connection('proxy')), '8.8.8.8');
      expect(
        connectionProxyServerIp(connection('private', server: '192.168.1.1')),
        isNull,
      );
      expect(
        connectionProxyServerIp(connection('name', server: 'node.test')),
        isNull,
      );
      expect(
        connectionProxyServerIp(connection('direct', exit: 'DIRECT')),
        isNull,
      );
      final target = connection('same').copyWith(
        metadata: const Metadata(
          remoteDestination: '8.8.8.8',
          destinationIP: '8.8.8.8',
        ),
      );
      expect(connectionProxyServerIp(target), isNull);
    },
  );
}
