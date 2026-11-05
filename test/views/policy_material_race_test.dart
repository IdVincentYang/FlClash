import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/managed_material.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/policy_draft.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import '../helpers/test_app.dart';
import '../helpers/test_managed_materials.dart';
import '../helpers/test_policy_drafts.dart';
import '../plugins/code_forge/support.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Setup extends SetupAction {
  final candidates = <PolicyMaterialCandidate>[];
  bool controlledLoads = false;
  int loads = 0;
  final entered = [Completer<void>(), Completer<void>()];
  final results = [Completer<void>(), Completer<void>()];

  @override
  void build() {}

  @override
  Future<PolicyMaterialCandidate> capturePolicyMaterial(
    int profileId, {
    bool latest = false,
    void Function(PolicyMaterialCandidate)? onCreated,
    String? incomingPath,
    Request? client,
    SourceMaterialApproval? approval,
  }) async {
    final index = latest && controlledLoads ? loads++ : null;
    final candidate = await super.capturePolicyMaterial(
      profileId,
      latest: index == null && latest,
      incomingPath: incomingPath,
      client: client,
      onCreated: (candidate) {
        candidates.add(candidate);
        onCreated?.call(candidate);
      },
    );
    if (index != null) {
      entered[index].complete();
      await results[index].future;
      if (index == 0) throw const RequestUnavailable('request_cancelled');
    }
    return candidate;
  }
}

class _Selection extends PolicySelectionAction {
  @override
  bool get supportsManaged => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database store;
  late ProviderContainer container;
  late _Core core;
  late _Setup setup;
  late Profile profile;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('material-widget-races-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    store = Database(NativeDatabase.memory());
    database = store;
    profile = draftTestProfile(1);
    core = _Core();
    setup = _Setup();
    when(
      () => core.getConfigState(),
    ).thenAnswer((_) async => const ConfigFact());
    when(() => core.getConfig(any())).thenAnswer((_) async => testMaterial());
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        setupActionProvider.overrideWith(() => setup),
        policySelectionActionProvider.overrideWith(_Selection.new),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
      ],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1400);
  });
  tearDown(() async {
    for (final result in setup.results) {
      if (!result.isCompleted) result.complete();
    }
    container.dispose();
    for (final candidate in setup.candidates) {
      await candidate.close();
    }
    await store.close();
  });

  Future<void> seed(Profile row, PolicyDraftDocument draft) async {
    profile = row;
    await store.profilesDao.putAll([row.toCompanion()]);
    await store.profilePolicyDraftsDao.compareAndWrite(
      1,
      expectedRaw: null,
      rawContent: draft.encode(),
    );
    final file = File(await appPath.getProfilePath('1'));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(testMaterial()));
  }

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 120 && !condition(); i++) {
      await settle(tester, 1);
    }
    expect(condition(), true);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      var drained = false;
      final drain = dataMutations.run(() async {
        drained = true;
      });
      await until(tester, () => drained);
      await drain;
      await tester.pump();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: StatusManager(child: PolicyDraftView(profile: profile)),
        ),
      ),
    );
    await settle(tester, 12);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder));
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> latest(WidgetTester tester) async {
    await tap(tester, find.byTooltip('More'));
    await tap(tester, find.text('Source bindings'));
    await tap(tester, find.text('Load latest material for preview'));
  }

  testWidgets(
    'I2 late A cleanup cannot enable controls or notify while B is pending',
    (tester) async {
      await tester.runAsync(
        () => seed(
          profile.copyWith(
            url: 'http://127.0.0.1/source',
            requestMode: RequestMode.direct,
          ),
          completePolicyDraft(),
        ),
      );
      setup.controlledLoads = true;
      await pump(tester);
      await latest(tester);
      await until(tester, () => setup.entered[0].isCompleted);
      await tap(tester, find.byTooltip('More'));
      await tap(tester, find.text('Discard preview material'));
      await latest(tester);
      await until(tester, () => setup.entered[1].isCompleted);
      setup.results[0].complete();
      await settle(tester, 12);
      final scaffold = tester.widget<CommonScaffold>(
        find.byType(CommonScaffold),
      );
      expect(scaffold.isLoading, true);
      expect(
        scaffold.iconActions
            .singleWhere((item) => item.tooltip == 'Generated draft preview')
            .onPressed,
        isNull,
      );
      expect(
        scaffold.menuItems
            .singleWhere((item) => item.label == 'Save and request application')
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Material is unavailable'), findsNothing);
      expect(find.textContaining('Latest material loaded.'), findsNothing);
      setup.results[1].complete();
      await until(
        tester,
        () => !tester
            .widget<CommonScaffold>(find.byType(CommonScaffold))
            .isLoading,
      );
      expect(find.textContaining('Latest material loaded.'), findsOneWidget);
      expect(setup.candidates.length, 2);
      expect(await setup.candidates.first.current(), false);
      List<Profile>? rows;
      List<ProfilePolicySelection>? selections;
      final read = () async {
        rows = await store.profilesDao.query().get();
        selections = await store.profilePolicySelectionsDao.query().get();
      }();
      await until(tester, () => rows != null && selections != null);
      await read;
      expect(rows!.single.lastUpdateDate, isNull);
      expect(selections, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester, 12);
      expect(await setup.candidates.last.current(), false);
    },
  );

  testWidgets(
    'I3 editing during preview cannot show old completion as the new draft ready',
    (tester) async {
      await tester.runAsync(initEditorNative);
      final draft = materialDraft(
        identity: profileMaterialIdentity(
          profileId: 1,
          type: profile.type.name,
          url: profile.url,
          overwrite: profile.overwriteType.name,
          scriptId: profile.scriptId,
        ),
      );
      await tester.runAsync(() => seed(profile, draft));
      final entered = Completer<void>(), release = Completer<void>();
      when(() => core.getConfig(any())).thenAnswer((_) async {
        entered.complete();
        await release.future;
        return testMaterial();
      });
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      await pump(tester);
      await tap(tester, find.byTooltip('Generated draft preview'));
      await until(tester, () => entered.isCompleted);
      await tap(tester, find.text('Default for unmatched domains'));
      await tap(tester, find.byKey(const ValueKey('draft-target')));
      await tap(tester, find.text('REJECT').last);
      await tap(tester, find.text('Confirm').last);
      draft.policy['domainDefault'] = {
        'target': {'kind': 'reject'},
      };
      release.complete();
      await settle(tester, 20);
      expect(find.byType(EditorPage), findsNothing);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      expect(
        find.text('Inputs still need generated preview validation'),
        findsOneWidget,
      );
      expect(setup.candidates.single.qualifies(draft), false);
      await tester.runAsync(initEditorNative);
      await tap(tester, find.byTooltip('Generated draft preview'));
      await until(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);
      final preview = tester.widget<EditorPage>(find.byType(EditorPage));
      expect(
        (loadYaml(preview.content!)['dns']['nameserver'] as List).first,
        'rcode://refused',
      );
      expect(setup.candidates.single.qualifies(draft), true);
      expect(await store.profilePolicySelectionsDao.query().get(), isEmpty);
    },
  );
}
