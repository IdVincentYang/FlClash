import 'dart:async';

import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/reports.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';
import '../helpers/test_database_providers.dart';
import '../helpers/test_profiles.dart';
import '../providers/reports_test.dart' show inventory, report;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.follow.clash/app');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late List<MethodCall> exports;

  setUp(() {
    exports = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'exportReport') {
        exports.add(call);
        return {'status': 'exported'};
      }
      if (call.method == 'cancelReportExport') return null;
      final args = call.arguments as Map;
      if (args['action'] == 'summary') {
        return {'status': 'ready', 'summary': report};
      }
      return inventory('one');
    });
    container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        profilesProvider.overrideWith(TestProfiles.new),
        scriptsProvider.overrideWith(TestScripts.new),
        globalRulesProvider.overrideWith(TestGlobalRules.new),
      ],
    );
    globalState.container = container;
  });

  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1000, 1400));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(locale: const Locale('en'), child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Tools opens reports with ordinary logging disabled', (
    tester,
  ) async {
    expect(container.read(appSettingProvider).openLogs, false);
    await show(tester, const ToolsView(isAndroid: true));
    await tester.scrollUntilVisible(
      find.text('Local crash reports'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Local crash reports'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportsView), findsOneWidget);
    expect(find.textContaining('Raw contents not verified'), findsOneWidget);
    expect(exports, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('detail preserves acquired Go ID alongside GNU identity', (
    tester,
  ) async {
    const go =
        'AbCdEfGhIjKlMnOpQrSt/_-0123456789AbCdEfGh/'
        'zyxwvutsrqponmlkjihg/ABCDEFGHabcdefgh0123';
    const gnu = '1234abcdef1234abcdef1234abcdef1234abcdef';
    final identity = {
      ...report,
      'libclash.so:go': go,
      'libclash.so:gnu': gnu,
      'unknown.so:go': 'PRIVATE_UNKNOWN_LIBRARY',
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      return (call.arguments as Map)['action'] == 'summary'
          ? {'status': 'ready', 'summary': identity}
          : {
              'status': 'ready',
              'revision': 'ids',
              'bytes': 100,
              'items': [
                {'token': 'ids', 'summary': identity},
              ],
            };
    });
    await show(tester, const ReportsView());
    await tester.tap(find.byKey(const ValueKey('ids')).first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('libclash.so:go: $go', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('libclash.so:gnu: $gnu', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('PRIVATE_UNKNOWN_LIBRARY', findRichText: true),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'raw warning cancel and summary confirmation use distinct kinds',
    (tester) async {
      await show(tester, const ReportsView());
      await tester.tap(find.byKey(const ValueKey('one')).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export raw report (ZIP)'));
      await tester.tap(find.text('Export raw report (ZIP)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('credentials, addresses', findRichText: true),
        findsOneWidget,
      );
      expect(exports, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(exports, isEmpty);
      await tester.tap(find.text('Export summary (JSON)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('sync to the cloud', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect((exports.single.arguments as Map)['kind'], 'summary');
      await tester.ensureVisible(find.text('Export raw report (ZIP)'));
      await tester.tap(find.text('Export raw report (ZIP)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect((exports.last.arguments as Map)['kind'], 'raw');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('provider failure shows fixed text; refresh can recover empty', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'private', message: 'SECRET_PATH');
    });
    await show(tester, const ReportsView());
    expect(find.textContaining('Operation failed'), findsOneWidget);
    expect(find.textContaining('0/20'), findsNothing);
    expect(find.textContaining('SECRET_PATH'), findsNothing);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => inventory('empty', empty: true),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No saved reports'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('delete confirmation preserves scope and allows cancel', (
    tester,
  ) async {
    var deleted = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      if (args['action'] == 'delete') {
        expect(args['revision'], 'one');
        expect(args['token'], 'one');
        expect(args['all'], isNull);
        deleted = true;
        return {'status': 'deleted'};
      }
      if (args['action'] == 'summary') {
        return {'status': 'ready', 'summary': report};
      }
      return inventory('one', empty: deleted);
    });
    await show(tester, const ReportsView());
    await tester.tap(find.byKey(const ValueKey('one')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('deduplication', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, false);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(deleted, true);
    expect(find.text('Selected reports deleted'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving the page revokes export and ignores its late reply', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object?>>();
    var cancelled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancelReportExport') {
        cancelled = true;
        return null;
      }
      if (call.method == 'exportReport') {
        exports.add(call);
        return pending.future;
      }
      return (call.arguments as Map)['action'] == 'summary'
          ? {'status': 'ready', 'summary': report}
          : inventory('one');
    });
    await show(tester, const ReportsView());
    await tester.tap(find.byKey(const ValueKey('one')).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export summary (JSON)'));
    await tester.tap(find.text('Export summary (JSON)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(exports, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancelled, true);
    pending.complete({'status': 'exported'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
