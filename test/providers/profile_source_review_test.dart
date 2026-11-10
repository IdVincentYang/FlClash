import 'dart:io';
import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import '../helpers/test_app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/source_review_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Native extends Mock implements Service {}

class _Core extends Mock implements CoreHandlerInterface {}

class _Requests extends Request {
  _Requests() : super.scoped(native: _Native(), isAndroid: false);
  @override
  bool get requiresSourceAcceptance => true;
  Completer<bool>? recoveryGate;
  @override
  Future<bool> materialRecoveryRequired() async =>
      recoveryGate == null ? false : await recoveryGate!.future;
  @override
  Future<Map<String, Object?>?> captureNativeRunState() async => const {
    'processEpoch': 'review-process',
    'intentRevision': 7,
    'configToken': 12,
  };
}

class _Profiles extends ProfilesAction {
  _Profiles(this.requests);
  final Request requests;
  @override
  Request get requestClient => requests;
  @override
  Future<void> presentSourceReview(
    Profile profile,
    Future<void> Function(SourceConfirmation, bool Function()) work,
  ) => work(ref.read(sourceConfirmationProvider), () => true);
}

class _VisibleProfiles extends ProfilesAction {
  _VisibleProfiles(this.requests);
  final Request requests;
  @override
  Request get requestClient => requests;
}

class _Setup extends SetupAction {
  final calls = <({bool force, Map<String, Object?>? run, int? sequence})>[];
  @override
  void build() {}
  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    bool allowSourceReview = true,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
  }) async {
    expect(allowSourceReview, isTrue);
    expect(allowBootstrap, isFalse);
    calls.add((force: force, run: expectedRun, sequence: setupSequence));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;
  late _Requests requests;
  late _Setup setup;
  late List<Map<String, Object?>> operations;
  SourceReviewDecision? decision;
  void Function()? duringReview;
  final profile = Profile.normal(label: 'Review fixture');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('en'));
    directory = await Directory.systemTemp.createTemp('profile-review-');
    AppPath.supportDirectory = () async => directory;
    AppPath.temporaryDirectory = () async => directory;
    AppPath.cacheDirectory = () async => directory;
    final file = File(await appPath.getProfilePath(profile.id.toString()));
    await file.parent.create(recursive: true);
    await file.writeAsString('rules: ["MATCH,REJECT"]\n');
    operations = [];
    decision = const SourceReviewDecision(automatic: false, routing: 'source');
    duringReview = null;
    final core = _Core();
    when(core.getConfigState).thenAnswer((_) async => const ConfigFact());
    when(() => core.sourceAcceptance(any())).thenAnswer((call) async {
      final input = Map<String, Object?>.from(
        call.positionalArguments.single as Map,
      );
      operations.add(input);
      return switch (input['action']) {
        'status' => {'status': 'accepted'},
        'review' => {
          'status': 'reviewRequired',
          'candidate': 'review-candidate',
          'routing': 'source',
        },
        'accept' => {
          'status': 'accepted',
          'routing': 'source',
          'use': <String, Object?>{},
        },
        'discard' => {'status': 'discarded'},
        _ => throw StateError('Unexpected source operation: $input'),
      };
    });
    requests = _Requests();
    setup = _Setup();
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesActionProvider.overrideWith(() => _Profiles(requests)),
        setupActionProvider.overrideWith(() => setup),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        sourceConfirmationProvider.overrideWithValue((review) async {
          expect(review.kind, 'profile');
          duringReview?.call();
          return decision;
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await requests.detach();
    await directory.delete(recursive: true);
  });

  test(
    'profile status reads the saved revision without review or application',
    () async {
      final status = await container
          .read(profilesActionProvider.notifier)
          .sourceReviewStatus(profile);
      expect(status, SourceReviewStatus.ready);
      expect(operations.map((input) => input['action']), ['status']);
      expect(operations.single['body'], 'rules: ["MATCH,REJECT"]\n');
      expect(setup.calls, isEmpty);
    },
  );

  test(
    'missing local content is unavailable rather than pending review',
    () async {
      await File(await appPath.getProfilePath(profile.id.toString())).delete();
      await expectLater(
        container
            .read(profilesActionProvider.notifier)
            .sourceReviewStatus(profile),
        throwsA(
          isA<RequestUnavailable>().having(
            (error) => error.code,
            'code',
            'source_material_unavailable',
          ),
        ),
      );
      expect(operations, isEmpty);
    },
  );

  for (final entry in ['card', 'menu', 'failed card']) {
    testWidgets(
      '$entry review is visible before slow native checks and cancels immediately',
      (tester) async {
        final core = container.read(coreHandlerProvider);
        container.dispose();
        container = ProviderContainer(
          overrides: [
            coreHandlerProvider.overrideWithValue(core),
            profilesActionProvider.overrideWith(
              () => _VisibleProfiles(requests),
            ),
            setupActionProvider.overrideWith(_Setup.new),
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profileReviewStatusProvider.overrideWith(
              (ref, profile) async => SourceReviewStatus.required,
            ),
          ],
        );
        globalState.container = container;
        container.read(appVisibleProvider.notifier).value = true;
        container.read(viewSizeProvider.notifier).value = const Size(1000, 900);
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestApp(
              child: Scaffold(
                body: ProfileItem(
                  profile: profile,
                  groupValue: profile.id,
                  onChanged: (_) => fail('review must not change selection'),
                  sourceReviewEnabled: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gate = requests.recoveryGate = Completer<bool>();
        if (entry == 'menu') {
          await tester.tap(find.byTooltip('More'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Review source'));
        } else {
          await tester.tap(find.text(profile.realLabel));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Review subscription'), findsOneWidget);
        expect(
          find.text('Checking subscription and permissions…'),
          findsOneWidget,
        );
        expect(operations, isEmpty);
        if (entry == 'failed card') {
          gate.completeError(
            const RequestUnavailable('source_material_unavailable'),
          );
          await tester.pump();
          expect(find.text('Retry'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(operations, isEmpty);
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        if (!gate.isCompleted) gate.complete(false);
        await tester.pumpAndSettle();
        expect(operations, isEmpty);
        expect(find.text('Review subscription'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'direct review skips permissions and continues explicit application',
    () async {
      await container
          .read(profilesActionProvider.notifier)
          .manageSourcePermissions(profile, review: true);

      expect(operations.map((input) => input['action']), ['review', 'accept']);
      expect(operations.first['forceReview'], isTrue);
      expect(setup.calls, hasLength(1));
      expect(setup.calls.single.force, isTrue);
      expect(setup.calls.single.run, await requests.captureNativeRunState());
      expect(setup.calls.single.sequence, isNotNull);
    },
  );

  test('cancelled review never applies or accepts the candidate', () async {
    decision = null;
    await expectLater(
      container
          .read(profilesActionProvider.notifier)
          .manageSourcePermissions(profile, review: true),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(operations.map((input) => input['action']), ['review', 'discard']);
    expect(setup.calls, isEmpty);
  });

  test(
    'changing selection during review cannot apply another profile',
    () async {
      duringReview = () {
        container.read(currentProfileIdProvider.notifier).value =
            profile.id + 1;
      };
      await container
          .read(profilesActionProvider.notifier)
          .manageSourcePermissions(profile, review: true);
      expect(operations.last['action'], 'accept');
      expect(setup.calls, isEmpty);
    },
  );
}
