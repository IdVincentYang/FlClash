import 'dart:async';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_config_state.dart';

class _Requests extends Request {
  Completer<void>? hold;
  Completer<void>? entered;

  @override
  Future<void> invalidate(String key) async {
    entered?.complete();
    await hold?.future;
    await super.invalidate(key);
  }
}

class _Inputs extends ApplicationInputAction {
  _Inputs(this.client);
  final Request client;
  @override
  Request get requestClient => client;

  bool android = false;
  @override
  bool get isAndroid => android;
}

class _Setup extends SetupAction {
  final rebuilds = <bool>[];
  int updates = 0;
  Error? failure;

  @override
  void build() {}

  @override
  Future<ConfigFailureObservation?> captureConfigFailure(
    Request client,
  ) async => null;

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    bool allowSourceReview = false,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
    bool rebuildVpn = false,
  }) async {
    rebuilds.add(rebuildVpn);
    if (failure case final error?) throw error;
    return true;
  }

  @override
  Future<void> updateConfigDebounce() async {
    updates++;
  }
}

class _NativeState extends NativeRequestState {
  @override
  Map<String, Object?> build() => const {
    'processEpoch': 'vpn-options-test',
    'revision': 1,
    'phase': 'started',
    'reason': 'none',
    'intentRunning': true,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late ProviderContainer container;
  late _Requests client;
  late _Inputs inputs;
  late _Setup setup;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('en'));
  });
  setUp(() {
    db = Database(NativeDatabase.memory());
    database = db;
    client = _Requests();
    inputs = _Inputs(client);
    setup = _Setup();
    container = ProviderContainer(
      overrides: [
        applicationInputActionProvider.overrideWith(() => inputs),
        setupActionProvider.overrideWith(() => setup),
        nativeRequestStateProvider.overrideWith(_NativeState.new),
        configStateProvider.overrideWith(TestConfigState.new),
      ],
    );
    container.listen(configProvider, (_, _) {});
    container.read(applicationInputActionProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  final vpnChanges = <String, VpnProps Function(VpnProps)>{
    'VPN enabled': (value) => value.copyWith(enable: !value.enable),
    'IPv6': (value) => value.copyWith(ipv6: !value.ipv6),
    'system HTTP proxy': (value) =>
        value.copyWith(systemProxy: !value.systemProxy),
    'allow bypass': (value) => value.copyWith(allowBypass: !value.allowBypass),
    'DNS hijacking': (value) =>
        value.copyWith(dnsHijacking: !value.dnsHijacking),
    'VPN app scope': (value) => value.copyWith.accessControlProps(
      enable: true,
      rejectList: ['test.app'],
    ),
  };
  for (final entry in vpnChanges.entries) {
    test('${entry.key} applies automatically while VPN is requested', () async {
      inputs.android = true;
      container.read(initProvider.notifier).value = true;
      await inputs.updateVpn(entry.value);
      expect(setup.rebuilds, [true]);
      expect(setup.updates, 0);
    });
  }

  final patchChanges = <String, PatchClashConfig Function(PatchClashConfig)>{
    'TUN stack': (value) => value.copyWith.tun(stack: TunStack.gvisor),
    'proxy port': (value) => value.copyWith(mixedPort: value.mixedPort + 1),
    'TUN routes': (value) => value.copyWith.tun(routeAddress: ['0.0.0.0/1']),
  };
  for (final entry in patchChanges.entries) {
    test(
      '${entry.key} rebuilds instead of attempting inline adoption',
      () async {
        inputs.android = true;
        container.read(initProvider.notifier).value = true;
        await inputs.updatePatch(entry.value);
        expect(setup.rebuilds, [true]);
        expect(setup.updates, 0);
      },
    );
  }

  final networkChanges = <String, NetworkProps Function(NetworkProps)>{
    'bypass domains': (value) => value.copyWith(bypassDomain: ['test.local']),
    'route mode': (value) => value.copyWith(routeMode: RouteMode.bypassPrivate),
    'proxy authentication': (value) => value.copyWith(
      authentication: const AuthenticationProps(
        enable: true,
        username: 'local',
      ),
    ),
  };
  for (final entry in networkChanges.entries) {
    test(
      '${entry.key} applies its dependent VPN options automatically',
      () async {
        inputs.android = true;
        container.read(initProvider.notifier).value = true;
        await inputs.updateNetwork(entry.value);
        expect(setup.rebuilds, [true]);
        expect(setup.updates, 0);
      },
    );
  }

  test('an ordinary mode change keeps the hot configuration path', () async {
    inputs.android = true;
    container.read(initProvider.notifier).value = true;
    await inputs.updatePatch((value) => value.copyWith(mode: Mode.direct));
    expect(setup.rebuilds, isEmpty);
    expect(setup.updates, 1);
  });

  test('unchanged settings do not reapply the VPN', () async {
    inputs.android = true;
    container.read(initProvider.notifier).value = true;
    await inputs.updateVpn((value) => value);
    await inputs.updatePatch((value) => value);
    expect(setup.rebuilds, isEmpty);
    expect(setup.updates, 0);
  });

  test(
    'offline edits save VPN options without starting a stopped VPN',
    () async {
      inputs.android = true;
      container.read(initProvider.notifier).value = true;
      container.read(nativeRequestStateProvider.notifier).onRequestState(const {
        'processEpoch': 'vpn-options-test',
        'revision': 2,
        'phase': 'stopped',
        'reason': 'userStop',
        'intentRunning': false,
      });
      await inputs.updateVpn((value) => value.copyWith(ipv6: true));
      await inputs.updatePatch(
        (value) => value.copyWith.tun(stack: TunStack.gvisor),
      );
      final saved = (await preferences.getConfig())!;
      expect(saved.vpnProps.ipv6, isTrue);
      expect(saved.patchClashConfig.tun.stack, TunStack.gvisor);
      expect(setup.rebuilds, isEmpty);
      expect(setup.updates, 0);
    },
  );

  test(
    'a reapply error remains observable and does not erase saved settings',
    () async {
      inputs.android = true;
      container.read(initProvider.notifier).value = true;
      setup.failure = StateError('synthetic apply failure');
      await expectLater(
        inputs.updateVpn((value) => value.copyWith(ipv6: true)),
        throwsStateError,
      );
      expect((await preferences.getConfig())!.vpnProps.ipv6, isTrue);
      expect(setup.rebuilds, [true]);
    },
  );

  test(
    'effective direct writes reject before publication; visual preference is allowed',
    () {
      final notifier = container.read(appSettingProvider.notifier);
      final previous = notifier.value;
      expect(
        () => notifier.value = previous.copyWith(testUrl: 'https://new.test'),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(notifier.value, previous);
      notifier.update(
        (value) => value.copyWith(showTrayTitle: !value.showTrayTitle),
      );
      expect(notifier.value.showTrayTitle, !previous.showTrayTitle);
      expect(
        () => container
            .read(networkSettingProvider.notifier)
            .update((value) => value.copyWith(systemProxy: !value.systemProxy)),
        throwsA(isA<RequestUnavailable>()),
      );
    },
  );

  test(
    'testUrl commits invalidate before publication and revoke a captured source without hot writes',
    () async {
      final original = container.read(appSettingProvider).testUrl;
      final source = await client.captureSource('application-config');
      client.hold = Completer<void>();
      client.entered = Completer<void>();
      final change = container
          .read(applicationInputActionProvider.notifier)
          .updateAppSetting(
            (value) => value.copyWith(testUrl: 'https://new.test'),
          );
      await client.entered!.future;
      expect(container.read(appSettingProvider).testUrl, original);
      client.hold!.complete();
      await change;
      expect(container.read(appSettingProvider).testUrl, 'https://new.test');
      expect(await client.configSourceCurrent(source), isFalse);
      expect(
        (await preferences.getConfig())!.appSettingProps.testUrl,
        'https://new.test',
      );
    },
  );

  test(
    'publication permission does not survive a listener microtask or receipt end',
    () async {
      final attempted = Completer<Object>();
      container.listen(appSettingProvider, (_, next) {
        if (next.testUrl != 'https://committed.test') return;
        scheduleMicrotask(() {
          try {
            container
                .read(networkSettingProvider.notifier)
                .update(
                  (value) => value.copyWith(systemProxy: !value.systemProxy),
                );
            attempted.complete(StateError('write escaped the scope'));
          } catch (error) {
            attempted.complete(error);
          }
        });
      });
      await container
          .read(applicationInputActionProvider.notifier)
          .updateAppSetting(
            (value) => value.copyWith(testUrl: 'https://committed.test'),
          );
      expect(await attempted.future, isA<RequestUnavailable>());
      expect(client.applicationInputsInvalidated, isFalse);
    },
  );
}
