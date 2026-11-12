import 'dart:async';

import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/source_review_status.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/local_groups.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:fl_clash/views/proxies/group_routing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _RegexCore implements CoreController {
  @override
  Future<Map<String, dynamic>> sourceAcceptance(
    Map<String, Object?> input,
  ) async => {
    'status': 'matched',
    'matches': (input['names'] as List<String>)
        .where(RegExp(input['pattern'] as String).hasMatch)
        .toList(),
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fact extends ConfigState {
  _Fact(this.id);
  final int id;
  @override
  ConfigViewState build() => ConfigViewState(
    fact: ConfigFact(profileId: id, phase: 'ready'),
  );
}

class _Groups extends Groups {
  _Groups(this.groups);
  final List<Group> groups;
  @override
  List<Group> build() =>
      groups.map((group) => group.copyWith(hidden: false)).toList();
}

class _ProxyActions extends ProxiesAction {
  final changes = <String>[];
  @override
  void build() {}
  @override
  Future<void> updateGroups({Future<bool> Function()? isCurrent}) async {}
  @override
  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
    ConfigFact? observed,
    bool transient = false,
  }) async {
    changes.add('$groupName:$proxyName');
    ref.read(groupsProvider.notifier).value = [
      for (final group in ref.read(groupsProvider))
        group.name == groupName ? group.copyWith(now: proxyName) : group,
    ];
  }
}

class _Profiles extends ProfilesAction {
  final writes = <List<LocalProxyGroup>>[];
  Completer<void>? applyGate;
  Exception? error;
  int reviews = 0;
  @override
  Future<void> manageSourcePermissions(
    Profile profile, {
    bool review = false,
  }) async {
    reviews++;
  }

  @override
  void build() {}
  @override
  Future<void> saveLocalGroups(
    Profile profile,
    List<LocalProxyGroup> groups, {
    void Function()? onSaved,
  }) async {
    if (error != null) throw error!;
    writes.add(groups);
    ref.read(profilesProvider.notifier).initialize([
      profile.copyWith(localGroups: groups),
    ]);
    onSaved?.call();
    await applyGate?.future;
    final names = {
      ...profile.localGroups.map((group) => group.name),
      ...groups.map((group) => group.name),
    };
    ref.read(groupsProvider.notifier).value = [
      for (final runtime in ref.read(groupsProvider))
        runtime.copyWith(
          all: [
            for (final node in runtime.all)
              if (!names.contains(node.name)) node,
            for (final local in groups)
              if (local.enabled && local.entrances.contains(runtime.name))
                Proxy(name: local.name, type: local.type.name),
          ],
        ),
    ];
  }
}

void main() {
  const nodes = [
    Proxy(name: 'Node A', type: 'Socks5'),
    Proxy(name: 'Node B', type: 'Socks5'),
  ];
  final profile = Profile.normal(label: 'Fixture');
  late ProviderContainer container;
  late _Profiles actions;
  late _ProxyActions proxyActions;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    actions = _Profiles();
    proxyActions = _ProxyActions();
    container = ProviderContainer(
      overrides: [
        profilesActionProvider.overrideWith(() => actions),
        proxiesActionProvider.overrideWith(() => proxyActions),
        coreHandlerProvider.overrideWithValue(_RegexCore()),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        configStateProvider.overrideWith(() => _Fact(profile.id)),
        groupsProvider.overrideWith(
          () => _Groups([
            const Group(
              name: 'Main',
              type: GroupType.Selector,
              all: nodes,
              now: 'Node A',
            ),
          ]),
        ),
        policySelectionProvider.overrideWith((ref, id) => Stream.value(null)),
        profileReviewStatusProvider.overrideWith(
          (ref, profile) async => SourceReviewStatus.ready,
        ),
      ],
    );
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = const Size(400, 900);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('node picker deduplicates leaves and excludes groups and built-ins', () {
    expect(
      localGroupNodes([
        const Group(
          name: 'Main',
          type: GroupType.Selector,
          all: [
            ...nodes,
            Proxy(name: 'DIRECT', type: 'Direct'),
            Proxy(name: 'Auto', type: 'URLTest'),
          ],
        ),
        const Group(name: 'Auto', type: GroupType.URLTest, all: nodes),
      ]).map((node) => node.name),
      ['Node A', 'Node B'],
    );
  });

  testWidgets('create from manager selects nodes and saves once', (
    tester,
  ) async {
    await pump(tester, const LocalGroupsView(initialParent: 'Main'));
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mine');
    await tester.ensureVisible(find.text('Node B'));
    await tester.tap(find.text('Node B'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(actions.writes, hasLength(1));
    expect(actions.writes.single.single.nodes, ['Node B']);
    expect(actions.writes.single.single.parent, isNull);
    expect(actions.writes.single.single.type, GroupType.Fallback);
    expect(find.byType(LocalGroupEditor), findsNothing);
    expect(find.text('Mine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('speed test toggles URL visibility and preserves its value', (
    tester,
  ) async {
    await pump(tester, const LocalGroupsView());
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(find.text('Enable speed test'), findsOneWidget);
    expect(find.text('Failover'), findsNothing);
    expect(find.text('Test URL'), findsNothing);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    await tester.tap(find.text('Enable speed test'));
    await tester.pumpAndSettle();
    final url = find.widgetWithText(TextField, 'Test URL');
    expect(url, findsOneWidget);
    await tester.enterText(url, 'https://example.com/custom-check');
    await tester.tap(find.text('Enable speed test'));
    await tester.pumpAndSettle();
    expect(find.text('Test URL'), findsNothing);
    await tester.tap(find.text('Enable speed test'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(url).controller!.text,
      'https://example.com/custom-check',
    );
    await tester.tap(find.text('Enable speed test'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mine');
    await tester.ensureVisible(find.text('Node A'));
    await tester.tap(find.text('Node A'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(actions.writes.single.single.type, GroupType.Fallback);
    expect(
      actions.writes.single.single.testUrl,
      'https://example.com/custom-check',
    );
  });

  testWidgets(
    'enabled speed test validates URL without blocking disabled save',
    (tester) async {
      LocalProxyGroup? saved;
      await pump(
        tester,
        LocalGroupEditor(
          value: const LocalProxyGroup(
            id: 7,
            name: 'Mine',
            type: GroupType.URLTest,
            nodes: ['Node A'],
            testUrl: 'https://example.com/saved-check',
          ),
          nodes: nodes,
          matchNodes: (_) async => [],
          reservedNames: const {},
          onSave: (group) async => saved = group,
        ),
      );
      expect(find.text('Test URL'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Test URL'),
        'invalid',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.byType(LocalGroupEditor), findsOneWidget);
      await tester.tap(find.text('Enable speed test'));
      await tester.pumpAndSettle();
      expect(find.text('Test URL'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.type, GroupType.Fallback);
      expect(saved!.testUrl, 'https://example.com/saved-check');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled editor never writes and search filters nodes', (
    tester,
  ) async {
    await pump(tester, const LocalGroupsView());
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Node B');
    await tester.pumpAndSettle();
    expect(find.text('Node A'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'Node B'), findsOneWidget);
    globalState.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(actions.writes, isEmpty);
  });

  testWidgets('enable disable and confirmed delete update the list', (
    tester,
  ) async {
    container.read(profilesProvider.notifier).initialize([
      profile.copyWith(
        localGroups: [
          const LocalProxyGroup(id: 7, name: 'Mine', nodes: ['Node A']),
        ],
      ),
    ]);
    await pump(tester, const LocalGroupsView());
    await tester.tap(find.byTooltip('Actions for Mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable'));
    await tester.pumpAndSettle();
    expect(actions.writes.last.single.enabled, isFalse);
    await tester.tap(find.byTooltip('Actions for Mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(actions.writes.last.single.enabled, isTrue);
    await tester.tap(find.byTooltip('Actions for Mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.writes.last, isEmpty);
    expect(find.text('Mine'), findsNothing);
  });

  testWidgets('invalid names and empty members stay in the editor', (
    tester,
  ) async {
    await pump(
      tester,
      LocalGroupEditor(
        value: const LocalProxyGroup(id: 7, name: ''),
        nodes: nodes,
        matchNodes: (_) async => ['Node B'],
        reservedNames: const {'Main'},
        onSave: (_) async => fail('invalid data was saved'),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Main');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a unique group name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Mine');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Select at least one available node.'), findsOneWidget);
  });

  testWidgets(
    'old Profile selections do not block disabling current saved groups',
    (tester) async {
      container
          .read(configStateProvider.notifier)
          .accept(
            ConfigFact(
              runtimeEpoch: 'fixture',
              profileId: profile.id + 1,
              phase: 'ready',
            ),
            authoritative: true,
          );
      container.read(groupsProvider.notifier).value = [
        const Group(
          name: 'Main',
          type: GroupType.Selector,
          all: nodes,
          now: 'Mine',
        ),
      ];
      container.read(profilesProvider.notifier).initialize([
        profile.copyWith(
          localGroups: [
            const LocalProxyGroup(id: 7, name: 'Mine', nodes: ['Node A']),
          ],
        ),
      ]);
      await pump(tester, const LocalGroupsView());
      await tester.tap(find.byTooltip('Actions for Mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable'));
      await tester.pumpAndSettle();
      expect(actions.writes.single.single.enabled, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save failure keeps edits and releases progress', (tester) async {
    await pump(
      tester,
      LocalGroupEditor(
        value: const LocalProxyGroup(
          id: 7,
          name: 'Mine',
          nodes: ['Node A'],
          testUrl: 'https://example.com/test',
        ),
        nodes: nodes,
        matchNodes: (_) async => ['Node B'],
        reservedNames: const {},
        onSave: (_) async => throw StateError('controlled failure'),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('controlled failure'), findsOneWidget);
    expect(find.byType(LocalGroupEditor), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Mine',
    );
  });
  testWidgets('regex replaces selection and clearing restores manual state', (
    tester,
  ) async {
    LocalProxyGroup? saved;
    await pump(
      tester,
      LocalGroupEditor(
        value: const LocalProxyGroup(
          id: 7,
          name: 'Mine',
          nodes: ['Node A'],
          testUrl: 'https://example.com/test',
        ),
        nodes: nodes,
        reservedNames: const {},
        matchNodes: (pattern) async {
          if (pattern == '[') throw const FormatException('invalid expression');
          return nodes
              .map((node) => node.name)
              .where(RegExp(pattern).hasMatch)
              .toList();
        },
        onSave: (group) async => saved = group,
      ),
    );
    final query = find.byType(TextField).last;
    await tester.ensureVisible(query);
    await tester.enterText(query, 'Node B');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Node A'), findsNothing);
    final matched = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Node B'),
    );
    expect(matched.value, true);
    expect(matched.onChanged, isNotNull);
    await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'Node B'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Node B'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Node B'),
          )
          .value,
      false,
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Node B'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Node B'),
          )
          .value,
      true,
    );
    await tester.ensureVisible(query);
    await tester.enterText(query, '[');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.textContaining('invalid expression'), findsOneWidget);
    await tester.enterText(query, '');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Node A'),
          )
          .value,
      true,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Node B'),
          )
          .value,
      false,
    );
    expect(find.byType(DropdownButtonFormField<GroupType>), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.nodes, ['Node A']);
    expect(saved!.regex, '');
    expect(saved!.type, GroupType.Fallback);
  });

  testWidgets('group row opens display page and edit has a separate action', (
    tester,
  ) async {
    container.read(profilesProvider.notifier).initialize([
      profile.copyWith(
        localGroups: [
          const LocalProxyGroup(
            id: 7,
            name: 'Mine',
            nodes: ['Node A'],
            type: GroupType.Fallback,
          ),
        ],
      ),
    ]);
    container.read(groupsProvider.notifier).value = [
      const Group(
        name: 'Main',
        type: GroupType.Selector,
        all: nodes,
        now: 'Node A',
      ),
      const Group(
        name: 'Mine',
        type: GroupType.Fallback,
        all: nodes,
        now: 'Node A',
      ),
    ];
    await pump(tester, const LocalGroupsView());
    expect(find.textContaining('Subscription ·'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    expect(find.byType(LocalGroupDetail), findsOneWidget);
    expect(find.byType(LocalGroupEditor), findsNothing);
    expect(find.text('Preferred node: Node A'), findsOneWidget);
    expect(find.text('Restore automatic'), findsNothing);
  });
  testWidgets(
    'subscription selector switches immediately without an edit or save step',
    (tester) async {
      await pump(tester, const LocalGroupsView());
      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tap a node to switch immediately. No save is needed.'),
        findsOneWidget,
      );
      expect(find.text('Preferred node: Node A'), findsOneWidget);
      await tester.tap(find.text('Node B'));
      await tester.pumpAndSettle();
      expect(proxyActions.changes, ['Main:Node B']);
      expect(find.text('Preferred node: Node B'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(actions.writes, isEmpty);
    },
  );

  testWidgets('disabled group display retains its saved members', (
    tester,
  ) async {
    container.read(profilesProvider.notifier).initialize([
      profile.copyWith(
        localGroups: [
          const LocalProxyGroup(
            id: 7,
            name: 'Disabled group',
            enabled: false,
            nodes: ['Node A'],
            type: GroupType.Fallback,
          ),
        ],
      ),
    ]);
    await pump(tester, const LocalGroupsView());
    await tester.tap(find.text('Disabled group'));
    await tester.pumpAndSettle();
    expect(find.byType(LocalGroupDetail), findsOneWidget);
    expect(find.text('Node A'), findsOneWidget);
    expect(find.textContaining('This group is not active'), findsOneWidget);
    expect(actions.writes, isEmpty);
  });
  testWidgets('saving returns after local commit while applying continues', (
    tester,
  ) async {
    actions.applyGate = Completer<void>();
    await pump(tester, const LocalGroupsView());
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Saved group');
    await tester.ensureVisible(find.text('Node A'));
    await tester.tap(find.text('Node A'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LocalGroupEditor), findsNothing);
    expect(find.text('Saved group'), findsOneWidget);
    expect(actions.applyGate!.isCompleted, false);
    actions.applyGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('regex selections persist manual exclusions', (tester) async {
    LocalProxyGroup? saved;
    await pump(
      tester,
      LocalGroupEditor(
        value: const LocalProxyGroup(
          id: 9,
          name: 'Regex group',
          regex: 'Node',
          matchedNodes: ['Node A', 'Node B'],
          nodes: ['Node A'],
          testUrl: 'https://example.com/test',
        ),
        nodes: nodes,
        reservedNames: const {},
        matchNodes: (_) async => ['Node A', 'Node B'],
        onSave: (group) async => saved = group,
      ),
    );
    expect(find.byTooltip('Regular expression help'), findsOneWidget);
    expect(find.text('Regular expression help'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'Node B'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Node B'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.excludedNodes, ['Node B']);
    expect(saved!.effectiveNodes, ['Node A']);
    expect(LocalProxyGroup.fromJson(saved!.toJson()), saved);
  });
  testWidgets('proxy pages survive entering management during preparation', (
    tester,
  ) async {
    await pump(tester, const ProxiesView());
    expect(find.text('Node A', findRichText: true), findsOneWidget);
    final tab = tester.state(find.byType(ProxiesTabView));
    final progress = container.read(proxyPreparationProvider.notifier);
    final sequence = progress.start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('More').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Group management'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LocalGroupsView), findsOneWidget);
    globalState.navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Node A', findRichText: true), findsOneWidget);
    expect(identical(tester.state(find.byType(ProxiesTabView)), tab), true);
    progress.finish(sequence, failed: false);
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(ProxiesTabView)), tab), true);
    expect(tester.takeException(), isNull);
  });

  void routingFixture({
    List<String> parents = const [],
    String now = 'Node A',
  }) {
    container.read(profilesProvider.notifier).initialize([
      profile.copyWith(
        localGroups: [
          LocalProxyGroup(
            id: 7,
            name: 'Mine',
            nodes: ['Node A'],
            parents: parents,
            type: GroupType.Fallback,
          ),
        ],
      ),
    ]);
    container.read(groupsProvider.notifier).value = [
      for (final name in ['Main', 'Media'])
        Group(
          name: name,
          type: GroupType.Selector,
          now: now,
          all: [
            ...nodes,
            if (parents.contains(name))
              const Proxy(name: 'Mine', type: 'Fallback'),
          ],
        ),
      const Group(
        name: 'Mine',
        type: GroupType.Fallback,
        now: 'Node A',
        all: nodes,
      ),
    ];
  }

  Future<void> openReferences(WidgetTester tester, {Profile? snapshot}) async {
    final current = snapshot ?? container.read(currentProfileProvider)!;
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => BaseNavigator.push(
                context,
                LocalGroupRoutingView(profile: current, localId: 7),
              ),
              child: const Text('References'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('References'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'references can be added to multiple targets without switching selections',
    (tester) async {
      routingFixture();
      await openReferences(tester);
      expect(find.text('View group'), findsNothing);
      expect(find.text('Use now'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Main'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Media'));
      actions.applyGate = Completer<void>();
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Applying configuration…'), findsOneWidget);
      expect(find.byType(LocalGroupRoutingView), findsOneWidget);
      actions.applyGate!.complete();
      await tester.pumpAndSettle();
      expect(actions.writes.single.single.entrances, {'Main', 'Media'});
      expect(
        find.text('References applied. Current selections were kept.'),
        findsWidgets,
      );
      expect(find.byType(LocalGroupRoutingView), findsNothing);
      expect(proxyActions.changes, isEmpty);
      expect(container.read(groupsProvider).first.now, 'Node A');
    },
  );

  testWidgets('references are preselected and can be removed independently', (
    tester,
  ) async {
    routingFixture(parents: ['Main', 'Media']);
    await openReferences(tester);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Main'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(actions.writes.single.single.entrances, {'Media'});
    expect(find.byType(LocalGroupRoutingView), findsNothing);
    expect(
      container
          .read(groupsProvider)
          .first
          .all
          .any((node) => node.name == 'Mine'),
      false,
    );
    expect(proxyActions.changes, isEmpty);
  });

  testWidgets(
    'removing an active reference keeps the draft and explains the conflict',
    (tester) async {
      routingFixture(parents: ['Main'], now: 'Mine');
      await openReferences(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Main'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(actions.writes, isEmpty);
      expect(
        find.text(
          'Choose another node or group before removing this reference, disabling or deleting this group.',
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Main'),
            )
            .value,
        false,
      );
      expect(find.byType(LocalGroupRoutingView), findsOneWidget);
    },
  );

  testWidgets(
    'unavailable accepted permissions keep the draft and offer an explicit review action',
    (tester) async {
      routingFixture();
      actions.error = const RequestUnavailable(
        'local_groups_source_unavailable',
      );
      await openReferences(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Main'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The accepted configuration or its permissions are unavailable. Check source permissions in Profiles.',
        ),
        findsWidgets,
      );
      expect(find.text('Review source'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Main'),
            )
            .value,
        true,
      );
      expect(actions.writes, isEmpty);
      await tester.tap(find.text('Review source'));
      await tester.pumpAndSettle();
      expect(actions.reviews, 1);
      expect(actions.writes, isEmpty);
      expect(proxyActions.changes, isEmpty);
      actions.error = null;
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('References applied. Current selections were kept.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'a stale reference page reports a changed profile instead of crashing',
    (tester) async {
      routingFixture(parents: ['Main']);
      final snapshot = container.read(currentProfileProvider)!;
      container.read(profilesProvider.notifier).initialize([]);
      await openReferences(tester, snapshot: snapshot);
      expect(
        find.text(
          'The configuration changed. Refresh group management and retry.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(actions.writes, isEmpty);
    },
  );
}
