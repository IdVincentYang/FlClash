import 'package:fl_clash/manager/proxy_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.isInit;
  });

  setUp(() {
    container = ProviderContainer(
      overrides: [configStateProvider.overrideWith(TestConfigState.new)],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Future<void> pumpProxyManager(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: ProxyManager(child: SizedBox(key: Key('child'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enableSystemProxy({
    required bool running,
    int mixedPort = 7890,
  }) async {
    final inputs = container.read(applicationInputActionProvider.notifier);
    await inputs.updateNetwork((state) => state.copyWith(systemProxy: true));
    await inputs.updatePatch((state) => state.copyWith(mixedPort: mixedPort));
    container.read(runTimeProvider.notifier).value = running ? 1 : null;
  }

  testWidgets('renders its child unchanged', (tester) async {
    await pumpProxyManager(tester);

    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('platform failures never escape the update chain', (
    tester,
  ) async {
    await pumpProxyManager(tester);

    await tester.runAsync(() => enableSystemProxy(running: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed update does not stall later transitions', (
    tester,
  ) async {
    await pumpProxyManager(tester);

    await tester.runAsync(() => enableSystemProxy(running: true));
    await tester.pump();
    await tester.runAsync(
      () => enableSystemProxy(running: true, mixedPort: 7891),
    );
    await tester.pump();
    container.read(runTimeProvider.notifier).value = null;
    await tester.pumpAndSettle();

    expect(container.read(proxyStateProvider).isStart, isFalse);
    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('a running core reports the mixed port as the proxy target', () async {
    await enableSystemProxy(running: true, mixedPort: 7892);
    final state = container.read(proxyStateProvider);
    expect(state.isStart, isTrue);
    expect(state.systemProxy, isTrue);
    expect(state.port, 7892);
  });

  test('an excluded SSID suspends the system proxy', () {
    final suspended = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        excludeSSIDsProvider.overrideWithValue(const ['Office Wi-Fi']),
      ],
    );
    addTearDown(suspended.dispose);
    suspended.read(runTimeProvider.notifier).value = 1;
    suspended.read(currentSSIDProvider.notifier).value = 'Office Wi-Fi';

    expect(suspended.read(proxyStateProvider).isStart, isFalse);
  });
}
