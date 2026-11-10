import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/profile_import.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/profile_refresh.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/profiles/import_url.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:fl_clash/widgets/source_review.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _ConfigState extends ConfigState {
  @override
  ConfigViewState build() => const ConfigViewState();
}

class _Attempt {
  _Attempt(this.url, this.label, this.task, this.presentation);
  final String url;
  final String? label;
  final ProfileImportTask task;
  final SourceReviewPresentation presentation;
  final downloaded = Completer<void>();
  final saved = Completer<void>();
  final related = Completer<List<SourceReview>>();
  bool cancelled = false;
}

class _Profiles extends ProfilesAction {
  final attempts = <_Attempt>[];
  @override
  void build() {}

  @override
  Future<ProfileRefreshResult?> addProfileFormURL(
    String url, {
    String? label,
    RequestMode mode = RequestMode.auto,
    String? proxy,
    bool confirmed = false,
    ProfileImportTask? importTask,
    SourceReviewPresentation? reviewPresentation,
  }) async {
    final attempt = _Attempt(url, label, importTask!, reviewPresentation!);
    attempts.add(attempt);
    importTask.attach(() => attempt.cancelled = true);
    importTask.report(ProfileImportPhase.downloading);
    await attempt.downloaded.future;
    final decision = await reviewPresentation.present(
      SourceReviewDialog(
        review: SourceReview(
          label: label ?? '',
          origin: 'https://source.example.test',
          kind: 'profile',
          reasons: const ['first_use'],
          routing: 'source',
        ),
        loadRelated: (_) => attempt.related.future,
        onDecision: reviewPresentation.onDecision,
      ),
    );
    if (decision == null || !importTask.isCurrent) {
      return const ProfileRefreshResult(
        application: ProfileApplicationOutcome.superseded,
      );
    }
    importTask.report(ProfileImportPhase.saving);
    await attempt.saved.future;
    return const ProfileRefreshResult(materialSaved: true);
  }
}

void main() {
  late ProviderContainer container;
  late _Profiles profiles;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    profiles = _Profiles();
    container = ProviderContainer(
      overrides: [
        profilesActionProvider.overrideWith(() => profiles),
        profilesProvider.overrideWith(TestProfiles.new),
        configStateProvider.overrideWith(_ConfigState.new),
      ],
    );
    globalState.container = container;
  });
  tearDown(() => container.dispose());

  Future<void> pumpStep(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = const Size(400, 900);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: Scaffold(
            body: FilledButton(
              onPressed: showAddProfilePage,
              child: Text('Add fixture'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add fixture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('URL'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileUrlImportDialog), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Request route'), findsOneWidget);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'Fixture');
    await tester.enterText(
      find.byType(TextFormField).last,
      'https://source.example.test/subscription',
    );
    await tester.tap(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await pumpStep(tester);
  }

  testWidgets('one import surface covers download, related review and saving', (
    tester,
  ) async {
    await open(tester);
    final route = ModalRoute.of(tester.element(find.byType(NamedUrlDialog)));
    await submit(tester);
    expect(profiles.attempts, hasLength(1));
    expect(find.text('Downloading subscription…'), findsOneWidget);
    expect(find.byType(NamedUrlDialog), findsNothing);
    expect(ModalRoute.of(tester.element(find.byType(CommonDialog))), route);
    final attempt = profiles.attempts.single;
    attempt.downloaded.complete();
    await pumpStep(tester);
    expect(find.byType(SourceReviewDialog), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(SourceReviewDialog))),
      route,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Accept this revision'),
          )
          .onPressed,
      isNull,
    );
    attempt.related.complete(const []);
    await pumpStep(tester);
    await tester.tap(find.text('Accept this revision'));
    await pumpStep(tester);
    expect(find.text('Saving subscription…'), findsOneWidget);
    expect(find.byType(SourceReviewDialog), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    await tester.binding.handlePopRoute();
    await pumpStep(tester);
    expect(find.text('Saving subscription…'), findsOneWidget);
    attempt.saved.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileUrlImportDialog), findsNothing);
    expect(find.byType(AddProfileView), findsNothing);
    expect(find.text('Add fixture'), findsOneWidget);
  });

  testWidgets(
    'download failure preserves input and retry uses the same surface',
    (tester) async {
      await open(tester);
      await submit(tester);
      profiles.attempts.single.downloaded.completeError(
        const MessageException('Fixture download failed'),
      );
      await pumpStep(tester);
      expect(find.text('Fixture download failed'), findsOneWidget);
      expect(find.text('Fixture'), findsOneWidget);
      expect(
        find.text('https://source.example.test/subscription'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await pumpStep(tester);
      expect(profiles.attempts, hasLength(2));
      expect(find.text('Downloading subscription…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await pumpStep(tester);
      expect(profiles.attempts.last.cancelled, isTrue);
      profiles.attempts.last.downloaded.complete();
      await pumpStep(tester);
      expect(find.byType(SourceReviewDialog), findsNothing);
      expect(find.byType(NamedUrlDialog), findsOneWidget);
    },
  );

  testWidgets(
    'review cancel and back preserve inputs and invalidate the attempt',
    (tester) async {
      await open(tester);
      await submit(tester);
      final attempt = profiles.attempts.single;
      attempt.downloaded.complete();
      await pumpStep(tester);
      await tester.tap(find.text('Cancel'));
      await pumpStep(tester);
      expect(attempt.cancelled, isTrue);
      expect(find.byType(NamedUrlDialog), findsOneWidget);
      expect(find.text('Fixture'), findsOneWidget);
      attempt.related.complete(const []);
      await pumpStep(tester);
      expect(find.byType(SourceReviewDialog), findsNothing);
      await tester.tap(find.text('Continue'));
      await pumpStep(tester);
      await tester.binding.handlePopRoute();
      await pumpStep(tester);
      expect(profiles.attempts.last.cancelled, isTrue);
      profiles.attempts.last.downloaded.complete();
      await pumpStep(tester);
      expect(find.byType(NamedUrlDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileUrlImportDialog), findsNothing);
      expect(find.byType(AddProfileView), findsOneWidget);
    },
  );
}
