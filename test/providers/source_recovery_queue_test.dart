import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';

class _Native extends Mock implements Service {}

class _Core extends Mock implements CoreHandlerInterface {}

class _Requests extends Request {
  _Requests(Service native) : super.scoped(native: native, isAndroid: true);
  @override
  Future<bool> materialRecoveryRequired() async => true;
}

class _Profiles extends ProfilesAction {
  _Profiles(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _Scripts extends ScriptsAction {
  _Scripts(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

class _NativeState extends NativeRequestState {
  @override
  Map<String, Object?> build() => const {};
}

class _HeldSetup extends SetupAction {
  _HeldSetup(Service native, Request client)
    : super.scoped(isAndroid: true, native: native, requests: client);
  final entered = Completer<void>();
  final release = Completer<void>();
  Map<String, Object?>? receivedRun;
  int? receivedSequence;
  final reservedSequences = <int>[];
  @override
  int reserveSetupSequence() {
    final sequence = super.reserveSetupSequence();
    reservedSequences.add(sequence);
    return sequence;
  }

  @override
  Future<bool> applyProfile({
    bool rebuildVpn = false,
    bool silence = false,
    bool force = false,
    bool allowSourceReview = true,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
  }) async {
    receivedRun = expectedRun;
    receivedSequence = setupSequence;
    entered.complete();
    await release.future;
    return super.applyProfile(
      silence: silence,
      force: force,
      allowSourceReview: allowSourceReview,
      allowBootstrap: allowBootstrap,
      expectedRun: expectedRun,
      setupSequence: setupSequence,
    );
  }
}

void main() {
  for (final caller in ['profile', 'script']) {
    testWidgets(
      'actual $caller recovery caller retains its original run across dispatch',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await AppLocalizations.load(const Locale('en'));
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('source-recovery-queue-'),
        ))!;
        AppPath.supportDirectory = () async => directory;
        AppPath.temporaryDirectory = () async => directory;
        AppPath.cacheDirectory = () async => directory;
        final store = db.Database(NativeDatabase.memory());
        db.database = store;
        final native = _Native();
        var run = <String, Object?>{
          'processEpoch': 'original-process',
          'intentRevision': 1,
          'configToken': 10,
          'revision': 1,
          'phase': 'failed',
          'reason': 'setupFailed',
          'intentRunning': false,
          'paused': false,
        };
        final original = Map<String, Object?>.of(run);
        final controls = <Map<String, Object?>>[];
        when(native.getRequestState).thenAnswer((_) async => Map.of(run));
        when(() => native.requestControl(any())).thenAnswer((call) async {
          final input = call.positionalArguments.single as Map<String, Object?>;
          controls.add(input);
          return switch (input['action']) {
            'attach' => {'client': 'recovery-client'},
            'inspect' => {
              'state': Map.of(run),
              'dataset': 1,
              'sourceRevision': 0,
              'owner': 1,
              'operation': 0,
            },
            _ => {'ready': true},
          };
        });
        final core = _Core();
        final sourceCalls = <String>[];
        when(() => core.sourceAcceptance(any())).thenAnswer((call) async {
          final input = call.positionalArguments.single as Map;
          sourceCalls.add(input['action'] as String);
          return switch (input['action']) {
            'inspectMaterialRecovery' => {
              'status': 'recovery',
              'recovery': {'snapshot': 'synthetic-existing-barrier'},
            },
            'recoverMaterialCommit' => {'status': 'recovered'},
            _ => throw StateError('unexpected source action $input'),
          };
        });
        final client = _Requests(native);
        final setup = _HeldSetup(native, client);
        final container = ProviderContainer(
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => const Size(1000, 900)),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            nativeRequestStateProvider.overrideWith(_NativeState.new),
            profilesActionProvider.overrideWith(() => _Profiles(client)),
            scriptsActionProvider.overrideWith(() => _Scripts(client)),
            setupActionProvider.overrideWith(() => setup),
          ],
        );
        globalState.container = container;
        await tester.runAsync(() async {
          client.attach(container);
          await client.ready();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(child: Scaffold()),
          ),
        );
        late Future<void> work;
        await tester.runAsync(() async {
          work = caller == 'profile'
              ? container
                    .read(profilesActionProvider.notifier)
                    .manageSourcePermissions(Profile.normal(label: 'synthetic'))
              : container
                    .read(scriptsActionProvider.notifier)
                    .manageSourcePermissions(Script.create(label: 'synthetic'));
        });
        for (
          var i = 0;
          i < 100 &&
              find.text(AppLocalizations.current.confirm).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(
          find.text(AppLocalizations.current.sourceRecoveryTitle),
          findsOneWidget,
        );
        expect(setup.reservedSequences, hasLength(1));
        await tester.tap(find.text(AppLocalizations.current.confirm));
        await tester.pumpAndSettle();
        for (var i = 0; i < 100 && !setup.entered.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(
          setup.entered.isCompleted,
          true,
          reason:
              'calls=$sourceCalls; attached=${client.hasNativeClient}; run=$run',
        );
        expect(setup.receivedRun, original);
        expect(setup.receivedSequence, setup.reservedSequences.single);
        run = {
          ...run,
          'intentRevision': 2,
          'configToken': 11,
          'revision': 2,
          'phase': 'preparing',
          'intentRunning': true,
          'source': 'tile',
        };
        setup.release.complete();
        await tester.runAsync(() => work);
        expect(sourceCalls, [
          'inspectMaterialRecovery',
          'inspectMaterialRecovery',
          'recoverMaterialCommit',
        ]);
        verifyNever(() => core.getConfigState());
        verifyNever(
          () => native.failRunIntent(
            any(),
            token: any(named: 'token'),
            unregistered: any(named: 'unregistered'),
          ),
        );
        expect(
          controls.where(
            (c) => ['begin', 'permit', 'grant'].contains(c['action']),
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await client.detach();
          container.dispose();
          await store.close();
          await directory.delete(recursive: true);
        });
      },
    );
  }
}
