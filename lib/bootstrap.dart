import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fl_clash/common/boot_guard.dart';
import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/launch.dart';
import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/common/permission.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/navigation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_color_utilities/palettes/tonal_palette.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Bootstrap {
  static Bootstrap? _instance;

  Bootstrap._internal()
    : _guard = bootGuard,
      _preparePresentationOverride = null,
      _checkPermissionsOverride = null;

  @visibleForTesting
  Bootstrap.scoped({
    required BootGuard guard,
    void Function()? preparePresentation,
    void Function()? checkPermissions,
  }) : _guard = guard,
       _preparePresentationOverride = preparePresentation,
       _checkPermissionsOverride = checkPermissions;

  final BootGuard _guard;
  final void Function()? _preparePresentationOverride;
  final void Function()? _checkPermissionsOverride;
  Future<bool>? _attachment;
  bool _warningShown = false;

  factory Bootstrap() {
    _instance ??= Bootstrap._internal();
    return _instance!;
  }

  BootDecision get _bootDecision => _guard.decision;

  Future<ProviderContainer> init(int version) async {
    globalState.appEnv = const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'pre',
    );
    windowPort = window;
    trayPort = appTray;
    navigationPort = navigation;
    final dynamicColor = await _initDynamicColor();
    return _initData(version, dynamicColor);
  }

  Future<DynamicColorSeeds> _initDynamicColor() async {
    TonalPalette? primaryPalette;
    Color? accentColor;
    try {
      primaryPalette = await _getSystemPrimaryPalette();
    } catch (error) {
      commonPrint.log(
        'Failed to get core palette: $error',
        logLevel: LogLevel.warning,
      );
    }
    try {
      accentColor = await DynamicColorPlugin.getAccentColor();
    } catch (error) {
      commonPrint.log(
        'Failed to get accent color: $error',
        logLevel: LogLevel.warning,
      );
    }
    return (
      lightSeed: primaryPalette != null ? Color(primaryPalette.get(40)) : null,
      darkSeed: primaryPalette != null ? Color(primaryPalette.get(80)) : null,
      accentColor: accentColor ?? const Color(defaultPrimaryColor),
    );
  }

  Future<TonalPalette?> _getSystemPrimaryPalette() async {
    final raw = await DynamicColorPlugin.channel.invokeMethod<List<dynamic>>(
      DynamicColorPlugin.methodName,
    );
    if (raw == null || raw.length < TonalPalette.commonSize) {
      return null;
    }
    return TonalPalette.fromList(
      raw.sublist(0, TonalPalette.commonSize).cast<int>(),
    );
  }

  Future<ProviderContainer> _initData(
    int version,
    DynamicColorSeeds dynamicColor,
  ) async {
    globalState.packageInfo = await PackageInfo.fromPlatform();
    final config = await migration.run();
    await _guard.evaluate(
      profileId: config.currentProfileId,
      preferencesAvailable: await preferences.isInit,
    );
    final appState = AppState(
      brightness: WidgetsBinding.instance.platformDispatcher.platformBrightness,
      version: version,
      viewSize: Size.zero,
      requests: FixedList(maxRequestsLength),
      logs: FixedList(maxLogsLength),
      traffics: FixedList(trafficSampleLength),
      totalTraffic: const Traffic(),
      systemUiOverlayStyle: const SystemUiOverlayStyle(),
    );
    final appStateOverrides = buildAppStateOverrides(appState);
    final configOverrides = buildConfigOverrides(config);
    final container = ProviderContainer(
      overrides: [...appStateOverrides, ...configOverrides],
    );
    globalState.container = container;
    container
        .read(dynamicColorProvider.notifier)
        .seed(
          lightSeed: dynamicColor.lightSeed,
          darkSeed: dynamicColor.darkSeed,
          accentColor: dynamicColor.accentColor,
        );
    final profiles = await database.profilesDao.query().get();
    container.read(profilesProvider.notifier).initialize(profiles);
    await AppLocalizations.load(
      getLocaleForString(config.appSettingProps.locale) ??
          WidgetsBinding.instance.platformDispatcher.locale,
    );
    await window?.init(version, config.windowProps);
    if (system.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    return container;
  }

  Future<bool> attach() => _attachment ??= _attach();

  Future<bool> _attach() async {
    final completed = await _initApp();
    if (completed) globalState.isAttach = true;
    return completed;
  }

  Future<bool> runAfterAttach(List<FutureOr<void> Function()> actions) async {
    if (!await attach()) return false;
    for (final action in actions) {
      if (!await _guard.isCurrent()) return false;
      await action();
    }
    return true;
  }

  ProviderContainer get _container => globalState.container;

  void _preparePresentation() {
    unawaited(_container.read(systemActionProvider.notifier).updateTray());
    unawaited(
      autoLaunch?.updateStatus(_container.read(appSettingProvider).autoLaunch),
    );
    if (!_container.read(appSettingProvider).silentLaunch) {
      unawaited(window?.show());
    } else {
      unawaited(window?.hide());
    }
  }

  Future<bool> _initApp() async {
    if (!await _guard.isCurrent()) return false;
    (_preparePresentationOverride ?? _preparePresentation)();
    if (!await _handleFailedPreference() || !await _guard.isCurrent()) {
      return false;
    }
    await request.ready();
    if (!await _guard.isCurrent()) return false;
    if (_bootDecision.isDegraded) await _guard.markPhase(BootPhase.recovery);
    if (!await _guard.isCurrent()) return false;
    await _showCrashRecoveryTip();
    if (!await _guard.isCurrent()) return false;
    await _guard.markPhase(BootPhase.core);
    if (!await _guard.isCurrent()) return false;
    await _container.read(coreActionProvider.notifier).startCore();
    if (!await _guard.isCurrent()) return false;
    await _guard.markPhase(BootPhase.setup);
    if (!await _guard.isCurrent()) return false;
    await _container
        .read(setupActionProvider.notifier)
        .initStatus(
          recovery: _bootDecision.isDegraded,
          isCurrent: _guard.isCurrent,
        );
    if (!await _guard.isCurrent()) return false;
    _container.read(initProvider.notifier).value = true;
    await _guard.markRunning();
    if (!await _guard.isCurrent()) return false;
    _showRecordWarning();
    (_checkPermissionsOverride ?? () => permissions.check(_container.read))();
    return true;
  }

  Future<void> _showCrashRecoveryTip() async {
    final recovery = _bootDecision.recovery;
    if (recovery == BootRecovery.none) return;
    final l10n = currentAppLocalizations;
    final damaged = recovery == BootRecovery.damagedRecord;
    final message = switch (recovery) {
      BootRecovery.damagedRecord => l10n.bootRecordDamaged,
      BootRecovery.newerRecord => l10n.bootRecordNewer,
      BootRecovery.unavailable => l10n.bootRecordUnavailable,
      _ => [
        _bootDecision.crashConfirmed
            ? l10n.crashDetectedTip(_failedProfileLabel)
            : l10n.launchInterruptedTip,
        if (_bootDecision.crashConfirmed)
          l10n.bootRecoveryReason(switch (_bootDecision.exitReason) {
            AppExitReason.crashNative => l10n.bootExitNativeCrash,
            AppExitReason.anr => l10n.bootExitAnr,
            AppExitReason.initializationFailure => l10n.bootExitInitialization,
            _ => l10n.bootExitCrash,
          }),
        if (_bootDecision.failedPhase case final phase?)
          l10n.bootRecoveryPhase(switch (phase) {
            BootPhase.bootstrap => l10n.bootPhaseBootstrap,
            BootPhase.recovery => l10n.bootPhaseRecovery,
            BootPhase.core => l10n.bootPhaseCore,
            BootPhase.setup => l10n.bootPhaseSetup,
          }),
        if (recovery == BootRecovery.repeated) l10n.bootRecoveryRepeated,
      ].join('\n\n'),
    };
    if (recovery == BootRecovery.unavailable) _warningShown = true;
    final rebuild = await dialogs.showMessage(
      title: _bootDecision.crashConfirmed
          ? l10n.crashDetected
          : l10n.launchInterrupted,
      cancelable: damaged,
      dismissible: false,
      confirmText: damaged ? l10n.bootRecordRebuild : null,
      cancelText: damaged ? l10n.bootRecordKeep : null,
      message: TextSpan(text: message),
    );
    if (damaged && rebuild == true && await _guard.isCurrent()) {
      await _guard.rebuildRecord();
      if (!await _guard.isCurrent()) return;
      _showRecordWarning();
    }
  }

  void _showRecordWarning() {
    if (_warningShown || _bootDecision.recovery != BootRecovery.unavailable) {
      return;
    }
    _warningShown = true;
    dialogs.showNotifier(
      currentAppLocalizations.bootRecordUnavailable,
      level: MessageLevel.error,
    );
  }

  String get _failedProfileLabel {
    final profileId = _bootDecision.failedProfileId;
    if (profileId == null) {
      return '';
    }
    final profile = _container.read(profilesProvider).getProfile(profileId);
    return profile?.label.takeFirstValid(['$profileId']) ?? '$profileId';
  }

  Future<bool> _handleFailedPreference() async {
    final initialized = await preferences.isInit;
    if (!await _guard.isCurrent()) return false;
    if (initialized) return true;
    final res = await dialogs.showMessage(
      title: currentAppLocalizations.tip,
      message: TextSpan(text: currentAppLocalizations.cacheCorrupt),
    );
    if (!await _guard.isCurrent()) return false;
    if (res == true) {
      final file = File(await appPath.sharedPreferencesPath);
      await file.safeDelete();
    }
    // Saving here would rewrite the preferences file the user just chose to delete.
    await _container.read(systemActionProvider.notifier).handleExit(false);
    return false;
  }
}

final bootstrap = Bootstrap();
