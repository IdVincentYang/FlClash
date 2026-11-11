import 'dart:convert';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/request_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/application_activity.dart';
import '../helpers/test_config_state.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Native extends NativeRequestState {
  @override
  Map<String, Object?> build() => const {
    'phase': 'started',
    'intentRunning': true,
    'paused': false,
    'serviceId': 'vpn-a',
    'protectPhase': 'ready',
    'protectGeneration': 1,
  };
}

void main() {
  testWidgets(
    'CoreManager keeps observation subscribed outside every activity page',
    (tester) async {
      final core = _Core();
      when(() => core.stopLog()).thenAnswer((_) {});
      when(() => core.getConnections()).thenAnswer((_) async => []);
      final container = ProviderContainer(
        overrides: [
          initProvider.overrideWithBuild((_, _) => true),
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          configStateProvider.overrideWith(
            () => TestConfigState(
              const ConfigFact(
                runtimeEpoch: 'runtime-a',
                phase: 'ready',
                businessActive: true,
              ),
            ),
          ),
          nativeRequestStateProvider.overrideWith(_Native.new),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CoreManager(isAndroid: true, child: SizedBox()),
        ),
      );
      await tester.pump();
      container.read(appVisibleProvider.notifier).value = false;
      await tester.pump();
      final info = activityConnection('background');
      coreEventManager.sendEvent(
        CoreEvent(
          type: CoreEventType.request,
          data: jsonDecode(jsonEncode(info)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final activity = container.read(applicationActivityProvider);
      expect(activity.connections.single.info.id, 'background');
      expect(activity.interrupted, true);
      expect(container.read(requestCountProvider), 1);
      container.read(appVisibleProvider.notifier).value = true;
      await tester.pump();
      expect(
        container
            .read(applicationActivityProvider)
            .apps
            .single
            .totals
            .activeCount,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
