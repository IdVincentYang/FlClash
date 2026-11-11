import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/application_activity.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/application_activity.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fl_clash/common/shape.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/application_activity.dart';
import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';

class _Activity extends ApplicationActivity {
  _Activity(this.value);
  final ApplicationActivityState value;
  @override
  ApplicationActivityState build() => value;
  void replace(ApplicationActivityState next) => state = next;
  @override
  Future<void> refresh() async {}
}

const _packages = [
  Package(
    packageName: 'test.app.a',
    label: 'Browser A',
    system: false,
    internet: true,
    lastUpdateTime: 0,
  ),
  Package(
    packageName: 'test.app.b',
    label: 'Mail B',
    system: false,
    internet: true,
    lastUpdateTime: 0,
  ),
];

ApplicationActivityState _activity({
  bool stopped = false,
  bool failed = false,
}) {
  final store = ApplicationActivityStore();
  final now = DateTime.utc(2026, 11, 11, 2);
  store.setContext('runtime-a', observing: true, now: now);
  final info = activityConnection('one');
  store.addEvent(info);
  store.addEvent(activityConnection('two', exit: 'node-b'));
  store.applySnapshot([info], startedRevision: store.revision, now: now);
  if (stopped) store.setContext('runtime-a', observing: false, now: now);
  if (failed) store.markUncertain(failed: true);
  return store.snapshot();
}

void main() {
  final fontPath = Platform.environment['FLCLASH_ACTIVITY_FONT'];
  setUpAll(() async {
    if (fontPath == null) return;
    final loader = FontLoader('ActivityPreview')
      ..addFont(
        Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())),
      );
    await loader.load();
  });
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    ApplicationActivityState? activity,
    bool catalogueError = false,
    bool catalogueLoading = false,
    Widget child = const ApplicationActivityView(),
    double width = 420,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        applicationActivityProvider.overrideWith(
          () => _Activity(activity ?? _activity()),
        ),
        applicationCatalogueProvider.overrideWith((_) async {
          if (catalogueError) throw StateError('catalogue failed');
          if (catalogueLoading) {
            return Future<ApplicationCatalogue>.delayed(
              const Duration(minutes: 1),
              () => const ApplicationCatalogue(packages: [], accessible: false),
            );
          }
          return const ApplicationCatalogue(
            packages: _packages,
            accessible: true,
          );
        }),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          homeBuilder: (widget) => Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: const ValueKey('activity-capture'),
                child: Theme(
                  data: fontPath == null
                      ? Theme.of(context)
                      : Theme.of(context)
                            .copyWith(
                              textTheme: Theme.of(
                                context,
                              ).textTheme.apply(fontFamily: 'ActivityPreview'),
                              primaryTextTheme: Theme.of(context)
                                  .primaryTextTheme
                                  .apply(fontFamily: 'ActivityPreview'),
                            )
                            .withAppShapes,
                  child: widget,
                ),
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    final directory = Platform.environment['FLCLASH_ACTIVITY_SCREENSHOTS'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('activity-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(directory).createSync(recursive: true);
      File(
        '$directory/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Tools opens the read-only page while the proxy is stopped', (
    tester,
  ) async {
    await pump(
      tester,
      activity: _activity(stopped: true),
      child: const ToolsView(isAndroid: true),
    );
    await tester.tap(find.text('Application network'));
    await tester.pumpAndSettle();
    expect(find.text('Observation paused · retained activity'), findsOneWidget);
    expect(find.text('Browser A'), findsOneWidget);
    expect(find.text('Active Unconfirmed · Observed 2'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tools'), findsOneWidget);
  });

  testWidgets(
    'search and filters retain activity and show unobserved installed apps',
    (tester) async {
      await pump(tester);
      expect(find.text('Active 1 · Observed 2'), findsOneWidget);
      await tester.tap(find.text('All apps'));
      await tester.pumpAndSettle();
      expect(find.text('Mail B'), findsOneWidget);
      await tester.tap(find.byTooltip('Search').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mail');
      await tester.pumpAndSettle();
      expect(find.text('Mail B'), findsOneWidget);
      expect(find.text('Browser A'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching apps'), findsOneWidget);
    },
  );

  testWidgets(
    'row expansion shows actual paths and current settings without edits',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Browser A'));
      await tester.pumpAndSettle();
      expect(find.text('Observed exit paths (2)'), findsOneWidget);
      expect(find.text('node-b → Proxy'), findsOneWidget);
      expect(find.text('Current settings: include this app'), findsOneWidget);
      expect(
        find.text('VPN capture observed for these connections'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
      await screenshot(tester, 'expanded');
    },
  );

  testWidgets('catalogue failure leaves activity visible and provides retry', (
    tester,
  ) async {
    await pump(tester, catalogueError: true);
    expect(find.text('test.app.a'), findsOneWidget);
    expect(
      find.text('App directory unavailable; observed activity is still shown.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('test.app.a'), findsOneWidget);
  });

  testWidgets('snapshot failure is distinct from empty or zero active data', (
    tester,
  ) async {
    await pump(tester, activity: _activity(failed: true));
    expect(
      find.text('Could not refresh · active state unconfirmed'),
      findsOneWidget,
    );
    expect(find.text('Active Unconfirmed · Observed 2'), findsOneWidget);
    await screenshot(tester, 'snapshot-failed');
  });

  testWidgets(
    'empty activity is immediately readable without an endless spinner',
    (tester) async {
      await pump(tester, activity: const ApplicationActivityState());
      expect(find.text('No activity observed yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Active now'));
      await tester.pumpAndSettle();
      expect(find.text('No confirmed active connections'), findsOneWidget);
    },
  );

  testWidgets('shared identities remain separate from their candidate apps', (
    tester,
  ) async {
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: DateTime.now());
    store.addEvent(
      activityConnection(
        'shared',
        status: 'ambiguous',
        candidates: ['test.app.a', 'test.app.b'],
      ),
    );
    await pump(tester, activity: store.snapshot());
    expect(find.text('Shared application identity'), findsOneWidget);
    expect(find.text('Browser A'), findsNothing);
    await tester.tap(find.text('Shared application identity'));
    await tester.pumpAndSettle();
    expect(find.text('test.app.a\ntest.app.b'), findsOneWidget);
  });

  testWidgets(
    'expanded rows follow app identity when recent activity reorders them',
    (tester) async {
      final now = DateTime.utc(2026, 11, 11, 2);
      final store = ApplicationActivityStore()
        ..setContext('runtime-a', observing: true, now: now);
      store.addEvent(activityConnection('a', start: now));
      store.addEvent(
        activityConnection(
          'b',
          package: 'test.app.b',
          uid: 10002,
          start: now.add(const Duration(seconds: 1)),
        ),
      );
      await pump(tester, activity: store.snapshot());
      await tester.tap(find.text('Mail B'));
      await tester.pumpAndSettle();
      store.addEvent(
        activityConnection('new-a', start: now.add(const Duration(seconds: 2))),
      );
      (container.read(applicationActivityProvider.notifier) as _Activity)
          .replace(store.snapshot());
      await tester.pumpAndSettle();
      ExpansionTile tile(String label) => tester.widget<ExpansionTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(ExpansionTile),
        ),
      );
      expect(tile('Mail B').controller!.isExpanded, true);
      expect(tile('Browser A').controller!.isExpanded, false);
    },
  );

  testWidgets('narrow screens and large text keep content scrollable', (
    tester,
  ) async {
    await pump(tester, width: 320, scale: 2);
    expect(tester.takeException(), null);
    await tester.tap(find.text('Browser A'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await screenshot(tester, 'narrow-large-text');
  });
}
