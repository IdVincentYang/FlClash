import 'dart:async';

import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Native extends Mock implements Service {}

ProviderContainer _recoveryContainer(_Native native) => ProviderContainer(
  overrides: [
    setupActionProvider.overrideWith(
      () => SetupAction.scoped(
        isAndroid: true,
        native: native,
        requests: Request.scoped(native: native, isAndroid: true),
      ),
    ),
    nativeRequestStateProvider.overrideWith(
      () => NativeRequestState.scoped(native),
    ),
    appVisibleProvider.overrideWithBuild((_, _) => false),
    safeModeProvider.overrideWithValue(true),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final phase in ['stopped', 'failed']) {
    test(
      'old $phase recovery snapshot cannot erase a newer started runtime',
      () async {
        final native = _Native();
        final old = <String, Object?>{
          'processEpoch': 'native',
          'revision': 2,
          'intentRevision': 1,
          'intentRunning': false,
          'phase': phase,
          'reason': 'fixture',
        };
        when(native.getRequestState).thenAnswer((_) async => old);
        when(
          () => native.initializeRequestState(any(), recovery: true),
        ).thenAnswer((_) async => false);
        when(native.getRunTime).thenAnswer(
          (_) async => DateTime.now().subtract(const Duration(seconds: 5)),
        );
        final container = _recoveryContainer(native);
        addTearDown(container.dispose);
        final entered = Completer<void>(), release = Completer<void>();
        var checks = 0;
        final work = container
            .read(setupActionProvider.notifier)
            .initStatus(
              recovery: true,
              isCurrent: () async {
                if (++checks == 3) {
                  entered.complete();
                  await release.future;
                }
                return true;
              },
            );
        await entered.future;
        final synchronized = Completer<void>();
        container.listen(runTimeProvider, (_, next) {
          if (next != null && !synchronized.isCompleted) {
            synchronized.complete();
          }
        });
        container.read(nativeRequestStateProvider.notifier).onRequestState({
          ...old,
          'revision': 3,
          'phase': 'started',
          'intentRunning': true,
        });
        await synchronized.future;
        final runtime = container.read(runTimeProvider);
        release.complete();
        await work;
        expect(container.read(nativeRequestStateProvider)['revision'], 3);
        expect(container.read(runTimeProvider), runtime);
      },
    );
  }

  for (final newEpoch in [false, true]) {
    test(
      'late runtime failure cannot clear newer ${newEpoch ? 'epoch' : 'revision'} runtime',
      () async {
        final native = _Native();
        final old = <String, Object?>{
          'processEpoch': 'old',
          'revision': 2,
          'intentRevision': 1,
          'intentRunning': true,
          'phase': 'started',
          'reason': 'fixture',
        };
        when(native.getRequestState).thenAnswer((_) async => old);
        final entered = Completer<void>(), oldRuntime = Completer<DateTime?>();
        var probes = 0;
        when(native.getRunTime).thenAnswer((_) {
          if (++probes == 1) {
            entered.complete();
            return oldRuntime.future;
          }
          return Future.value(
            DateTime.now().subtract(const Duration(seconds: 10)),
          );
        });
        final container = _recoveryContainer(native);
        addTearDown(container.dispose);
        container.read(setupActionProvider);
        await entered.future;
        final synchronized = Completer<void>();
        container.listen(runTimeProvider, (_, next) {
          if (next != null && !synchronized.isCompleted) {
            synchronized.complete();
          }
        });
        container.read(nativeRequestStateProvider.notifier).onRequestState({
          ...old,
          'processEpoch': newEpoch ? 'new' : 'old',
          'revision': newEpoch ? 0 : 3,
        });
        await synchronized.future;
        final runtime = container.read(runTimeProvider);
        oldRuntime.completeError(StateError('synthetic delayed query failure'));
        await Future<void>.delayed(Duration.zero);
        expect(container.read(runTimeProvider), runtime);
        expect(
          container.read(nativeRequestStateProvider)['processEpoch'],
          newEpoch ? 'new' : 'old',
        );
      },
    );
  }
  for (final phase in ['stopped', 'failed', 'preparing', 'started']) {
    test(
      'recovery synchronizes $phase without preparing a run request',
      () async {
        final native = _Native();
        final state = <String, Object?>{
          'processEpoch': 'native',
          'revision': 2,
          'intentRevision': 1,
          'intentRunning': phase == 'started' || phase == 'preparing',
          'paused': false,
          'phase': phase,
          'reason': phase == 'stopped' ? 'none' : 'fixture',
        };
        when(native.getRequestState).thenAnswer((_) async => state);
        when(
          () => native.initializeRequestState(2, recovery: true),
        ).thenAnswer((_) async => false);
        when(native.getRunTime).thenAnswer(
          (_) async => DateTime.now().subtract(const Duration(seconds: 5)),
        );
        final container = ProviderContainer(
          overrides: [
            setupActionProvider.overrideWith(
              () => SetupAction.scoped(
                isAndroid: true,
                native: native,
                requests: Request.scoped(native: native, isAndroid: true),
              ),
            ),
            nativeRequestStateProvider.overrideWith(
              () => NativeRequestState.scoped(native),
            ),
            appVisibleProvider.overrideWithBuild((_, _) => false),
            safeModeProvider.overrideWithValue(true),
            appSettingProvider.overrideWithBuild(
              (_, _) => const AppSettingProps(autoRun: true),
            ),
            currentProfileIdProvider.overrideWithBuild((_, _) => 7),
          ],
        );
        addTearDown(container.dispose);
        globalState.needInitStatus = true;
        await container
            .read(setupActionProvider.notifier)
            .initStatus(recovery: true, isCurrent: () async => true);
        expect(container.read(nativeRequestStateProvider)['phase'], phase);
        expect(
          container.read(runTimeProvider),
          phase == 'started' ? isNotNull : isNull,
        );
        expect(container.read(currentProfileIdProvider), 7);
        expect(container.read(appSettingProvider).autoRun, true);
        verifyNever(
          () => native.prepareRunIntent(
            running: any(named: 'running'),
            source: any(named: 'source'),
            paused: any(named: 'paused'),
          ),
        );
        verifyNever(() => native.startPrepared(any()));
        verifyNever(() => native.stopPrepared(any()));
        expect(globalState.needInitStatus, false);
      },
    );
  }

  test(
    'a newer native start wins initializer rejection and late runtime is ignored',
    () async {
      final native = _Native();
      var state = <String, Object?>{
        'processEpoch': 'native',
        'revision': 0,
        'intentRevision': 0,
        'phase': 'stopped',
        'reason': 'none',
        'intentRunning': false,
      };
      final runtime = Completer<DateTime?>();
      when(native.getRequestState).thenAnswer((_) async => Map.of(state));
      when(
        () => native.initializeRequestState(any(), recovery: true),
      ).thenAnswer((_) async {
        state = {
          ...state,
          'revision': 1,
          'intentRevision': 1,
          'phase': 'started',
          'intentRunning': true,
        };
        return false;
      });
      when(native.getRunTime).thenAnswer((_) => runtime.future);
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(
            () => SetupAction.scoped(
              isAndroid: true,
              native: native,
              requests: Request.scoped(native: native, isAndroid: true),
            ),
          ),
          nativeRequestStateProvider.overrideWith(
            () => NativeRequestState.scoped(native),
          ),
          appVisibleProvider.overrideWithBuild((_, _) => false),
          safeModeProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      final work = container
          .read(setupActionProvider.notifier)
          .initStatus(recovery: true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(nativeRequestStateProvider)['intentRevision'], 1);
      container.read(nativeRequestStateProvider.notifier).onRequestState({
        ...state,
        'revision': 2,
        'intentRevision': 2,
        'phase': 'stopped',
        'intentRunning': false,
      });
      runtime.complete(DateTime(2026));
      await work;
      expect(container.read(runTimeProvider), isNull);
      expect(container.read(nativeRequestStateProvider)['intentRevision'], 2);
    },
  );
}
