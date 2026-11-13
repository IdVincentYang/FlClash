import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/application_activity.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/application_activity.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/widgets/popup.dart';
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
  int refreshCount = 0;
  void replace(ApplicationActivityState next) => state = next;
  @override
  Future<void> refresh() async {
    refreshCount++;
  }
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
    Locale? locale,
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
          locale: locale,
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

  Finder summary(String prefix) => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.textSpan?.toPlainText().startsWith(prefix) ?? false),
  );

  Future<void> toggleAll(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all apps'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Tools opens retained activity with an inline search while stopped',
    (tester) async {
      await pump(
        tester,
        activity: _activity(stopped: true),
        child: const ToolsView(isAndroid: true),
      );
      await tester.tap(find.text('Application network'));
      await tester.pumpAndSettle();
      expect(find.text('Observation paused · retained activity'), findsNothing);
      expect(find.text('Browser A'), findsOneWidget);
      expect(summary('Active —/2'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Tools'), findsOneWidget);
    },
  );

  testWidgets(
    'normal chrome has only the menu and the persistent search field',
    (tester) async {
      await pump(tester);
      expect(find.byTooltip('More'), findsOneWidget);
      expect(find.byTooltip('Search'), findsNothing);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.byTooltip('Observation scope'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Observing VPN activity'), findsNothing);
      expect(
        find.text('This run · latest 4096 observed connections'),
        findsNothing,
      );
      expect(find.text('Search app name or package'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        lessThan(tester.getTopLeft(find.text('Browser A')).dy),
      );
    },
  );

  testWidgets(
    'all-app menu preserves the search and clear restores recent apps',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Mail');
      await tester.pumpAndSettle();
      expect(find.text('No matching apps'), findsOneWidget);
      await toggleAll(tester);
      expect(find.text('Mail B'), findsOneWidget);
      expect(find.text('Browser A'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mail',
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CommonPopupMenu>(find.byType(CommonPopupMenu))
            .items
            .single
            .checked,
        true,
      );
      await tester.tap(find.text('Show all apps'));
      await tester.pumpAndSettle();
      expect(find.text('No matching apps'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Browser A'), findsOneWidget);
      expect(find.text('Mail B'), findsNothing);
      await tester.enterText(find.byType(TextField), 'test.app.a');
      await tester.pumpAndSettle();
      expect(find.text('Browser A'), findsOneWidget);
    },
  );

  testWidgets('activity updates preserve typed search and keyboard focus', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Browser');
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(focus.hasFocus, true);
    (container.read(applicationActivityProvider.notifier) as _Activity).replace(
      _activity(stopped: true),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Browser',
    );
    expect(focus.hasFocus, true);
    expect(find.text('Browser A'), findsOneWidget);
    expect(summary('Active —/2'), findsOneWidget);
  });

  testWidgets(
    'active count is emphasized and active apps precede newer idle apps',
    (tester) async {
      final now = DateTime.now();
      final store = ApplicationActivityStore()
        ..setContext('runtime-a', observing: true, now: now);
      final a = activityConnection(
        'a',
        start: now.subtract(const Duration(minutes: 2)),
      );
      final b = activityConnection(
        'b',
        package: 'test.app.b',
        uid: 10002,
        start: now,
      );
      store.addEvent(a);
      store.addEvent(b);
      store.applySnapshot([a], startedRevision: store.revision, now: now);
      await pump(tester, activity: store.snapshot());
      expect(
        tester.getTopLeft(find.text('Browser A')).dy,
        lessThan(tester.getTopLeft(find.text('Mail B')).dy),
      );
      final active = tester.widget<Text>(summary('Active 1/1'));
      final activeSpan = (active.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.style != null);
      final idle = tester.widget<Text>(summary('Active 0/1'));
      final idleSpan = (idle.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.style != null);
      final theme = Theme.of(tester.element(find.text('Browser A')));
      expect(active.semanticsLabel, contains('Active 1 · Observed 1'));
      expect(activeSpan.text, '1');
      expect(activeSpan.style!.color, theme.colorScheme.primary);
      expect(activeSpan.style!.fontWeight, FontWeight.w600);
      expect(idleSpan.text, '0');
      expect(idleSpan.style!.color, theme.colorScheme.onSurfaceVariant);
      expect(idleSpan.style!.fontWeight, FontWeight.normal);
      expect(find.text('Last activity: Just now'), findsNothing);
      expect(idle.textSpan!.toPlainText(), endsWith(' · Just now'));
      expect(tester.getSize(summary('Active 0/1')).height, lessThan(24));
      final tile = find.ancestor(
        of: find.text('Browser A'),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(tile).height, lessThanOrEqualTo(88));
      await screenshot(tester, 'compact-activity');
    },
  );

  testWidgets('rows remain summary-only without expansion or status badges', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Browser A'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(Chip), findsNothing);
    expect(find.text('Observed exit paths (2)'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(summary('Active 1/2'), findsOneWidget);
  });

  testWidgets('observation gaps have no persistent warning', (tester) async {
    final initial = _activity();
    await pump(
      tester,
      activity: ApplicationActivityState(
        connections: initial.connections,
        observing: true,
        hasSnapshot: true,
        interrupted: true,
        truncated: true,
      ),
    );
    expect(find.text('Observation has gaps'), findsNothing);
    expect(summary('Active 1/2'), findsOneWidget);
  });

  testWidgets('unknown identity uses an application placeholder', (
    tester,
  ) async {
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: DateTime.now());
    store.addEvent(activityConnection('unknown', status: 'notObserved'));
    await pump(tester, activity: store.snapshot());
    expect(find.text('Unknown app'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GlyphIcon && widget.glyph == AppGlyphs.application,
      ),
      findsOneWidget,
    );
    expect(summary('Active —/1'), findsOneWidget);
  });

  testWidgets('catalogue failure leaves observed apps searchable with retry', (
    tester,
  ) async {
    await pump(tester, catalogueError: true);
    expect(find.text('test.app.a'), findsOneWidget);
    expect(
      find.text('App directory unavailable; observed activity is still shown.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'test.app.a');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'test.app.a'), findsOneWidget);
  });

  testWidgets('connection failures offer retry without showing a false zero', (
    tester,
  ) async {
    await pump(tester, activity: _activity(failed: true));
    expect(
      find.text('Could not refresh · active state unconfirmed'),
      findsOneWidget,
    );
    expect(summary('Active —/2'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(
      (container.read(applicationActivityProvider.notifier) as _Activity)
          .refreshCount,
      1,
    );
    await screenshot(tester, 'connection-failed');
  });

  testWidgets('empty activity still offers search and all installed apps', (
    tester,
  ) async {
    await pump(tester, activity: const ApplicationActivityState());
    expect(find.text('No activity observed yet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    await toggleAll(tester);
    expect(find.text('Browser A'), findsOneWidget);
    expect(find.text('Mail B'), findsOneWidget);
  });

  testWidgets('shared identities stay separate from candidate apps', (
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
  });

  testWidgets('reordered summaries retain the correct counts', (tester) async {
    final now = DateTime.now();
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
    store.addEvent(
      activityConnection('new-a', start: now.add(const Duration(seconds: 2))),
    );
    (container.read(applicationActivityProvider.notifier) as _Activity).replace(
      store.snapshot(),
    );
    await tester.pumpAndSettle();
    final browser = find.ancestor(
      of: find.text('Browser A'),
      matching: find.byType(ListTile),
    );
    final mail = find.ancestor(
      of: find.text('Mail B'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: browser, matching: summary('Active —/2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mail, matching: summary('Active —/1')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(browser).dy, lessThan(tester.getTopLeft(mail).dy));
  });

  testWidgets('narrow large-text layout stays usable with the keyboard open', (
    tester,
  ) async {
    await pump(tester, width: 320, scale: 2);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'test.app.a');
    await tester.pump();
    expect(tester.takeException(), null);
    expect(find.text('Browser A'), findsOneWidget);
    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThan(600));
    await screenshot(tester, 'narrow-large-text');
  });

  for (final locale in const [Locale('zh', 'CN'), Locale('ja'), Locale('ru')]) {
    testWidgets('localized compact counts retain their styled value $locale', (
      tester,
    ) async {
      await pump(tester, locale: locale, width: 360);
      expect(tester.takeException(), null);
      final texts = tester.widgetList<Text>(find.byType(Text));
      final stats = texts.singleWhere((text) => text.textSpan != null);
      expect(stats.textSpan!.toPlainText(), isNot(contains('{active}')));
      final numeric = (stats.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.style != null);
      expect(numeric.text, '1');
      expect(numeric.style!.fontWeight, FontWeight.w600);
      await screenshot(tester, 'locale-${locale.languageCode}');
    });
  }
}
