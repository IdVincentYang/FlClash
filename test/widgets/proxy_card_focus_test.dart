import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _testUrl = 'https://example.com/generate_204';

class _RecordingProxiesAction extends ProxiesAction {
  static final List<String> tested = [];

  @override
  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
    tested.add(proxy.name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    _RecordingProxiesAction.tested.clear();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        proxiesActionProvider.overrideWith(_RecordingProxiesAction.new),
        delayDataSourceProvider.overrideWithBuild(
          (_, _) => {
            _testUrl: {'proxy 0': 123, 'proxy 1': 456},
          },
        ),
      ],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(900, 600);
  });

  tearDown(() => container.dispose());

  Future<void> pumpCards(WidgetTester tester, ProxyCardType type) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          homeBuilder: (child) => Scaffold(body: child),
          child: Column(
            children: [
              for (var index = 0; index < 2; index++)
                SizedBox(
                  height: 120,
                  child: ProxyCard(
                    key: ValueKey('proxy $index'),
                    groupName: 'group',
                    testUrl: _testUrl,
                    proxy: Proxy(name: 'proxy $index', type: 'Shadowsocks'),
                    groupType: GroupType.Selector,
                    type: type,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> focusCard(WidgetTester tester, int index) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context?.findAncestorWidgetOfExactType<ProxyCard>()?.key ==
          ValueKey('proxy $index')) {
        return;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    fail('proxy card $index was not reachable by tab');
  }

  for (final type in ProxyCardType.values) {
    testWidgets('arrow right from a ${type.name} proxy card focuses its '
        'delay control', (tester) async {
      await pumpCards(tester, type);

      for (var index = 0; index < 2; index++) {
        await focusCard(tester, index);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        final focusNode = FocusManager.instance.primaryFocus;
        expect(focusNode, isA<SkipTraversalFocusNode>());
        expect(
          find.descendant(
            of: find.byWidget(focusNode!.context!.widget),
            matching: find.text(index == 0 ? '123 ms' : '456 ms'),
          ),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('tab walks card to card without stopping on the delay control', (
    tester,
  ) async {
    await pumpCards(tester, ProxyCardType.shrink);

    await focusCard(tester, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final context = FocusManager.instance.primaryFocus?.context;
    expect(
      context?.findAncestorWidgetOfExactType<ProxyCard>()?.key,
      const ValueKey('proxy 1'),
    );
  });

  testWidgets('pending nodes show waiting before replacing their old values', (
    tester,
  ) async {
    final pending = container.read(pendingDelayTestsProvider.notifier);
    final first = delayTestKey(_testUrl, 'proxy 0');
    final second = delayTestKey(_testUrl, 'proxy 1');
    pending.apply(acquired: [first, second], started: [second]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          homeBuilder: (child) => Scaffold(body: child),
          child: Column(
            children: [
              for (var index = 0; index < 2; index++)
                SizedBox(
                  height: 120,
                  child: ProxyCard(
                    groupName: 'group',
                    testUrl: _testUrl,
                    proxy: Proxy(name: 'proxy $index', type: 'Shadowsocks'),
                    groupType: GroupType.Selector,
                    type: ProxyCardType.shrink,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Waiting for result'), findsOneWidget);
    expect(find.text('123 ms'), findsNothing);
    container
        .read(delayDataSourceProvider.notifier)
        .setDelay(const Delay(url: _testUrl, name: 'proxy 0', value: 28));
    pending.apply(released: [first], finished: [second]);
    await tester.pumpAndSettle();
    expect(find.text('28 ms'), findsOneWidget);
    expect(find.text('456 ms'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('failed tests show a reason and can be retried', (tester) async {
    container
        .read(delayTestFailuresProvider.notifier)
        .set(
          delayTestKey(_testUrl, 'proxy 0'),
          const RequestUnavailable('delay_test_no_result'),
        );
    await pumpCards(tester, ProxyCardType.shrink);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('123 ms'), findsNothing);
    expect(find.text('456 ms'), findsOneWidget);
    expect(
      find.byTooltip(AppLocalizations.current.delayTestNoResult),
      findsOneWidget,
    );
    await tester.tap(find.text('Unavailable'));
    expect(_RecordingProxiesAction.tested, ['proxy 0']);
  });

  testWidgets('enter on the delay control runs the delay test', (tester) async {
    await pumpCards(tester, ProxyCardType.shrink);

    await focusCard(tester, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isA<SkipTraversalFocusNode>());

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_RecordingProxiesAction.tested, ['proxy 0']);
  });
}
