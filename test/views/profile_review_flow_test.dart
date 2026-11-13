import 'dart:io';
import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/edit.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
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

class _Setup extends SetupAction {
  int applications = 0;
  @override
  void build() {}
  @override
  void autoApplyProfile() => applications++;
  @override
  void applyProfileDebounce({
    bool silence = false,
    bool force = false,
    bool allowSourceReview = true,
    Future<bool> Function()? isCurrent,
  }) {
    expect(allowSourceReview, isTrue);
    applications++;
  }
}

class _Profiles extends ProfilesAction {
  final reviews = <({int id, bool direct})>[];
  int writes = 0;
  Future<SourceReviewStatus> Function()? checkStatus;
  @override
  Future<SourceReviewStatus> sourceReviewStatus(Profile profile) async =>
      await checkStatus?.call() ?? SourceReviewStatus.ready;
  @override
  void build() {}
  @override
  Future<void> manageSourcePermissions(
    Profile profile, {
    bool review = false,
  }) async {
    reviews.add((id: profile.id, direct: review));
  }

  @override
  Future<void> putProfile(
    Profile profile, {
    Iterable<int> renameIn = const [],
    void Function(RequestSource)? onSourceSaved,
  }) async {
    writes++;
  }
}

void main() {
  late Directory directory;
  late ProviderContainer container;
  late _Setup setup;
  late _Profiles profiles;
  final profile = Profile.normal(
    label: 'Review fixture',
    url: 'https://example.test/subscription',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('profile-review-ui-');
    AppPath.supportDirectory = () async => directory;
    AppPath.temporaryDirectory = () async => directory;
    AppPath.cacheDirectory = () async => directory;
    final file = File(await appPath.getProfilePath(profile.id.toString()));
    await file.parent.create(recursive: true);
    await file.writeAsString('rules: ["MATCH,REJECT"]\n');
    setup = _Setup();
    profiles = _Profiles();
    container = ProviderContainer(
      overrides: [
        setupActionProvider.overrideWith(() => setup),
        configStateProvider.overrideWith(_ConfigState.new),
        profilesActionProvider.overrideWith(() => profiles),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
      ],
    );
    globalState.container = container;
  });

  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1200, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final action in ['leave', 'save unchanged', 'save changes']) {
    testWidgets('editing profile: $action', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: ProfileItem(
            profile: profile,
            groupValue: profile.id,
            onChanged: (_) => fail('editing must not select a profile'),
            sourceReviewEnabled: false,
          ),
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileView), findsOneWidget);
      expect(setup.applications, 0);
      if (action == 'save changes') {
        await tester.enterText(find.byType(TextField).first, 'Renamed fixture');
      }
      if (action != 'leave') {
        await tester.tap(find.byTooltip('Save'));
      } else {
        globalState.navigatorKey.currentState!.pop();
      }
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileView), findsNothing);
      expect(setup.applications, action == 'save changes' ? 1 : 0);
      expect(profiles.writes, action == 'save changes' ? 1 : 0);
      expect(profiles.reviews, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('profile menu exposes direct review without opening edit', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        body: ProfileItem(
          profile: profile,
          groupValue: profile.id,
          onChanged: (_) => fail('review must not select another profile'),
          sourceReviewEnabled: true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Review source'), findsOneWidget);
    await tester.tap(find.text('Review source'));
    await tester.pumpAndSettle();
    expect(profiles.reviews, [(id: profile.id, direct: true)]);
    expect(find.byType(EditProfileView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final selected in [true, false]) {
    for (final pending in [true, false]) {
      testWidgets(
        'URL card reviews pending sources or uses subscription: selected=$selected, pending=$pending',
        (tester) async {
          final selections = <int?>[];
          profiles.checkStatus = () async =>
              pending ? SourceReviewStatus.required : SourceReviewStatus.ready;
          await pump(
            tester,
            Scaffold(
              body: ProfileItem(
                profile: profile,
                groupValue: selected ? profile.id : null,
                onChanged: selections.add,
                sourceReviewEnabled: true,
              ),
            ),
          );
          await tester.tap(find.text(profile.realLabel));
          await tester.pumpAndSettle();
          if (pending) {
            expect(profiles.reviews, [(id: profile.id, direct: true)]);
            expect(find.byType(EditProfileView), findsNothing);
          } else {
            expect(profiles.reviews, isEmpty);
            expect(find.byType(EditProfileView), findsNothing);
          }
          expect(selections, pending || selected ? isEmpty : [profile.id]);
          expect(setup.applications, 0);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final pending in [false, true]) {
    testWidgets(
      'phone card fits separate Use and review status: pending=$pending',
      (tester) async {
        profiles.checkStatus = () async =>
            pending ? SourceReviewStatus.required : SourceReviewStatus.ready;
        await pump(
          tester,
          Scaffold(
            body: ProfileItem(
              profile: profile,
              groupValue: null,
              onChanged: (_) {},
              sourceReviewEnabled: true,
            ),
          ),
          size: const Size(390, 800),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Use'), findsOneWidget);
        expect(
          tester
                  .widget<TextButton>(find.widgetWithText(TextButton, 'Use'))
                  .onPressed !=
              null,
          !pending,
        );
        expect(
          find.text('Review required'),
          pending ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Use changes selection without opening edit or review', (
    tester,
  ) async {
    final selections = <int?>[];
    await pump(
      tester,
      Scaffold(
        body: ProfileItem(
          profile: profile,
          groupValue: null,
          onChanged: selections.add,
          sourceReviewEnabled: true,
        ),
      ),
    );
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(selections, [profile.id]);
    expect(profiles.reviews, isEmpty);
    expect(find.byType(EditProfileView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final failure in [false, true]) {
    testWidgets(
      'unknown permission status retains Use behavior without accepting sources: failure=$failure',
      (tester) async {
        final gate = Completer<SourceReviewStatus>();
        final selections = <int?>[];
        profiles.checkStatus = () => gate.future;
        await pump(
          tester,
          Scaffold(
            body: ProfileItem(
              profile: profile,
              groupValue: null,
              onChanged: selections.add,
              sourceReviewEnabled: true,
            ),
          ),
        );
        if (failure) {
          gate.completeError(StateError('native unavailable'));
          await tester.pumpAndSettle();
          expect(find.text('Permissions unavailable · retry'), findsOneWidget);
          await tester.tap(find.text(profile.realLabel));
          await tester.pumpAndSettle();
          expect(find.byType(EditProfileView), findsNothing);
          expect(selections, [profile.id]);
          expect(profiles.reviews, isEmpty);
          profiles.checkStatus = () async => SourceReviewStatus.required;
          await tester.tap(find.text('Permissions unavailable · retry'));
          await tester.pumpAndSettle();
          expect(find.text('Review required'), findsOneWidget);
          profiles.checkStatus = () => Completer<SourceReviewStatus>().future;
        } else {
          expect(find.text('Checking source permissions…'), findsOneWidget);
        }
        if (!failure) {
          await tester.tap(find.text(profile.realLabel));
          await tester.pumpAndSettle();
          expect(find.byType(EditProfileView), findsNothing);
          expect(selections, [profile.id]);
          expect(profiles.reviews, isEmpty);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        if (!gate.isCompleted) gate.complete(SourceReviewStatus.ready);
      },
    );
  }
  testWidgets('file profile card retains its edit action', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: ProfileItem(
          profile: profile.copyWith(url: ''),
          groupValue: null,
          onChanged: (_) => fail('file card keeps its existing edit action'),
          sourceReviewEnabled: false,
        ),
      ),
    );
    await tester.tap(find.text(profile.realLabel));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileView), findsOneWidget);
    expect(profiles.reviews, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
