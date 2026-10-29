import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _Native extends Mock implements Service {}

class _Core extends Mock implements CoreHandlerInterface {}

class _Profiles extends ProfilesAction {
  _Profiles(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database store;
  late HttpServer server;
  late ProviderContainer container;
  late Request client;
  late MethodChannelMobileScanner channel;
  late MobileScannerPlatform original;
  late HttpOverrides? originalHttp;
  final calls = <MethodCall>[];
  final received = <Uri>[];
  const body = 'mode: rule\nrules: ["MATCH,DIRECT"]\n';

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qr-import-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
    globalState.packageInfo = PackageInfo(
      appName: 'fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
    );
  });
  tearDownAll(() => root.delete(recursive: true));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    originalHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    calls.clear();
    received.clear();
    store = Database(NativeDatabase.memory());
    database = store;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      received.add(request.uri);
      request.response.write(body);
      await request.response.close();
    });
    final core = _Core();
    when(() => core.validateConfig(any())).thenAnswer((invocation) async {
      expect(
        await File(
          invocation.positionalArguments.first as String,
        ).readAsString(),
        body,
      );
      return '';
    });
    client = Request.scoped(native: _Native(), isAndroid: false);
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesActionProvider.overrideWith(() => _Profiles(client)),
        profilesProvider.overrideWith(TestProfiles.new),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
      ],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    client.attach(container);
    await client.ready();
    original = MobileScannerPlatform.instance;
    channel = MethodChannelMobileScanner();
    MobileScannerPlatform.instance = channel;
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel.methodChannel,
      null,
    );
    MobileScannerPlatform.instance = original;
    HttpOverrides.global = originalHttp;
    container.dispose();
    await client.detach();
    await server.close(force: true);
    await store.close();
    await for (final entry in root.list()) {
      await entry.delete(recursive: true);
    }
  });

  void nativePayload({bool cancelled = false, PlatformException? error}) {
    final url = 'http://127.0.0.1:${server.port}/subscription?token=SYNTHETIC';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel.methodChannel,
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'pickQrImage':
            return cancelled ? null : 41;
          case 'decodeQrImage':
            if (error != null) throw error;
            return {
              'data': [
                {
                  'rawValue':
                      'flclash://install-config?url=${Uri.encodeComponent(url)}',
                  'format': 256,
                  'type': 7,
                },
              ],
            };
          case 'cancelQrImage':
            return null;
          default:
            throw StateError(call.method);
        }
      },
    );
  }

  testWidgets(
    'gallery codec candidate waits for confirmation; cancel never downloads; confirm saves through Request',
    (tester) async {
      nativePayload();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(1400, 1000));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      final action = container.read(profilesActionProvider.notifier);
      for (final confirm in [false, true]) {
        late String candidate;
        late Future<void> importing;
        await tester.runAsync(() async {
          candidate = (await QrImageOperation().read())!;
          importing = action.addProfileFormURL(
            candidate,
            mode: RequestMode.direct,
          );
        });
        await tester.pumpAndSettle();
        expect(find.byType(NamedUrlDialog), findsOneWidget);
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .any((field) => field.controller?.text == candidate),
          isTrue,
        );
        expect(received, isEmpty);
        await tester.tap(
          find.text(
            confirm
                ? currentAppLocalizations.submit
                : currentAppLocalizations.cancel,
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() => importing);
        if (!confirm) {
          expect(received, isEmpty);
          expect(
            await tester.runAsync(() => store.profilesDao.query().get()),
            isEmpty,
          );
        }
      }
      expect(received, hasLength(1));
      expect(received.single.path, '/subscription');
      expect(received.single.queryParameters, {'token': 'SYNTHETIC'});
      final profiles = (await tester.runAsync(
        () => store.profilesDao.query().get(),
      ))!;
      expect(profiles, hasLength(1));
      expect(
        profiles.single.url,
        'http://127.0.0.1:${server.port}/subscription?token=SYNTHETIC',
      );
      final saved = await tester.runAsync(
        () async => File(
          await appPath.getProfilePath(profiles.single.id.toString()),
        ).readAsString(),
      );
      expect(saved, body);
      expect(calls.map((call) => call.method), [
        'pickQrImage',
        'decodeQrImage',
        'cancelQrImage',
        'pickQrImage',
        'decodeQrImage',
        'cancelQrImage',
      ]);
      for (var offset = 0; offset < calls.length; offset += 3) {
        final clientId = (calls[offset].arguments as Map)['clientId'];
        expect(clientId, isA<int>());
        expect((calls[offset + 1].arguments as Map)['handle'], 41);
        expect((calls[offset + 2].arguments as Map)['clientId'], clientId);
      }
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'native selection cancellation passes through the codec without decode or HTTP',
    () async {
      nativePayload(cancelled: true);
      expect(await QrImageOperation().read(), isNull);
      expect(calls.map((call) => call.method), [
        'pickQrImage',
        'cancelQrImage',
      ]);
      expect(received, isEmpty);
    },
  );

  test('native error envelope is sanitized before the app consumer', () async {
    await AppLocalizations.load(const Locale('en'));
    nativePayload(
      error: PlatformException(
        code: 'qr_invalid_image',
        message: 'content://SYNTHETIC_SECRET',
        details: 'SYNTHETIC_SECRET',
      ),
    );
    await expectLater(
      QrImageOperation().read(),
      throwsA(
        isA<MessageException>().having(
          (error) => error.message,
          'safe error',
          currentAppLocalizations.qrImageReadFailed,
        ),
      ),
    );
    expect(calls.map((call) => call.method), [
      'pickQrImage',
      'decodeQrImage',
      'cancelQrImage',
    ]);
    expect(received, isEmpty);
  });
}
