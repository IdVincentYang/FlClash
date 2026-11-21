import 'dart:convert';

import 'package:dio/dio.dart'
    show HttpClientAdapter, RequestOptions, ResponseBody;
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';

const _runningVersion = '0.8.95';

const _payload =
    '{"schemaVersion":2,"versions":[{"version":"0.8.96","tag":"v0.8.96",'
    '"date":"2026-08-16","prerelease":false,"groups":['
    '{"type":"breaking","entries":[{"id":"af20769","text":'
    '"Re-import backups"}]},'
    '{"type":"feat","entries":[{"id":"1a2b3c4","text":'
    '"Override scripts"}]}]}]}';

const _bulletsOnly =
    '<!-- flclash:changelog:begin -->\n'
    '- Override scripts\n'
    '<!-- flclash:changelog:end -->\n';

String _bodyWith(String payload) =>
    '$_bulletsOnly\n<!-- flclash:changelog:json\n$payload\n-->\n';

Map<String, dynamic> release(String? body) => <String, dynamic>{
  'tag_name': 'v0.8.96',
  'body': body,
};

class _ReleaseAdapter implements HttpClientAdapter {
  String? body;
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode(release(body)),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<ProviderContainer> pumpApp(WidgetTester tester, {Locale? locale}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  // appSettingProvider is autoDispose; in the app `configProvider` keeps it
  // alive, so the test has to hold a listener or edits are dropped.
  container.listen(appSettingProvider, (_, _) {}, fireImmediately: true);
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1200, 800));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        locale: locale,
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// The dialog blocks until the user answers, so tests must close it before
/// awaiting the call that opened it.
Future<void> tapCancel(WidgetTester tester) async {
  await tester.tap(find.byType(TextButton).first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter originalAdapter;
  late _ReleaseAdapter adapter;
  Map<String, dynamic>? latest;
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  setUp(() {
    // This tests desktop result ownership; Android attached authorization has separate suites.
    expect(request.isAttached, isFalse);
    originalAdapter = request.dio.httpClientAdapter;
    adapter = _ReleaseAdapter();
    request.dio.httpClientAdapter = adapter;
    latest = null;
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          launched.add((call.arguments as Map)['url'] as String);
          return true;
        });
  });
  tearDown(() {
    if (latest != null) request.releaseVersionResult(latest!);
    request.cancelKey('versionCheck');
    request.dio.httpClientAdapter = originalAdapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<Map<String, dynamic>> loadRelease(
    WidgetTester tester,
    String? body,
  ) async {
    adapter.body = body;
    final data = await tester.runAsync(request.checkForUpdate);
    expect(data, isNotNull);
    latest = data!;
    return data;
  }

  final cancelled = throwsA(
    isA<RequestUnavailable>().having(
      (error) => error.code,
      'code',
      'request_cancelled',
    ),
  );
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: _runningVersion,
      buildNumber: '1',
    );
  });

  testWidgets('renders the grouped notes carried by the release', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final data = await loadRelease(tester, _bodyWith(_payload));
    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: data);
    await tester.pumpAndSettle();

    expect(find.textContaining('v0.8.96'), findsOneWidget);
    expect(find.textContaining('Re-import backups'), findsOneWidget);
    expect(find.textContaining('Override scripts'), findsOneWidget);
    expect(find.textContaining('Breaking changes'), findsOneWidget);

    await tapCancel(tester);
    await shown;
    await expectLater(request.validateVersionResult(data), cancelled);
    expect(launched, isEmpty);
  });

  testWidgets('localizes the group titles but not the entries', (tester) async {
    final container = await pumpApp(tester, locale: const Locale('zh', 'CN'));

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(
          data: await loadRelease(tester, _bodyWith(_payload)),
        );
    await tester.pumpAndSettle();

    // Entry copy comes from the release payload and is English only; the group
    // headings still follow the app locale.
    expect(find.textContaining('新功能'), findsOneWidget);
    expect(find.textContaining('Override scripts'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('falls back to the bullets of a release without a payload', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: await loadRelease(tester, _bulletsOnly));
    await tester.pumpAndSettle();

    expect(find.textContaining('- Override scripts'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  for (final _ in [false, true]) {}
}
