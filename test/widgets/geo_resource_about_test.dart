import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/resources.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';
import '../helpers/test_profiles.dart';

const _resources = {
  'MMDB': (
    description: 'MaxMind DB format',
    url: 'https://wiki.metacubex.one/en/config/general/#geo-data-mode',
  ),
  'ASN': (
    description: 'autonomous system numbers',
    url: 'https://dev.maxmind.com/geoip/docs/databases/asn/',
  ),
  'GEOIP': (
    description: '.dat database',
    url: 'https://wiki.metacubex.one/en/config/rules/#geoip',
  ),
  'GEOSITE': (
    description: 'Groups domain names',
    url: 'https://wiki.metacubex.one/en/config/rules/#geosite',
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late Object configBeforeAbout;
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  setUpAll(() async {
    home = await Directory.systemTemp.createTemp('flclash-geo-about-');
    AppPath.supportDirectory = () async => home;
    AppPath.temporaryDirectory = () async => home;
    AppPath.cacheDirectory = () async => home;
    SharedPreferences.setMockInitialValues({});
    await preferences.isInit;
  });

  tearDownAll(() async {
    await home.delete(recursive: true);
  });

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launch') {
            launched.add((call.arguments as Map)['url'] as String);
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<ProviderContainer> openAbout(
    WidgetTester tester,
    String resource, {
    Size size = const Size(480, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        profilesProvider.overrideWith(TestProfiles.new),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).update((_) => size);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ResourcesView()),
      ),
    );
    await tester.pumpAndSettle();
    configBeforeAbout = container.read(patchClashConfigProvider);
    final row = find.ancestor(
      of: find.text(resource),
      matching: find.byType(DecorationListItem),
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    return container;
  }

  for (final resource in _resources.entries) {
    testWidgets('${resource.key} explains its role without changing config', (
      tester,
    ) async {
      final container = await openAbout(tester, resource.key);
      expect(container.read(patchClashConfigProvider), configBeforeAbout);
      expect(find.text('${resource.key} · About'), findsOneWidget);
      expect(find.textContaining(resource.value.description), findsOneWidget);
      expect(find.text(resource.value.url), findsOneWidget);
      expect(launched, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('${resource.key} · About'), findsNothing);
      expect(container.read(patchClashConfigProvider), configBeforeAbout);
      expect(launched, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${resource.key} documentation keeps external-link confirmation',
      (tester) async {
        await openAbout(tester, resource.key);
        await tester.tap(find.text('Official documentation'));
        await tester.pumpAndSettle();
        expect(find.text('External link'), findsOneWidget);
        expect(find.text(resource.value.url), findsNWidgets(2));
        expect(launched, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('External link'), findsNothing);
        expect(find.text('${resource.key} · About'), findsOneWidget);
        expect(launched, isEmpty);
      },
    );
  }

  testWidgets('Go opens only the selected official documentation URL', (
    tester,
  ) async {
    await openAbout(tester, 'ASN');
    await tester.tap(find.text('Official documentation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(launched, [_resources['ASN']!.url]);
    expect(find.text('ASN · About'), findsOneWidget);
  });

  testWidgets('description and close stay usable with larger phone text', (
    tester,
  ) async {
    await openAbout(tester, 'GEOIP', size: const Size(360, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('GEOIP · About'), findsNothing);
  });
}
