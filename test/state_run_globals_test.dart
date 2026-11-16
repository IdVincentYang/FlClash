import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';

import 'helpers/boot_fixture.dart';
import 'helpers/test_config_state.dart';

class _AttachCore extends CoreAction {
  int starts = 0;
  @override
  Future<void> startCore() async {
    starts++;
  }
}

class _AttachSetup extends SetupAction {
  int initializations = 0;
  @override
  void build() {}
  @override
  Future<void> initStatus({
    bool recovery = false,
    Future<bool> Function()? isCurrent,
  }) async {
    initializations++;
  }
}

final _packageInfo = PackageInfo(
  appName: 'FlClash',
  packageName: 'com.follow.clash',
  version: '1.2.3',
  buildNumber: '1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.isInit;
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = _packageInfo;
  });

  setUp(() {
    container = ProviderContainer(
      overrides: [configStateProvider.overrideWith(TestConfigState.new)],
    );
    container.listen(configProvider, (_, _) {});
    globalState.container = container;
  });

  tearDown(() {
    container.dispose();
    globalState.isAttach = false;
  });

  Future<void> setGlobalUa(String value) async {
    await container
        .read(applicationInputActionProvider.notifier)
        .updatePatch((state) => state.copyWith(globalUa: value));
  }

  group('user agent', () {
    test(
      'falls back to the package user agent when none is configured',
      () async {
        await setGlobalUa('');

        expect(globalState.ua, _packageInfo.ua);
        expect(globalState.ua, contains('FlClash/v1.2.3'));
      },
    );

    test('prefers the configured global user agent', () async {
      await setGlobalUa('custom-agent/1.0');

      expect(globalState.ua, 'custom-agent/1.0');
    });

    test('treats a blank configured user agent as unset', () async {
      await setGlobalUa('   ');

      expect(globalState.ua, _packageInfo.ua);
    });
  });

  group('attach', () {
    test(
      'first concurrent and repeated attach share one startup sequence',
      () async {
        final fixture = BootFixture();
        final guard = fixture.guard();
        await guard.evaluate(profileId: null);
        final core = _AttachCore();
        final setup = _AttachSetup();
        container.dispose();
        container = ProviderContainer(
          overrides: [
            configStateProvider.overrideWith(TestConfigState.new),
            coreActionProvider.overrideWith(() => core),
            setupActionProvider.overrideWith(() => setup),
          ],
        );
        globalState.container = container;
        final boot = Bootstrap.scoped(
          guard: guard,
          preparePresentation: () {},
          checkPermissions: () {},
        );
        final first = boot.attach();
        final concurrent = boot.attach();
        expect(identical(first, concurrent), isTrue);
        expect(await first, isTrue);
        expect(await boot.attach(), isTrue);
        expect(core.starts, 1);
        expect(setup.initializations, 1);
        expect(globalState.isAttach, isTrue);
        expect(container.read(initProvider), isTrue);
      },
    );
  });

  group('canCrashCoreFor', () {
    test('allows a forced Core crash in debug and on the dev channel', () {
      expect(
        GlobalState.canCrashCoreFor(isDebug: true, appEnv: 'stable'),
        isTrue,
      );
      expect(
        GlobalState.canCrashCoreFor(isDebug: false, appEnv: 'dev'),
        isTrue,
      );
    });

    test('never allows a forced Core crash in a release build', () {
      expect(
        GlobalState.canCrashCoreFor(isDebug: false, appEnv: 'stable'),
        isFalse,
      );
      expect(
        GlobalState.canCrashCoreFor(isDebug: false, appEnv: 'pre'),
        isFalse,
      );
    });
  });
}
