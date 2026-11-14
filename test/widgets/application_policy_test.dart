import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/application_policy.dart';
import 'package:fl_clash/widgets/application_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';

class _Routing extends ApplicationRoutingController {
  ApplicationRouteAction? selected;
  bool fail = false;
  @override
  ApplicationRoutingOperation build() => const ApplicationRoutingOperation();
  @override
  Future<void> setPolicy(
    Iterable<String> packages,
    ApplicationRouteAction action, {
    ApplicationRouteTarget? target,
    bool shared = false,
    bool? enable,
    int? expectedProfileId,
  }) async {
    selected = action;
    if (fail) throw StateError('controlled save failure');
  }
}

void main() {
  late ProviderContainer container;
  late _Routing routing;
  Future<void> pump(
    WidgetTester tester, {
    Mode mode = Mode.rule,
    bool enabled = false,
    bool fail = false,
    bool switchOnly = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    routing = _Routing()..fail = fail;
    container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => PatchClashConfig(mode: mode),
        ),
        applicationRoutingSettingsProvider.overrideWith(
          (_) => Stream.value(
            ApplicationRoutingSettings(
              rules: {
                'app': ApplicationRouteRule(
                  packageName: 'app',
                  enabled: enabled,
                  action: ApplicationRouteAction.reject,
                ),
              },
            ),
          ),
        ),
        globalLocalGroupsProvider.overrideWith((_) => Stream.value(const [])),
        applicationRoutingControllerProvider.overrideWith(() => routing),
      ],
    );
    container.listen(patchClashConfigProvider, (_, _) {});
    container.listen(vpnSettingProvider, (_, _) {});
    container.listen(currentProfileIdProvider, (_, _) {});
    container.listen(currentProfileProvider, (_, _) {});
    container.listen(globalLocalGroupsProvider, (_, _) {});
    globalState.container = container;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          homeBuilder: (child) => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: switchOnly
                ? child
                : Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => BaseNavigator.push(context, child),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
          ),
          child: switchOnly
              ? const Scaffold(
                  body: Center(
                    child: ApplicationPolicySwitch(
                      packages: ['app'],
                      label: 'Browser',
                    ),
                  ),
                )
              : const ApplicationPolicyView(
                  packages: ['app'],
                  label: 'Browser',
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!switchOnly) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'picker fixes DIRECT and REJECT above independent group/node filters',
    (tester) async {
      await pump(tester);
      expect(find.text('App policy · Browser'), findsOneWidget);
      expect(find.text('DIRECT'), findsOneWidget);
      expect(find.text('REJECT'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing node');
      await tester.pumpAndSettle();
      expect(find.text('DIRECT'), findsOneWidget);
      expect(find.text('REJECT'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('DIRECT'));
      await tester.pumpAndSettle();
      expect(routing.selected, ApplicationRouteAction.direct);
      expect(container.read(patchClashConfigProvider).mode, Mode.rule);
    },
  );

  testWidgets(
    'picker keeps source information below the app bar with large text',
    (tester) async {
      await pump(tester, scale: 2);
      expect(
        tester.getTopLeft(find.text('Unknown · Rule')).dy,
        greaterThan(tester.getTopLeft(find.text('App policy · Browser')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save error keeps the independent picker open', (tester) async {
    await pump(tester, fail: true);
    await tester.tap(find.text('REJECT'));
    await tester.pumpAndSettle();
    expect(routing.selected, ApplicationRouteAction.reject);
    expect(find.text('App policy · Browser'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Global preserves an enabled switch but disables its tap', (
    tester,
  ) async {
    await pump(
      tester,
      mode: Mode.global,
      enabled: true,
      switchOnly: true,
      scale: 2,
    );
    final control = tester.widget<Switch>(find.byType(Switch));
    expect(control.value, true);
    expect(control.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
}
