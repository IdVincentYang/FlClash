part of '../action.dart';

@Riverpod(keepAlive: true)
class SystemAction extends _$SystemAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  @protected
  BootGuard get startupGuard => bootGuard;

  @protected
  Request get requestClient => request;

  @protected
  Service? get nativeService => service;

  @protected
  Future<void> shutdownTray() async => await trayPort?.shutdown();

  @protected
  Future<void> shutdownDns() async => await systemDnsCoordinator?.shutdown();

  @protected
  Future<void> stopSystemProxy() async => await proxy?.stopProxy();

  SystemExitCoordinator? _exitCoordinator;

  @override
  void build() {}

  Future<List<Package>> getPackages() async {
    if (ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    ref.read(packagesProvider.notifier).value = await app?.getPackages() ?? [];
    return ref.read(packagesProvider);
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    return await app?.isInstalledAppsPermissionGranted() ?? true;
  }

  Future<bool> requestInstalledAppsPermission() async {
    return await app?.requestInstalledAppsPermission() ?? false;
  }

  Future<void> handleExit([bool needSave = true]) {
    unawaited(
      Future<void>.sync(startupGuard.markClosed).catchError((Object error) {
        commonPrint.log(
          'Startup close failed: ${compactError(error)}',
          logLevel: LogLevel.error,
        );
      }),
    );
    final coordinator = _exitCoordinator ??= SystemExitCoordinator(
      watchdogDuration: exitWatchdogDuration,
      closeWindow: closeWindow,
      closeCore: closeCore,
      exitApplication: exitApplication,
    );
    return coordinator.exit(cleanup: () => cleanupExitResources(needSave));
  }

  @protected
  Duration get exitWatchdogDuration => const Duration(seconds: 3);

  @protected
  Future<void> cleanupExitResources(bool needSave) async {
    Object? firstError;
    StackTrace? firstStack;
    Future<void> runStep(String name, Future<void> Function() step) async {
      try {
        await step();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
        commonPrint.log(
          'Exit $name failed: ${compactError(error)}',
          logLevel: LogLevel.error,
        );
      }
    }

    RequestExitCleanup? scope;
    final quiesced = runStep('request quiesce', () async {
      scope = requestClient.quiesceForExit();
    });
    final independent = [
      runStep('startup close', startupGuard.markClosed),
      runStep('tray', shutdownTray),
      runStep('DNS', shutdownDns),
      runStep('system proxy', stopSystemProxy),
    ];
    await quiesced;
    await runStep('intent', () async {
      await nativeService?.prepareRunIntent(running: false, source: 'exit');
    });
    if (needSave) {
      await runStep('preferences', () async {
        final owner = scope;
        if (owner == null) throw const RequestUnavailable('request_cancelled');
        await savePreferences(commit: owner.commit);
      });
    }
    await runStep('request detach', () async {
      final owner = scope;
      if (owner == null) throw const RequestUnavailable('request_cancelled');
      await owner.detach();
    });
    await Future.wait(independent);
    final error = firstError;
    if (error != null) Error.throwWithStackTrace(error, firstStack!);
  }

  Future<void> _savePreferencesSafely() async {
    try {
      await savePreferences();
    } catch (error) {
      commonPrint.log(
        'Preferences save failed: ${compactError(error)}',
        logLevel: LogLevel.error,
      );
    }
  }

  @protected
  Future<void> savePreferences({RequestLocalCommit? commit}) async {
    final port = windowPort;
    if (port != null) {
      try {
        final current = ref.read(windowSettingProvider);
        final geometry = await port.captureNormalGeometry(current);
        if (geometry != null) {
          ref.read(windowSettingProvider.notifier).value = geometry;
        }
      } catch (error) {
        commonPrint.log(
          'Window geometry capture failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    }
    final writeConfig = await preferences.prepareConfigWriter();
    await (commit ?? requestClient.mutate<void>)(() async {
      if (!await writeConfig(ref.read(configProvider))) {
        throw const RequestUnavailable('preferences_save_failed');
      }
    });
  }

  @protected
  Future<void> closeWindow() async {
    await windowPort?.close();
  }

  @protected
  Future<void> closeCore() async {
    await _core.close();
    commonPrint.log('exit');
  }

  @protected
  Future<void> exitApplication() async {
    await system.exit();
    windowPort?.forceExit();
  }

  Future<void> handleClose([bool exit = true]) async {
    if (ref.read(appSettingProvider).minimizeOnExit || !exit) {
      if (system.isDesktop) {
        await _savePreferencesSafely();
      }
      await system.back();
      await windowPort?.hide();
    } else {
      await handleExit();
    }
  }

  Future<void> updateVisible() async {
    await windowPort?.toggle();
  }

  Future<void> updateTun() async {
    await ref
        .read(applicationInputActionProvider.notifier)
        .updatePatch((state) => state.copyWith.tun(enable: !state.tun.enable));
  }

  Future<void> updateSystemProxy() async {
    await ref
        .read(applicationInputActionProvider.notifier)
        .updateNetwork(
          (state) => state.copyWith(systemProxy: !state.systemProxy),
        );
  }

  Future<void> copyProxyEnv() async {
    final fact = ref.read(configStateProvider).fact;
    final port = fact.isManaged
        ? fact.mixedPort
        : ref.read(patchClashConfigProvider.select((state) => state.mixedPort));
    await Clipboard.setData(
      ClipboardData(text: proxyEnvCommand(port, isWindows: system.isWindows)),
    );
  }

  void updateAutoLaunch() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: !state.autoLaunch));
  }

  Future<void> updateTray() async {
    await trayPort?.update(
      trayState: ref.read(trayStateProvider),
      traffic: ref.read(
        trafficsProvider.select(
          (state) => state.list.safeLast(const Traffic()),
        ),
      ),
      read: globalState.container.read,
    );
  }

  Future<void> updateLocalIp() async {
    ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    ref.read(localIpProvider.notifier).value = await getLocalIpAddress();
  }
}
