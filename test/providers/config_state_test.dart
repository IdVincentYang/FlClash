import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Core implements CoreController {
  bool failing = false;
  @override
  Future<ConfigFact> getConfigState() async {
    if (failing) throw StateError('temporary transport failure');
    return const ConfigFact(
      runtimeEpoch: 'fixture',
      version: 1,
      profileId: 7,
      phase: 'ready',
      businessActive: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SynchronousFailureCore implements CoreController {
  @override
  Future<ConfigFact> getConfigState() => throw StateError('not connected yet');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'initial synchronous Core failure leaves a readable unknown state',
    () async {
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(_SynchronousFailureCore()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(configStateProvider).fact.phase, 'unknown');
      await container.read(configStateProvider.notifier).refresh();
      expect(container.read(configStateProvider).fact.phase, 'unknown');
      expect(container.read(configStateProvider).buildFailed, false);
    },
  );

  test(
    'temporary refresh failure retains last known config until a crash or new fact',
    () async {
      final core = _Core();
      final container = ProviderContainer(
        overrides: [coreHandlerProvider.overrideWithValue(core)],
      );
      addTearDown(container.dispose);
      final state = container.read(configStateProvider.notifier);
      await state.refresh();
      expect(container.read(configStateProvider).fact.profileId, 7);
      core.failing = true;
      await state.refresh();
      expect(container.read(configStateProvider).fact.profileId, 7);
      expect(container.read(configStateProvider).fact.phase, 'ready');
      state.onCrash('disconnected');
      expect(container.read(configStateProvider).fact.phase, 'unknown');
    },
  );
}
