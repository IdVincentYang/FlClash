import 'dart:io';
import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/profile_import.dart';
import 'package:fl_clash/models/profile_refresh.dart';
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
  final updates = <({int id, bool review})>[];
  Future<void> Function(Profile)? onUpdate;
  @override
  Future<ProfileRefreshResult> updateProfile(
    Profile profile, {
    bool showLoading = false,
    bool automatic = false,
    bool allowSourceReview = true,
    bool Function()? isCurrent,
    bool allowBootstrap = false,
    bool sourceEdit = false,
    bool sourceMustMatch = false,
    bool importing = false,
    RequestSource? expectedSource,
    ProfileImportTask? importTask,
    SourceConfirmation? confirm,
    Iterable<int> renameIn = const [],
  }) async {
    updates.add((id: profile.id, review: allowSourceReview));
    await onUpdate?.call(profile);
    return const ProfileRefreshResult();
  }

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

  for (final urls in [0, 1, 2]) {
    for (final localFile in [false, true]) {
      testWidgets(
        'Sync all review policy: $urls subscriptions, local=$localFile',
        (tester) async {
          final entries = [
            for (var i = 0; i < urls; i++)
              profile.copyWith(id: i + 1, label: 'URL $i'),
            if (localFile) profile.copyWith(id: 3, label: 'File', url: ''),
          ];
          (container.read(profilesProvider.notifier) as TestProfiles).replace(
            entries,
          );
          await pump(tester, const ProfilesView());
          if (entries.isEmpty) {
            expect(find.byTooltip('Update'), findsNothing);
          } else {
            await tester.tap(find.byTooltip('Update'));
            await tester.pumpAndSettle();
          }
          expect(profiles.updates, [
            for (var i = 0; i < urls; i++) (id: i + 1, review: urls == 1),
          ]);
          expect(profiles.reviews, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'failed bulk sync reports download errors and permits another sync',
    (tester) async {
      (container.read(profilesProvider.notifier) as TestProfiles).replace([
        profile,
        profile.copyWith(id: profile.id + 1, label: 'Other'),
      ]);
      profiles.onUpdate = (entry) async {
        if (entry.id == profile.id) {
          throw const RequestUnavailable('profile_download_failed');
        }
      };
      await pump(tester, const ProfilesView());
      await tester.tap(find.byTooltip('Update'));
      await tester.pumpAndSettle();
      expect(profiles.updates, hasLength(2));
      expect(find.text('Tip'), findsOneWidget);
      expect(
        find.text(
          'The subscription download failed. The previous file was kept.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      profiles.onUpdate = null;
      await tester.tap(find.byTooltip('Update'));
      await tester.pumpAndSettle();
      expect(profiles.updates, hasLength(4));
      expect(find.text('Tip'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('leaving during bulk sync does not show a late error dialog', (
    tester,
  ) async {
    final gate = Completer<void>();
    profiles.onUpdate = (_) => gate.future;
    await pump(tester, const ProfilesView());
    await tester.tap(find.byTooltip('Update'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.completeError(const RequestUnavailable('profile_download_failed'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(profiles.updates, hasLength(1));
  });

  testWidgets(
    'individual sync remains interactive with multiple subscriptions',
    (tester) async {
      (container.read(profilesProvider.notifier) as TestProfiles).replace([
        profile,
        profile.copyWith(id: profile.id + 1, label: 'Other'),
      ]);
      await pump(
        tester,
        Scaffold(
          body: ProfileItem(
            profile: profile,
            groupValue: profile.id,
            onChanged: (_) {},
            sourceReviewEnabled: true,
          ),
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      expect(profiles.updates, [(id: profile.id, review: true)]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'bulk sync finishes by marking the card, and only a tap starts review',
    (tester) async {
      var pending = false;
      profiles.checkStatus = () async =>
          pending ? SourceReviewStatus.required : SourceReviewStatus.ready;
      final selections = <int?>[];
      await pump(
        tester,
        Scaffold(
          body: ProfileItem(
            profile: profile,
            groupValue: profile.id,
            onChanged: selections.add,
            sourceReviewEnabled: true,
          ),
        ),
      );
      final updating = container.read(updatingKeysProvider.notifier);
      final operation = updating.start(profile.updatingKey);
      await tester.pump();
      pending = true;
      updating.stop(profile.updatingKey, operation);
      await tester.pumpAndSettle();
      expect(find.text('Review required'), findsOneWidget);
      expect(profiles.reviews, isEmpty);
      await tester.tap(find.text(profile.realLabel));
      await tester.pumpAndSettle();
      expect(profiles.reviews, [(id: profile.id, direct: true)]);
      expect(selections, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
