import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/boot_fixture.dart';
import 'helpers/test_app.dart';

class _Core extends CoreAction {
  int starts = 0;
  Completer<void>? entered, release;
  @override
  Future<void> startCore() async {
    starts++;
    entered?.complete();
    await release?.future;
  }
}

class _Setup extends SetupAction {
  final modes = <bool>[];
  int initializations = 0;
  @override
  void build() {}
  @override
  Future<void> initStatus({
    bool recovery = false,
    Future<bool> Function()? isCurrent,
  }) async {
    initializations++;
    if (isCurrent == null || await isCurrent()) modes.add(recovery);
  }
}

class _Exit extends SystemAction {
  final saves = <bool>[];
  @override
  Future<void> handleExit([bool needSave = true]) async {
    saves.add(needSave);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() async {
    await preferences.isInit;
  });
  late ProviderContainer container;
  late _Core core;
  late _Setup setup;
  late _Exit exitAction;
  setUp(() {
    globalState.isAttach = false;
    core = _Core();
    setup = _Setup();
    exitAction = _Exit();
    container = ProviderContainer(
      overrides: [
        coreActionProvider.overrideWith(() => core),
        setupActionProvider.overrideWith(() => setup),
        systemActionProvider.overrideWith(() => exitAction),
        currentProfileIdProvider.overrideWithBuild((_, _) => 7),
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(autoRun: true),
        ),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(800, 600)),
      ],
    );
    globalState.container = container;
  });
  tearDown(() {
    container.dispose();
    globalState.isAttach = false;
  });

  Bootstrap startup(BootFixture fixture) => Bootstrap.scoped(
    guard: fixture.guard(),
    preparePresentation: () {},
    checkPermissions: () {},
  );

  for (final phase in [BootPhase.recovery, BootPhase.core, BootPhase.setup]) {
    for (final replacement in [false, true]) {
      testWidgets(
        'phase ${phase.name} write cannot continue after ${replacement ? 'replacement' : 'close'}',
        (tester) async {
          await tester.runAsync(() => preferences.isInit);
          final fixture = BootFixture(
            raw: phase == BootPhase.recovery
                ? BootFixture.encode(interruptedBoot())
                : null,
          );
          final guard = fixture.guard();
          await guard.evaluate(profileId: 7);
          final entered = Completer<void>(), release = Completer<void>();
          fixture.intercept = (action, args) async {
            if (action == 'write' &&
                jsonDecode(args['record'] as String)['phase'] == phase.name &&
                !entered.isCompleted) {
              entered.complete();
              await release.future;
              return {'status': 'stale', 'current': false};
            }
            return fixture.respond(action, args);
          };
          final boot = Bootstrap.scoped(
            guard: guard,
            preparePresentation: () {},
            checkPermissions: () {},
          );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const TestApp(locale: Locale('en'), child: SizedBox()),
            ),
          );
          var followed = false;
          final work = boot.runAfterAttach([
            () {
              followed = true;
            },
          ]);
          await tester.pumpAndSettle();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(entered.isCompleted, true);
          if (replacement) {
            fixture.current = false;
          } else {
            await guard.markClosed();
          }
          release.complete();
          await tester.pumpAndSettle();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(core.starts, phase == BootPhase.setup ? 1 : 0);
          expect(setup.initializations, 0);
          expect(find.byType(AlertDialog), findsNothing);
          expect(await work, false);
          expect(followed, false);
        },
      );
    }
  }

  test(
    'concurrent attach coalesces and completed continuation stops at exit',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard();
      await guard.evaluate(profileId: 7);
      final boot = Bootstrap.scoped(
        guard: guard,
        preparePresentation: () {},
        checkPermissions: () {},
      );
      final a = boot.attach(), b = boot.attach();
      expect(identical(a, b), true);
      expect(await a, true);
      expect(core.starts, 1);
      expect(setup.modes, [false]);
      final actions = <String>[];
      expect(
        await boot.runAfterAttach([
          () {
            actions.add('maintenance');
            return guard.markClosed();
          },
          () {
            actions.add('links');
          },
          () {
            actions.add('shortcuts');
          },
        ]),
        false,
      );
      expect(actions, ['maintenance']);
    },
  );

  test(
    'exit while Core connection awaits aborts setup and Application followups',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard();
      await guard.evaluate(profileId: 7);
      final boot = Bootstrap.scoped(
        guard: guard,
        preparePresentation: () {},
        checkPermissions: () {},
      );
      core.entered = Completer<void>();
      core.release = Completer<void>();
      var followed = false;
      final work = boot.runAfterAttach([
        () {
          followed = true;
        },
      ]);
      await core.entered!.future;
      await guard.markClosed();
      core.release!.complete();
      expect(await work, false);
      expect(setup.modes, isEmpty);
      expect(followed, false);
      expect(container.read(initProvider), false);
    },
  );

  for (final rebuild in [false, true]) {
    testWidgets(
      'damaged record ${rebuild ? 'rebuild' : 'keep'} uses real prompt and preserves settings',
      (tester) async {
        final fixture = BootFixture(raw: '{private malformed');
        final guard = fixture.guard();
        await guard.evaluate(profileId: 7);
        final boot = Bootstrap.scoped(
          guard: guard,
          preparePresentation: () {},
          checkPermissions: () {},
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(locale: Locale('en'), child: SizedBox()),
          ),
        );
        final work = boot.attach();
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(
          find.text(rebuild ? 'Rebuild startup record' : 'Keep and continue'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        expect(fixture.raw, '{private malformed');
        await tester.tap(
          find.text(rebuild ? 'Rebuild startup record' : 'Keep and continue'),
        );
        await tester.pumpAndSettle();
        expect(await work, true);
        expect(setup.modes, [true]);
        expect(container.read(currentProfileIdProvider), 7);
        expect(container.read(appSettingProvider).autoRun, true);
        expect(
          rebuild
              ? fixture.record?.stage == BootStage.running
              : fixture.raw == '{private malformed',
          true,
        );
      },
    );
  }

  test(
    'engine replacement aborts before any Core or setup operation',
    () async {
      final fixture = BootFixture()..current = false;
      expect(
        await startup(fixture).runAfterAttach([
          () {
            fail('old Application continued');
          },
        ]),
        false,
      );
      expect(core.starts, 0);
      expect(setup.modes, isEmpty);
    },
  );

  for (final replaced in [false, true]) {
    testWidgets(
      'unavailable preferences ${replaced ? 'replacement' : 'confirmation'} abort Core setup',
      (tester) async {
        await tester.runAsync(() => preferences.isInit);
        final previous = preferences.sharedPreferencesCompleter;
        preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
          ..complete(null);
        addTearDown(() {
          preferences.sharedPreferencesCompleter = previous;
        });
        final fixture = BootFixture();
        final guard = fixture.guard();
        await guard.evaluate(profileId: 7, preferencesAvailable: false);
        final boot = Bootstrap.scoped(
          guard: guard,
          preparePresentation: () {},
          checkPermissions: () {},
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(locale: Locale('en'), child: SizedBox()),
          ),
        );
        final work = boot.attach();
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        if (replaced) fixture.current = false;
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(await work, false);
        expect(exitAction.saves, replaced ? isEmpty : [false]);
        expect(core.starts, 0);
        expect(setup.modes, isEmpty);
        expect(
          fixture.calls.where((c) => c.$1 == 'begin' || c.$1 == 'write'),
          isEmpty,
        );
      },
    );
  }
}
