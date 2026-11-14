import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/features/overwrite/rule.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/application_host_rule.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';
import '../helpers/exit_groups.dart';

class _UiRouting extends ApplicationRoutingController {
  bool fail = false;
  @override
  ApplicationRoutingOperation build() => const ApplicationRoutingOperation();
  @override
  Future<void> saveHostRules(
    List<Rule> hostRules, {
    required int expectedProfileId,
  }) async {
    for (final host in hostRules) {
      await database.rulesDao.putGlobalRule(host);
    }
    final previous = await database.readApplicationRouting();
    await database.writeApplicationRouting(
      previous.copyWith(
        rules: {
          ...previous.rules,
          for (final package
              in hostRules
                  .map((rule) => rule.hostBinding?.packageName)
                  .whereType<String>())
            package:
                previous.rules[package] ??
                ApplicationRouteRule(packageName: package, hasDefault: false),
        },
      ),
    );
    if (fail) throw StateError('controlled adoption failure');
  }

  @override
  Future<void> setEnabled(Iterable<String> packages, bool enabled) async {
    final settings = await database.readApplicationRouting();
    await database.writeApplicationRouting(
      settings.copyWith(
        rules: {
          ...settings.rules,
          for (final package in packages)
            package: settings.rules[package]!.copyWith(enabled: enabled),
        },
      ),
    );
  }

  @override
  Future<void> deleteHostRules(Iterable<int> ids) =>
      database.rulesDao.delRules(ids);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database store;
  late ProviderContainer container;
  late _UiRouting routing;
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store = Database(NativeDatabase.memory());
    database = store;
    routing = _UiRouting();
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => 7),
        currentProfileProvider.overrideWith(
          (_) => const Profile(id: 7, autoUpdateDuration: Duration(hours: 1)),
        ),
        configStateProvider.overrideWith(TestConfigState.new),
        applicationRoutingControllerProvider.overrideWith(() => routing),
        runControlProvider.overrideWithValue(false),
        globalLocalGroupsProvider.overrideWith((_) => Stream.value(const [])),
        groupsProvider.overrideWith(() => TestExitGroups(const ['Node A'])),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(420, 1000)),
      ],
    );
    container.listen(currentProfileIdProvider, (_, _) {});
    container.listen(currentProfileProvider, (_, _) {});
    globalState.container = container;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await store.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => BaseNavigator.push(
                  context,
                  const ApplicationHostRuleView(
                    host: 'example.test',
                    packages: ['a'],
                    appLabel: 'Browser',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  Future<void> remove(WidgetTester tester) async {
    await tester.tap(find.byTooltip(currentAppLocalizations.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text(currentAppLocalizations.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(currentAppLocalizations.confirm));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'scope switching preserves drafts and creation edits the same persisted rule',
    (tester) async {
      await pump(tester);
      expect(find.byType(RuleEditorForm), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'DIRECT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REJECT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All apps'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'DIRECT'), findsOneWidget);
      await tester.tap(find.text('This app'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'REJECT'), findsOneWidget);
      await save(tester, 'Create rule');
      final first = (await store.rulesDao.hostRules()).single;
      expect(first.hostBinding!.packageName, 'a');
      expect(first.ruleTarget, 'REJECT');
      expect((await store.readApplicationRouting()).rules['a']!.enabled, false);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.text(currentAppLocalizations.appHostAppDisabled),
        findsOneWidget,
      );
      await save(tester, currentAppLocalizations.save);
      expect((await store.rulesDao.hostRules()).single.id, first.id);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'deleting switches to the other existing scope then returns to the list',
    (tester) async {
      await pump(tester);
      await save(tester, 'Create rule');
      await tester.tap(find.text('All apps'));
      await tester.pumpAndSettle();
      await save(tester, 'Create rule');
      expect(await store.rulesDao.hostRules(), hasLength(2));
      await remove(tester);
      final segment = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(segment.selected, {false});
      expect(await store.rulesDao.hostRules(), hasLength(1));
      await remove(tester);
      expect(find.byType(ApplicationHostRuleView), findsNothing);
      expect(await store.rulesDao.hostRules(), isEmpty);
    },
  );
  testWidgets(
    'an adoption failure keeps a saved record in edit state for retry',
    (tester) async {
      await pump(tester);
      routing.fail = true;
      await save(tester, 'Create rule');
      expect(await store.rulesDao.hostRules(), hasLength(1));
      expect(
        find.widgetWithText(FilledButton, currentAppLocalizations.save),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      routing.fail = false;
      await save(tester, currentAppLocalizations.save);
      expect(await store.rulesDao.hostRules(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
