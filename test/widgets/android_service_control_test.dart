import 'package:fl_clash/common/android_service_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/start_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

class _Native extends NativeRequestState {
  @override
  Map<String, Object?> build() => const {};
}

class _Setup extends SetupAction {
  final targets = <bool>[];
  @override
  void build() {}
  @override
  Future<bool> setRunning(
    bool running, {
    bool initialize = false,
    int? preparedRequestId,
    String source = 'ui',
    bool? paused,
  }) async {
    targets.add(running);
    return true;
  }
}

void main() {
  testWidgets(
    'paused intent remains stoppable without claiming early suspension',
    (tester) async {
      final setup = _Setup();
      final container = ProviderContainer(
        overrides: [
          nativeRequestStateProvider.overrideWith(_Native.new),
          profilesProvider.overrideWithValue([
            const Profile(id: 1, autoUpdateDuration: Duration.zero),
          ]),
          setupActionProvider.overrideWith(() => setup),
          runControlProvider.overrideWith(
            (ref) => androidRunRequested(ref.watch(nativeRequestStateProvider)),
          ),
          androidServiceStatusProvider.overrideWith(
            (ref) => androidServiceStatus(
              ref.watch(nativeRequestStateProvider),
              const ConfigFact(phase: 'ready'),
            ),
          ),
          suspendProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      final native = container.read(nativeRequestStateProvider.notifier);
      void publish(
        String phase,
        int revision, {
        String serviceId = 'owned',
        String protect = 'ready',
        bool intent = true,
      }) {
        native.onRequestState({
          'processEpoch': 'widget',
          'revision': revision,
          'phase': phase,
          'paused': true,
          'intentRunning': intent,
          'serviceId': serviceId,
          'protectPhase': protect,
          'protectGeneration': 1,
          'reason': 'excludedSsid',
        });
      }

      publish('stopping', 1);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            homeBuilder: (child) => Scaffold(floatingActionButton: child),
            child: const StartButton(isAndroid: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Stopping service'), findsOneWidget);
      expect(find.text('Suspended'), findsNothing);
      expect(find.byTooltip('Stop'), findsOneWidget);
      publish('stopped', 2);
      await tester.pump();
      expect(find.text('Suspended'), findsNothing);
      publish('stopped', 3, serviceId: '', protect: 'none');
      await tester.pump();
      expect(find.text('Suspended'), findsOneWidget);
      expect(container.read(runTimeProvider), isNull);
      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      expect(setup.targets, [false]);
      publish('failed', 4, intent: false);
      await tester.pump();
      expect(find.byTooltip('Start'), findsOneWidget);
      expect(find.text('Suspended'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
