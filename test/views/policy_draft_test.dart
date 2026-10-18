import 'dart:async';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/policy_draft.dart';
import 'package:fl_clash/views/profiles/profiles.dart';
import 'package:fl_clash/views/backup_and_restore.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_policy_drafts.dart';
import '../plugins/code_forge/support.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Setup extends SetupAction {
  int autoApplyCalls = 0;
  @override
  void build() {}
  @override
  void autoApplyProfile() {
    autoApplyCalls++;
  }
}

class _LateLoad extends PolicyDraftAction {
  final Completer<ProfilePolicyDraft?> pending;
  _LateLoad(this.pending);
  @override
  Future<ProfilePolicyDraft?> load(int profileId) => pending.future;
}

class _ConfirmBackup extends BackupAction {
  int calls = 0;
  bool confirmed = false;
  @override
  Future<bool> hasPolicyDrafts() async => true;
  @override
  Future<bool> backup(
    BackupDelivery deliver, {
    bool policyDraftsConfirmed = false,
  }) async {
    calls++;
    confirmed = policyDraftsConfirmed;
    return false;
  }
}

class _AndroidSelection extends PolicySelectionAction {
  @override
  bool get supportsManaged => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late ProviderContainer container;
  late _Core core;
  late _Setup setup;
  final profile = draftTestProfile(1);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('policy-widget-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
    await Future.wait([appPath.homeDirPath, appPath.tempPath]);
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    db = Database(NativeDatabase.memory());
    database = db;
    await db.profilesDao.putAll([profile.toCompanion()]);
    core = _Core();
    setup = _Setup();
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        policySelectionActionProvider.overrideWith(_AndroidSelection.new),
        setupActionProvider.overrideWith(() => setup),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
      ],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1400);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> seed(PolicyDraftDocument value) async {
    await db.profilePolicyDraftsDao.compareAndWrite(
      1,
      expectedRaw: null,
      rawContent: value.encode(),
    );
  }

  Future<String?> stored([int profileId = 1]) async =>
      (await db.profilePolicyDraftsDao.query(profileId).getSingleOrNull())
          ?.rawContent;

  Future<void> pump(
    WidgetTester tester, {
    Widget? child,
    Size size = const Size(1200, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: StatusManager(
            child: child ?? PolicyDraftView(profile: profile),
          ),
        ),
      ),
    );
    await settle(tester, 12);
  }

  Future<void> click(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find.byType(Scrollable).last;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 300, scrollable: scrollable);
      }
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, Finder field, String value) async {
    await click(tester, field);
    await click(tester, find.text(value).last);
  }

  Future<void> confirmForm(WidgetTester tester) => click(
    tester,
    find
        .descendant(
          of: find.byType(CommonDialog),
          matching: find.text('Confirm'),
        )
        .last,
  );

  Future<void> openDraft(WidgetTester tester, [Profile? value]) async {
    await pump(
      tester,
      child: Scaffold(
        body: ProfileItem(
          profile: value ?? profile,
          groupValue: null,
          onChanged: (_) => fail('draft entry must not select a profile'),
        ),
      ),
    );
    await click(tester, find.byTooltip('More'));
    await click(tester, find.text('Policy draft'));
    expect(find.byType(PolicyDraftView), findsOneWidget);
  }

  Future<void> editIpDefault(WidgetTester tester, String target) async {
    await click(tester, find.text('Default for unmatched IPs'));
    await choose(tester, find.byKey(const ValueKey('draft-target')), target);
    await confirmForm(tester);
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  Finder dialogAction(String label) => find.descendant(
    of: find.byType(CommonDialog),
    matching: find.text(label),
  );

  void noRuntimeChange() {
    expect(container.read(currentProfileIdProvider), isNull);
    expect(setup.autoApplyCalls, 0);
    verifyZeroInteractions(core);
  }

  testWidgets(
    'real profile menu opens an independent draft route without selecting or applying',
    (tester) async {
      var selected = false;
      await pump(
        tester,
        child: Scaffold(
          body: ProfileItem(
            profile: profile,
            groupValue: null,
            onChanged: (_) => selected = true,
          ),
        ),
      );
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Policy draft'));
      expect(find.byType(PolicyDraftView), findsOneWidget);
      expect(selected, isFalse);
      Navigator.of(tester.element(find.byType(PolicyDraftView))).pop();
      await settle(tester);
      noRuntimeChange();
    },
  );

  testWidgets(
    'real default editor saves, reopens and retains an explicit REJECT without applying',
    (tester) async {
      await pump(tester);
      await click(tester, find.text('Default for unmatched domains'));
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'REJECT',
      );
      await confirmForm(tester);
      await click(tester, find.byType(CommonFloatingActionButton));
      final first = PolicyDraftDocument.decode((await stored())!);
      expect(first.policy['domainDefault'], {
        'target': {'kind': 'reject'},
      });
      expect(first.policy['ipDefault'], isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await pump(tester);
      expect(find.text('Draft saved; not applied'), findsWidgets);
      expect(find.text('REJECT'), findsOneWidget);
      noRuntimeChange();
    },
  );

  testWidgets(
    'dirty menu route cancels system back then discards via the real back button without writing',
    (tester) async {
      await seed(completePolicyDraft());
      final initial = await stored();
      await openDraft(tester);
      await editIpDefault(tester, 'DIRECT');
      await systemBack(tester);
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await click(tester, dialogAction('Cancel'));
      expect(find.byType(PolicyDraftView), findsOneWidget);
      expect(find.text('Unsaved draft; not applied'), findsOneWidget);
      expect(await stored(), initial);
      await click(tester, find.byTooltip('Back'));
      await click(tester, dialogAction('Confirm'));
      expect(find.byType(PolicyDraftView), findsNothing);
      expect(await stored(), initial);
      expect(tester.takeException(), isNull);
      noRuntimeChange();
    },
  );

  testWidgets(
    'dirty menu route saves through PopScope and exits after DAO success',
    (tester) async {
      await seed(completePolicyDraft());
      await openDraft(tester);
      await editIpDefault(tester, 'DIRECT');
      await systemBack(tester);
      await click(tester, dialogAction('Save'));
      expect(find.byType(PolicyDraftView), findsNothing);
      expect(
        PolicyDraftDocument.decode((await stored())!).policy['ipDefault'],
        {'kind': 'direct'},
      );
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Policy draft'));
      expect(find.text('Draft saved; not applied'), findsOneWidget);
      expect(tester.takeException(), isNull);
      noRuntimeChange();
    },
  );

  for (final conflict in [false, true]) {
    testWidgets(
      'dirty route save ${conflict ? 'conflict' : 'SQL failure'} stays editable and clears loading',
      (tester) async {
        await seed(completePolicyDraft());
        final initial = (await stored())!;
        await openDraft(tester);
        await editIpDefault(tester, 'DIRECT');
        if (conflict) {
          await db.profilePolicyDraftsDao.compareAndWrite(
            1,
            expectedRaw: initial,
            rawContent: 'different raw',
          );
        } else {
          await db.customStatement(
            "CREATE TRIGGER fail_leave BEFORE INSERT ON profile_policy_drafts BEGIN SELECT RAISE(ABORT,'synthetic-sql-secret'); END",
          );
        }
        await systemBack(tester);
        await click(tester, dialogAction('Save'));
        expect(find.byType(PolicyDraftView), findsOneWidget);
        expect(find.text('Unsaved draft; not applied'), findsOneWidget);
        expect(find.textContaining('synthetic-sql-secret'), findsNothing);
        expect(await stored(), conflict ? 'different raw' : initial);
        final scaffold = tester.widget<CommonScaffold>(
          find.byType(CommonScaffold),
        );
        expect(scaffold.isLoading, isFalse);
        expect(scaffold.primaryAction!.onPressed, isNotNull);
        await click(tester, find.text('Default for unmatched IPs'));
        final field = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('draft-target')),
        );
        expect(field.initialValue, 'direct');
        await click(tester, dialogAction('Cancel'));
        expect(tester.takeException(), isNull);
        noRuntimeChange();
      },
    );
  }

  testWidgets('DAO barrier blocks editing and both back paths while saving', (
    tester,
  ) async {
    await seed(completePolicyDraft());
    await openDraft(tester);
    await editIpDefault(tester, 'DIRECT');
    final entered = Completer<void>();
    final release = Completer<void>();
    final barrier = db.transaction(() async {
      entered.complete();
      await release.future;
    });
    await settle(tester);
    await entered.future;
    try {
      await click(tester, find.byType(CommonFloatingActionButton));
      expect(
        tester.widget<CommonScaffold>(find.byType(CommonScaffold)).isLoading,
        isTrue,
      );
      await tester.tap(
        find.text('Default for unmatched IPs'),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byType(CommonDialog), findsNothing);
      await tester.tap(find.byTooltip('Back'), warnIfMissed: false);
      await systemBack(tester);
      expect(find.byType(CommonDialog), findsNothing);
      expect(find.byType(PolicyDraftView), findsOneWidget);
    } finally {
      release.complete();
      await barrier;
    }
    await settle(tester, 12);
    expect(
      tester.widget<CommonScaffold>(find.byType(CommonScaffold)).isLoading,
      isFalse,
    );
    expect(PolicyDraftDocument.decode((await stored())!).policy['ipDefault'], {
      'kind': 'direct',
    });
    expect(tester.takeException(), isNull);
    noRuntimeChange();
  });

  testWidgets(
    'disposed leave-save completes through the DAO without changing a new route or its CAS baseline',
    (tester) async {
      await seed(completePolicyDraft());
      final other = draftTestProfile(2);
      await db.profilesDao.putAll([other.toCompanion()]);
      await db.profilePolicyDraftsDao.compareAndWrite(
        2,
        expectedRaw: null,
        rawContent: completePolicyDraft().encode(),
      );
      await openDraft(tester);
      await editIpDefault(tester, 'DIRECT');
      await systemBack(tester);
      final entered = Completer<void>();
      final release = Completer<void>();
      final barrier = db.transaction(() async {
        entered.complete();
        await release.future;
      });
      await settle(tester);
      await entered.future;
      try {
        await click(tester, dialogAction('Save'));
        expect(
          tester.widget<CommonScaffold>(find.byType(CommonScaffold)).isLoading,
          isTrue,
        );
        final element = tester.element(find.byType(PolicyDraftView));
        Navigator.of(element).removeRoute(ModalRoute.of(element)!);
        await settle(tester);
        expect(find.byType(PolicyDraftView), findsNothing);
        await openDraft(tester, other);
      } finally {
        release.complete();
        await barrier;
      }
      await settle(tester, 12);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<PolicyDraftView>(find.byType(PolicyDraftView)).profile.id,
        2,
      );
      expect(find.text('Draft saved; not applied'), findsOneWidget);
      expect(
        PolicyDraftDocument.decode((await stored())!).policy['ipDefault'],
        {'kind': 'direct'},
      );
      await click(tester, find.text('Default for unmatched IPs'));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('draft-target')),
            )
            .initialValue,
        'reject',
      );
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'DIRECT',
      );
      await confirmForm(tester);
      await click(tester, find.byType(CommonFloatingActionButton));
      expect(
        PolicyDraftDocument.decode((await stored(2))!).policy['ipDefault'],
        {'kind': 'direct'},
      );
      expect(find.text('Draft saved; not applied'), findsOneWidget);
      expect(tester.takeException(), isNull);
      noRuntimeChange();
    },
  );

  testWidgets(
    'domain add edit move delete and save use the actual persisted order',
    (tester) async {
      await seed(completePolicyDraft());
      await pump(tester);
      await click(tester, find.byTooltip('Add Domain rules'));
      await choose(
        tester,
        find.byKey(const ValueKey('draft-choice-type')),
        'DOMAIN',
      );
      await tester.enterText(
        find.byKey(const ValueKey('draft-field-value')),
        'added.test',
      );
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'REJECT',
      );
      await confirmForm(tester);
      final first = find.byKey(const ValueKey('draft-domainRules-0'));
      await click(
        tester,
        find.descendant(of: first, matching: find.byTooltip('Move down')),
      );
      final second = find.byKey(const ValueKey('draft-domainRules-1'));
      await click(
        tester,
        find.descendant(of: second, matching: find.byTooltip('Delete')),
      );
      await click(tester, find.byType(CommonFloatingActionButton));
      final draft = PolicyDraftDocument.decode((await stored())!);
      expect(draft.rows('domainRules').map((r) => r['value']), [
        'exact.example.test',
        'lan.test',
        'denied.test',
        'added.test',
      ]);
      noRuntimeChange();
    },
  );

  testWidgets(
    'credential fields are masked and saving resource edits retains paired authentication',
    (tester) async {
      await seed(completePolicyDraft(credentials: true));
      await pump(tester);
      await click(tester, find.text('nodeA'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('draft-field-password')),
            )
            .obscureText,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('draft-field-username')),
            )
            .obscureText,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('draft-field-password')),
        'replacement-synthetic-secret',
      );
      await confirmForm(tester);
      await click(tester, find.byType(CommonFloatingActionButton));
      final draft = PolicyDraftDocument.decode((await stored())!);
      expect(
        draft.policy['proxies']['nodeA']['password'],
        'replacement-synthetic-secret',
      );
      expect(draft.policy['proxies']['nodeA']['username'], 'synthetic-user-测试');
      expect(find.textContaining('replacement-synthetic-secret'), findsNothing);
    },
  );

  testWidgets(
    'preview EditorPage and CodeForge contain only masked output; full copy requires confirmation',
    (tester) async {
      await tester.runAsync(initEditorNative);
      await seed(completePolicyDraft(credentials: true));
      await pump(tester);
      await click(tester, find.byTooltip('Generated draft preview'));
      await settle(tester, 12);
      final editorPage = tester.widget<EditorPage>(find.byType(EditorPage));
      expect(editorPage.readOnly, isTrue);
      expect(editorPage.content, isNot(contains('synthetic-password')));
      final editor = tester.widget<CodeForge>(find.byType(CodeForge));
      expect(editor.controller.text, isNot(contains('synthetic-user')));
      expect(editor.controller.text, contains('••••••'));
      Navigator.of(tester.element(find.byType(EditorPage))).pop();
      await settle(tester);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Copy full generated configuration'));
      expect(clipboard, isNull);
      await click(tester, find.text('Cancel').last);
      expect(clipboard, isNull);
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Copy full generated configuration'));
      await click(tester, find.text('Confirm').last);
      expect(clipboard, contains('synthetic-password-🙂'));
      expect(clipboard, contains('synthetic-user-测试'));
      noRuntimeChange();
    },
  );

  testWidgets(
    'CAS conflict and real DB failure preserve current storage and UI input, clear loading and hide errors',
    (tester) async {
      await seed(completePolicyDraft());
      await pump(tester);
      final initial = (await stored())!;
      await db.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: initial,
        rawContent: 'different raw',
      );
      await click(tester, find.text('Default for unmatched IPs'));
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'DIRECT',
      );
      await confirmForm(tester);
      await click(tester, find.byType(CommonFloatingActionButton));
      expect(await stored(), 'different raw');
      expect(find.textContaining('The stored draft changed.'), findsOneWidget);
      expect(
        tester.widget<CommonScaffold>(find.byType(CommonScaffold)).isLoading,
        isFalse,
      );
      await db.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: 'different raw',
        rawContent: initial,
      );
      await db.customStatement(
        "CREATE TRIGGER fail_draft BEFORE INSERT ON profile_policy_drafts BEGIN SELECT RAISE(ABORT,'synthetic-sql-secret'); END",
      );
      await click(tester, find.byType(CommonFloatingActionButton));
      expect(await stored(), initial);
      expect(find.textContaining('Could not save the draft.'), findsOneWidget);
      expect(find.textContaining('synthetic-sql-secret'), findsNothing);
      expect(
        tester.widget<CommonScaffold>(find.byType(CommonScaffold)).isLoading,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      noRuntimeChange();
    },
  );

  testWidgets(
    'opaque draft never enters editor or gets overwritten while opening',
    (tester) async {
      const raw = '{"draftVersion":99,"synthetic-secret":"do-not-show"}';
      await db.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: null,
        rawContent: raw,
      );
      await pump(tester);
      expect(find.textContaining('Unknown version'), findsOneWidget);
      expect(find.textContaining('do-not-show'), findsNothing);
      expect(find.byType(EditorPage), findsNothing);
      expect(await stored(), raw);
      noRuntimeChange();
    },
  );

  testWidgets(
    'late load completion after dispose does not update the released page',
    (tester) async {
      final pending = Completer<ProfilePolicyDraft?>();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          policySelectionActionProvider.overrideWith(_AndroidSelection.new),
          setupActionProvider.overrideWith(() => setup),
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          policyDraftActionProvider.overrideWith(() => _LateLoad(pending)),
        ],
      );
      globalState.container = container;
      container.listen(configProvider, (_, _) {});
      container.read(viewSizeProvider.notifier).value = const Size(1200, 1400);
      await pump(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      pending.complete(
        ProfilePolicyDraft(
          profileId: 1,
          rawContent: completePolicyDraft().encode(),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(await stored(), isNull);
    },
  );

  testWidgets('narrow layout renders real ordered rows without overflowing', (
    tester,
  ) async {
    await seed(completePolicyDraft());
    container.read(viewSizeProvider.notifier).value = const Size(360, 800);
    await pump(tester, size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Draft saved; not applied')).dy,
      greaterThanOrEqualTo(pageToolbarHeight),
    );
    await click(tester, find.text('Default for unmatched domains'));
    expect(tester.takeException(), isNull);
    await click(tester, find.text('Cancel').last);
  });

  testWidgets(
    'IP and DNS editors persist explicit choices and static group members',
    (tester) async {
      await seed(completePolicyDraft());
      await pump(tester);
      await click(tester, find.byTooltip('Add IP rules'));
      await tester.enterText(
        find.byKey(const ValueKey('draft-field-cidr')),
        '192.168.0.0/16',
      );
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'REJECT',
      );
      await confirmForm(tester);
      await click(tester, find.text('dnsA'));
      await tester.enterText(
        find.byKey(const ValueKey('draft-field-port')),
        '5354',
      );
      await confirmForm(tester);
      await click(tester, find.text('a'));
      await click(tester, find.text('nodeB').last);
      await confirmForm(tester);
      await click(tester, find.text('Default for unmatched domains'));
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'DIRECT',
      );
      await choose(
        tester,
        find.byKey(const ValueKey('draft-choice-dnsService')),
        'dnsA',
      );
      await confirmForm(tester);
      await click(tester, find.byType(CommonFloatingActionButton));
      final draft = PolicyDraftDocument.decode((await stored())!);
      expect(draft.rows('ipRules').last['cidr'], '192.168.0.0/16');
      expect(draft.rows('ipRules').last['target'], {'kind': 'reject'});
      expect(draft.policy['dnsServices']['dnsA']['port'], 5354);
      expect(draft.policy['groups']['a'], ['nodeA', 'nodeB']);
      expect(draft.policy['domainDefault'], {
        'target': {'kind': 'direct'},
        'dnsService': 'dnsA',
      });
      noRuntimeChange();
    },
  );

  testWidgets(
    'migration blocked state disables real preview while allowing draft save',
    (tester) async {
      final draft = completePolicyDraft()
        ..setMigration(
          migrationSnapshot(['MATCH,REJECT', 'DOMAIN,secret.test,DIRECT']),
        );
      await seed(draft);
      await pump(tester);
      expect(find.textContaining('Migration is blocked.'), findsWidgets);
      final scaffold = tester.widget<CommonScaffold>(
        find.byType(CommonScaffold),
      );
      expect(scaffold.iconActions.single.onPressed, isNull);
      await click(tester, find.byType(CommonFloatingActionButton));
      expect(
        PolicyDraftDocument.decode((await stored())!).migration,
        isNotNull,
      );
      expect(find.byType(EditorPage), findsNothing);
      noRuntimeChange();
    },
  );

  testWidgets(
    'independent rebuild requires confirmation before abandoning migration materials',
    (tester) async {
      final snapshot = migrationSnapshot(['MATCH,REJECT']);
      snapshot['customProxies'] = [
        {
          'name': 'node',
          'type': 'socks5',
          'server': 'synthetic.test',
          'port': 1080,
        },
      ];
      await seed(completePolicyDraft()..setMigration(snapshot));
      final initial = await stored();
      await openDraft(tester);
      expect(find.textContaining('Migration is blocked.'), findsWidgets);
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Create an independent draft'));
      expect(find.textContaining('will not preserve the old'), findsOneWidget);
      await click(tester, dialogAction('Cancel'));
      expect(await stored(), initial);
      expect(find.textContaining('Migration is blocked.'), findsWidgets);
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Create an independent draft'));
      await click(tester, dialogAction('Confirm'));
      expect(await stored(), initial);
      expect(find.textContaining('Migration is blocked.'), findsNothing);
      expect(find.text('Unsaved draft; not applied'), findsOneWidget);
      await click(tester, find.byType(CommonFloatingActionButton));
      final rebuilt = PolicyDraftDocument.decode((await stored())!);
      expect(rebuilt.migration, isNull);
      expect(rebuilt.policy['domainDefault'], isNull);
      expect(rebuilt.policy['ipDefault'], isNull);
      expect(tester.takeException(), isNull);
      noRuntimeChange();
    },
  );

  testWidgets(
    'sensitive local backup UI cancels before backup and confirms for this call only',
    (tester) async {
      container.dispose();
      final backup = _ConfirmBackup();
      container = ProviderContainer(
        overrides: [backupActionProvider.overrideWith(() => backup)],
      );
      globalState.container = container;
      container.listen(configProvider, (_, _) {});
      container.read(viewSizeProvider.notifier).value = const Size(1200, 1400);
      await pump(tester, child: const BackupAndRestore());
      await click(tester, find.text('Backup').last);
      expect(
        find.textContaining('unencrypted ZIP saved to your chosen local file'),
        findsOneWidget,
      );
      await click(tester, find.text('Cancel').last);
      expect(backup.calls, 0);
      await click(tester, find.text('Backup').last);
      await click(tester, find.text('Confirm').last);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(backup.calls, 1);
      expect(backup.confirmed, isTrue);
    },
  );

  testWidgets(
    'proxy group labels remain distinct from the DIRECT builtin target',
    (tester) async {
      final draft = completePolicyDraft()..setLabel('a', 'DIRECT');
      await seed(draft);
      await pump(tester);
      await click(tester, find.text('Default for unmatched IPs'));
      await choose(
        tester,
        find.byKey(const ValueKey('draft-target')),
        'Proxy group: DIRECT',
      );
      await confirmForm(tester);
      await click(tester, find.byType(CommonFloatingActionButton));
      expect(
        PolicyDraftDocument.decode((await stored())!).policy['ipDefault'],
        {'kind': 'proxy', 'group': 'a'},
      );
      expect(find.text('Proxy group: DIRECT'), findsWidgets);
      noRuntimeChange();
    },
  );

  testWidgets(
    'real policy selection confirms target, stays stopped, and explicit original mode preserves draft',
    (tester) async {
      await seed(completePolicyDraft());
      await pump(tester);
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Save and request application'));
      await click(tester, find.text('Proxy group: a'));
      await click(tester, find.text('Confirm').last);
      await settle(tester, 12);
      final selected = await db.profilePolicySelectionsDao.query(1).getSingle();
      expect(selected.rawContent, contains('maintenanceProxyTarget'));
      expect(container.read(currentProfileIdProvider), 1);
      expect(container.read(initProvider), isFalse);
      expect(setup.autoApplyCalls, 0);
      verifyZeroInteractions(core);
      final before = await stored();
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Use original profile'));
      await click(tester, find.text('Cancel').last);
      expect(
        await db.profilePolicySelectionsDao.query(1).getSingleOrNull(),
        isNotNull,
      );
      await click(tester, find.byTooltip('More'));
      await click(tester, find.text('Use original profile'));
      await click(tester, find.text('Confirm').last);
      await settle(tester, 12);
      expect(
        await db.profilePolicySelectionsDao.query(1).getSingleOrNull(),
        isNull,
      );
      expect(await stored(), before);
      expect(container.read(currentProfileIdProvider), 1);
      verifyZeroInteractions(core);
    },
  );
}
