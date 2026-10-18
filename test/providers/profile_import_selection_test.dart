import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_config_state.dart';
import '../helpers/test_policy_drafts.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Setup extends SetupAction {
  final intents = <bool>[];
  int applies = 0;

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
    intents.add(running);
    return true;
  }

  @override
  Future<bool> applyProfile({bool silence = false, bool force = false}) async {
    applies++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'deleting the last managed profile then cold import requires selection',
    () async {
      final root = await Directory.systemTemp.createTemp('profile-selection-');
      addTearDown(() => root.delete(recursive: true));
      AppPath.supportDirectory = () async => root;
      AppPath.temporaryDirectory = () async => root;
      AppPath.cacheDirectory = () async => root;
      final file = File('${root.path}/profiles.sqlite');
      var store = Database(NativeDatabase(file));
      database = store;
      await store.profilesDao.putAll([draftTestProfile(1).toCompanion()]);
      await store.profilePolicySelectionsDao.requireSelections({1});
      final core = _Core();
      when(() => core.clearEffect(1)).thenAnswer((_) async => '');
      ProviderContainer open(int? current) {
        final container = ProviderContainer(
          overrides: [
            ...buildConfigOverrides(
              Config(themeProps: defaultThemeProps, currentProfileId: current),
            ),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            setupActionProvider.overrideWith(_Setup.new),
            configStateProvider.overrideWith(TestConfigState.new),
          ],
        );
        container.listen(configProvider, (_, _) {});
        return container;
      }

      var container = open(1);
      try {
        await container.read(profilesActionProvider.notifier).deleteProfile(1);
        expect(container.read(currentProfileIdProvider), isNull);
        expect(
          (container.read(setupActionProvider.notifier) as _Setup).intents,
          [false],
        );
        expect(await store.profilesDao.query().get(), isEmpty);
        expect(await store.profilePolicySelectionsDao.query().get(), isEmpty);
      } finally {
        container.dispose();
        await store.close();
      }

      store = Database(NativeDatabase(file));
      database = store;
      container = open(null);
      try {
        expect(container.read(configStateProvider).fact.token, 0);
        await container
            .read(profilesActionProvider.notifier)
            .putProfile(draftTestProfile(2));
        expect((await store.profilesDao.query().get()).single.id, 2);
        expect(await store.profilePolicySelectionsDao.query().get(), isEmpty);
        expect(container.read(currentProfileIdProvider), isNull);
        final setup = container.read(setupActionProvider.notifier) as _Setup;
        expect(setup.intents, isEmpty);
        expect(setup.applies, 0);
        expect(
          await container
              .read(policySelectionActionProvider.notifier)
              .chooseProfile(2, confirmLeave: () async => true),
          isTrue,
        );
        expect(container.read(currentProfileIdProvider), 2);
        expect(setup.intents, isEmpty);
        expect(setup.applies, 0);
      } finally {
        container.dispose();
        await store.close();
      }
    },
  );
}
