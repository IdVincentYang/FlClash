import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/source_review_status.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';

class _Profiles extends ProfilesAction {
  @override
  void build() {}

  @override
  Future<void> manageSourcePermissions(
    Profile profile, {
    bool review = false,
  }) async {}
}

void main() {
  final profile = Profile.normal(
    label: 'Subscription with a long title',
    url: 'https://example.test/profile',
  );
  late ProviderContainer container;
  final selections = <int?>[];

  setUp(() {
    selections.clear();
  });

  Future<String> pumpCard(
    WidgetTester tester, {
    required double width,
    bool selected = false,
    bool needsReview = false,
    bool updating = false,
    Locale locale = const Locale('en'),
    double scale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        profilesActionProvider.overrideWith(_Profiles.new),
        profileReviewStatusProvider.overrideWith(
          (ref, _) async => needsReview
              ? SourceReviewStatus.required
              : SourceReviewStatus.ready,
        ),
        isUpdatingProvider(profile.updatingKey).overrideWithValue(updating),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: locale,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: ProfileItem(
                      profile: profile,
                      groupValue: selected ? profile.id : null,
                      sourceReviewEnabled: true,
                      onChanged: selections.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (updating) {
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pumpAndSettle();
    }
    final context = tester.element(find.byType(ProfileItem));
    return selected
        ? context.appLocalizations.selected
        : context.appLocalizations.useProfile;
  }

  for (final width in [140.0, 600.0]) {
    for (final state in ['available', 'selected', 'review']) {
      testWidgets('$state action and menu at width $width', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final label = await pumpCard(
            tester,
            width: width,
            selected: state == 'selected',
            needsReview: state == 'review',
          );
          final action = width < 200
              ? find.byTooltip(label)
              : find.widgetWithText(TextButton, label);
          expect(action, findsOneWidget);
          final actionSemantics = tester
              .getSemantics(action)
              .getSemanticsData();
          if (width < 200) {
            expect(actionSemantics.tooltip, label);
            expect(actionSemantics.label, isNot(contains(label)));
          } else {
            expect(find.bySemanticsLabel(label), findsOneWidget);
          }
          final onPressed = width < 200
              ? tester
                    .widget<IconButton>(find.byType(IconButton).first)
                    .onPressed
              : tester.widget<TextButton>(action).onPressed;
          expect(onPressed == null, state != 'available');
          if (width < 200) {
            expect(tester.getSize(action), const Size(40, 40));
          }
          await tester.tap(action);
          await tester.pump();
          expect(selections, state == 'available' ? [profile.id] : isEmpty);
          await tester.tap(find.byTooltip('More'));
          await tester.pumpAndSettle();
          expect(find.text('Edit'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('text action yields to icons at its measured width boundary', (
    tester,
  ) async {
    final label = await pumpCard(tester, width: 600);
    final actionWidth = tester
        .getSize(find.widgetWithText(TextButton, label))
        .width;
    final title = tester.widget<Text>(find.text(profile.realLabel));
    final item = tester.widget<ListItem>(find.byType(ListItem));
    final threshold =
        actionWidth +
        40 +
        item.padding.horizontal +
        item.horizontalTitleGap! +
        title.style!.fontSize! * 3;
    for (final delta in [-1.0, 0.0, 1.0]) {
      await pumpCard(tester, width: threshold + delta);
      expect(find.byTooltip(label), delta < 0 ? findsOneWidget : findsNothing);
      expect(
        find.widgetWithText(TextButton, label),
        delta < 0 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'long localized actions and scaled text keep useful title space',
    (tester) async {
      for (final selected in [false, true]) {
        final label = await pumpCard(
          tester,
          width: 270,
          selected: selected,
          locale: const Locale('ru'),
          scale: 2,
        );
        expect(find.byTooltip(label), findsOneWidget);
        expect(
          tester.getSize(find.text(profile.realLabel)).width,
          greaterThan(50),
        );
        expect(tester.getSize(find.byTooltip(label)), const Size(40, 40));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('updating keeps the action and replaces only its menu', (
    tester,
  ) async {
    final label = await pumpCard(tester, width: 140, updating: true);
    expect(find.byTooltip(label), findsOneWidget);
    expect(find.byType(CommonCircleLoading), findsOneWidget);
    expect(find.byTooltip('More'), findsNothing);
    await tester.tap(find.byTooltip(label));
    await tester.pump();
    expect(selections, [profile.id]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
