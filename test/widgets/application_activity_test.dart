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
import 'package:fl_clash/views/application_targets.dart';
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
      final entry = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Application network'),
          matching: find.byType(ListTile),
        ),
      );
      expect((entry.leading! as GlyphIcon).glyph, AppGlyphs.application);
      expect(
        (entry.subtitle! as Text).data,
        'View app connections, matching rules and exits',
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

  const targetsPage = ApplicationTargetsView(
    appKey: 'package:test.app.a',
    label: 'Browser A',
    packageName: 'test.app.a',
  );

  Future<void> activeTargets(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only show active targets'));
    await tester.pumpAndSettle();
  }

  testWidgets('application rows open targets and preserve the parent search', (
    tester,
  ) async {
    await pump(tester);
    await toggleAll(tester);
    await tester.enterText(find.byType(TextField), 'Browser');
    await tester.tap(find.text('Browser A'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationTargetsView), findsOneWidget);
    expect(find.text('example.test'), findsOneWidget);
    expect(find.text('test.app.a · UID 10001'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationTargetsView), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Browser',
    );
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Mail B'), findsOneWidget);
  });

  testWidgets('a directory-only application opens an empty target page', (
    tester,
  ) async {
    await pump(tester);
    await toggleAll(tester);
    await tester.tap(find.text('Mail B'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationTargetsView), findsOneWidget);
    expect(find.text('No activity observed yet'), findsOneWidget);
    expect(find.text('test.app.b'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      (container.read(applicationActivityProvider.notifier) as _Activity)
          .refreshCount,
      0,
    );
  });

  testWidgets('targets aggregate this app only and keep actual route pairs', (
    tester,
  ) async {
    final now = DateTime.now();
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: now);
    final a = activityConnection('a', host: 'EXAMPLE.test.');
    final b = activityConnection(
      'b',
      exit: 'node-b',
    ).copyWith(rule: 'RuleSet', rulePayload: 'Domestic');
    store.addEvent(a);
    store.addEvent(b);
    store.addEvent(
      activityConnection(
        'c',
        package: 'test.app.b',
        uid: 10002,
        host: 'mail.test',
      ),
    );
    store.applySnapshot([a], startedRevision: store.revision, now: now);
    await pump(tester, activity: store.snapshot(), child: targetsPage);
    expect(find.text('example.test'), findsOneWidget);
    expect(find.text('mail.test'), findsNothing);
    expect(summary('Active 1/2'), findsOneWidget);
    expect(find.text('2 rule results · 2 exit paths'), findsOneWidget);
    await tester.tap(find.text('example.test'));
    await tester.pumpAndSettle();
    expect(find.text('Domain · EXAMPLE.test.'), findsOneWidget);
    expect(find.text('RuleSet · Domestic'), findsOneWidget);
    expect(find.text('node-a → Proxy'), findsOneWidget);
    expect(find.text('node-b → Proxy'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    await screenshot(tester, 'targets-routes');
  });

  testWidgets(
    'targets prioritize active hosts and search without losing focus',
    (tester) async {
      final now = DateTime.now();
      final store = ApplicationActivityStore()
        ..setContext('runtime-a', observing: true, now: now);
      final a = activityConnection('a', host: 'active.test');
      store.addEvent(a);
      store.addEvent(activityConnection('b', host: 'recent.test', start: now));
      store.applySnapshot([a], startedRevision: store.revision, now: now);
      await pump(tester, activity: store.snapshot(), child: targetsPage);
      expect(
        tester.getTopLeft(find.text('active.test')).dy,
        lessThan(tester.getTopLeft(find.text('recent.test')).dy),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'active');
      store.addEvent(activityConnection('new', host: 'active.test'));
      (container.read(applicationActivityProvider.notifier) as _Activity)
          .replace(store.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('recent.test'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'active',
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('recent.test'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('recent.test'), findsOneWidget);
      expect(
        find.text('Active state is unconfirmed. Showing retained targets.'),
        findsNothing,
      );
      // The newly observed connection is not yet confirmed by a snapshot.
      expect(find.text('Only show active targets'), findsOneWidget);
    },
  );

  testWidgets('active filtering falls back to retained targets after failure', (
    tester,
  ) async {
    final now = DateTime.now();
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: now);
    final a = activityConnection('a');
    store.addEvent(a);
    store.addEvent(activityConnection('idle', host: 'idle.test'));
    store.applySnapshot([a], startedRevision: store.revision, now: now);
    await pump(tester, activity: store.snapshot(), child: targetsPage);
    await activeTargets(tester);
    expect(find.text('idle.test'), findsNothing);
    store.markUncertain(failed: true);
    final notifier =
        container.read(applicationActivityProvider.notifier) as _Activity;
    notifier.replace(store.snapshot());
    await tester.pumpAndSettle();
    expect(find.text('idle.test'), findsOneWidget);
    expect(summary('Active —/1'), findsNWidgets(2));
    expect(
      find.text('Active state is unconfirmed. Showing retained targets.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(notifier.refreshCount, 1);
  });

  testWidgets(
    'shared identity exposes candidates without selecting a package',
    (tester) async {
      final shared = activityConnection(
        'shared',
        status: 'ambiguous',
        candidates: ['test.app.a', 'test.app.b'],
      );
      final store = ApplicationActivityStore()
        ..setContext('runtime-a', observing: true, now: DateTime.now())
        ..addEvent(shared);
      await pump(tester, activity: store.snapshot());
      await tester.tap(find.text('Shared application identity'));
      await tester.pumpAndSettle();
      expect(find.text('UID 10001'), findsOneWidget);
      expect(find.text('Browser A'), findsOneWidget);
      expect(find.text('Mail B'), findsOneWidget);
      expect(find.text('test.app.a'), findsOneWidget);
      expect(find.text('test.app.b'), findsOneWidget);
      expect(find.text('example.test'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await pump(
        tester,
        activity: store.snapshot(),
        child: ApplicationTargetsView(
          appKey: store.snapshot().apps.single.key,
          label: 'Shared application identity',
          identity: shared.observation!.application,
        ),
      );
      await screenshot(tester, 'targets-shared');
    },
  );

  testWidgets(
    'IP and unknown targets remain distinct with a missing directory',
    (tester) async {
      final store = ApplicationActivityStore()
        ..setContext('runtime-a', observing: true, now: DateTime.now());
      for (final ip in ['192.0.2.1', '2001:db8::1', '']) {
        store.addEvent(activityConnection(ip, host: '', ip: ip));
      }
      await pump(
        tester,
        activity: store.snapshot(),
        child: targetsPage,
        catalogueError: true,
      );
      expect(find.text('192.0.2.1'), findsOneWidget);
      expect(find.text('2001:db8::1'), findsOneWidget);
      expect(find.text('Unknown target'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2001:db8');
      await tester.pumpAndSettle();
      expect(find.text('2001:db8::1'), findsOneWidget);
      expect(find.text('192.0.2.1'), findsNothing);
    },
  );

  testWidgets('targets remain after stopping and clear with a new runtime', (
    tester,
  ) async {
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: DateTime.now())
      ..addEvent(activityConnection('a'));
    await pump(tester, activity: store.snapshot(), child: targetsPage);
    store.setContext('runtime-a', observing: false, now: DateTime.now());
    final notifier =
        container.read(applicationActivityProvider.notifier) as _Activity;
    notifier.replace(store.snapshot());
    await tester.pumpAndSettle();
    expect(find.text('example.test'), findsOneWidget);
    expect(summary('Active —/1'), findsOneWidget);
    store.setContext('runtime-b', observing: true, now: DateTime.now());
    notifier.replace(store.snapshot());
    await tester.pumpAndSettle();
    expect(find.text('example.test'), findsNothing);
    expect(find.text('No activity observed yet'), findsOneWidget);
  });

  testWidgets(
    'expanded route results survive live updates and list reordering',
    (tester) async {
      final now = DateTime.now();
      final store = ApplicationActivityStore()
        ..setContext('runtime-a', observing: true, now: now)
        ..addEvent(activityConnection('a'));
      await pump(tester, activity: store.snapshot(), child: targetsPage);
      await tester.tap(find.text('example.test'));
      await tester.pumpAndSettle();
      store.addEvent(activityConnection('new', host: 'new.test', start: now));
      (container.read(applicationActivityProvider.notifier) as _Activity)
          .replace(store.snapshot());
      await tester.pumpAndSettle();
      expect(find.text('node-a → Proxy'), findsOneWidget);
      expect(find.text('new.test'), findsOneWidget);
    },
  );

  testWidgets('target empty search and large text do not overflow', (
    tester,
  ) async {
    await pump(tester, child: targetsPage, width: 320, scale: 2);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'not-present');
    await tester.pumpAndSettle();
    expect(find.text('No matching targets'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('example.test'), findsOneWidget);
    expect(tester.takeException(), null);
    await screenshot(tester, 'targets-large-text');
  });

  testWidgets('unknown identity stays unknown and cannot borrow an app name', (
    tester,
  ) async {
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: DateTime.now())
      ..addEvent(
        activityConnection('unknown', status: 'lookupFailed', candidates: []),
      );
    await pump(tester, activity: store.snapshot());
    await tester.tap(find.text('Unknown app'));
    await tester.pumpAndSettle();
    expect(find.text('Unknown app'), findsOneWidget);
    expect(find.text('Browser A'), findsNothing);
    expect(find.text('example.test'), findsOneWidget);
    expect(
      find.textContaining('Application could not be identified'),
      findsOneWidget,
    );
  });

  testWidgets('a bypassed rule needs frozen configuration evidence', (
    tester,
  ) async {
    final original = activityConnection('global');
    final global = original.copyWith(
      rule: '',
      rulePayload: '',
      observation: original.observation!.copyWith(
        configuration: const ConnectionConfiguration(
          status: 'known',
          mode: 'global',
        ),
      ),
    );
    final unknown = activityConnection('unknown', host: 'unknown.test')
        .copyWith(
          rule: '',
          rulePayload: '',
          observation: original.observation!.copyWith(
            configuration: const ConnectionConfiguration(mode: 'global'),
          ),
        );
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: DateTime.now())
      ..addEvent(global)
      ..addEvent(unknown);
    await pump(tester, activity: store.snapshot(), child: targetsPage);
    expect(
      find.textContaining('Rules bypassed in Global or Direct mode'),
      findsOneWidget,
    );
    expect(find.text('Unknown · node-a → Proxy'), findsOneWidget);
  });

  testWidgets('returning from a target page preserves parent scroll position', (
    tester,
  ) async {
    final store = ApplicationActivityStore()
      ..setContext('runtime-a', observing: true, now: DateTime.now());
    for (var i = 0; i < 30; i++) {
      store.addEvent(
        activityConnection(
          'app-$i',
          package: 'test.app.$i',
          uid: 11000 + i,
          start: DateTime(2026, 11, 11, 1, i),
        ),
      );
    }
    await pump(tester, activity: store.snapshot());
    final list = find.byKey(const PageStorageKey('application-network'));
    await tester.scrollUntilVisible(
      find.text('test.app.15'),
      250,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    final before = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    await tester.tap(find.text('test.app.15'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationTargetsView), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(after, before);
  });

  for (final locale in const [Locale('zh', 'CN'), Locale('ja'), Locale('ru')]) {
    testWidgets('target layout supports $locale', (tester) async {
      await pump(
        tester,
        child: targetsPage,
        locale: locale,
        width: 320,
        scale: 1.4,
      );
      expect(find.text('example.test'), findsOneWidget);
      expect(tester.takeException(), null);
      await screenshot(tester, 'targets-${locale.languageCode}');
    });
  }
}
