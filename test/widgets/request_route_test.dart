import '../helpers/test_config_state.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/request_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets(
    'saved unavailable proxy remains visible and mode changes explicitly',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          configStateProvider.overrideWith(TestConfigState.new),
          selectedMapProvider.overrideWithValue(const {}),
        ],
      );
      container.read(viewSizeProvider.notifier).value = const Size(800, 600);
      addTearDown(container.dispose);
      var mode = RequestMode.proxy;
      String? proxy = 'synthetic missing node';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: RequestRouteFields(
                    mode: mode,
                    proxy: proxy,
                    onChanged: (value) => setState(() {
                      mode = value.$1;
                      proxy = value.$2;
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('synthetic missing node'), findsOneWidget);
      await tester.tap(find.text('Request route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Direct').last);
      await tester.pumpAndSettle();
      expect(mode, RequestMode.direct);
      expect(proxy, 'synthetic missing node');
      expect(find.text('Proxy target'), findsNothing);
    },
  );

  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ru'),
  ]) {
    testWidgets('advanced request fields render in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await tester.pumpWidget(
        TestApp(
          overrides: [
            configStateProvider.overrideWith(TestConfigState.new),
            selectedMapProvider.overrideWithValue(const {}),
          ],
          locale: locale,
          child: Scaffold(
            body: SingleChildScrollView(
              child: RequestRouteFields(
                mode: RequestMode.auto,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(RequestRouteFields));
      expect(
        find.text(AppLocalizations.of(context).requestModeAuto),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
