import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/source_review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';

void main() {
  const review = SourceReview(
    label: 'fixture',
    origin: '',
    kind: 'script',
    reasons: ['first_use'],
    routing: 'source',
    script: 'function main(config) { return config; }',
  );
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = const Size(1000, 900);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a delayed review in the background never opens a modal', (
    tester,
  ) async {
    await mount(tester);
    container.read(appVisibleProvider.notifier).value = false;
    await expectLater(
      container.read(sourceConfirmationProvider)(review),
      throwsA(
        isA<RequestUnavailable>().having(
          (error) => error.code,
          'code',
          'source_review_required',
        ),
      ),
    );
    container.read(appVisibleProvider.notifier).value = true;
    await tester.pumpAndSettle();
    expect(find.byType(SourceReviewDialog), findsNothing);
  });

  for (final beforeFirstFrame in [false, true]) {
    testWidgets(
      'backgrounding cancels the owned review: before frame=$beforeFirstFrame',
      (tester) async {
        await mount(tester);
        container.read(appVisibleProvider.notifier).value = true;
        final decision = container.read(sourceConfirmationProvider)(review);
        if (!beforeFirstFrame) {
          await tester.pumpAndSettle();
          expect(find.byType(SourceReviewDialog), findsOneWidget);
        }
        container.read(appVisibleProvider.notifier).value = false;
        await tester.pumpAndSettle();
        expect(await decision, isNull);
        expect(find.byType(SourceReviewDialog), findsNothing);
        container.read(appVisibleProvider.notifier).value = true;
        await tester.pumpAndSettle();
        expect(find.byType(SourceReviewDialog), findsNothing);
      },
    );
  }
}
