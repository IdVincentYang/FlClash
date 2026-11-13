import 'package:fl_clash/common/network_error.dart';
import 'package:fl_clash/core/desktop/launch_policy.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'local_proxy_groups.dart';

import 'dart:ui';

final currentAppLocalizations = AppLocalizations.current;

String? coreLaunchBlockedMessage(
  Object error,
  AppLocalizations appLocalizations,
) {
  if (!isPolicyBlockedLaunch(error)) {
    return null;
  }
  return switch (smartAppControlStateReader()) {
    SmartAppControlState.on || SmartAppControlState.evaluation =>
      appLocalizations.coreBlockedBySmartAppControlTip,
    _ => appLocalizations.coreBlockedByPolicyTip(launchOsError(error)!),
  };
}

String userFacingErrorMessage(Object error, AppLocalizations appLocalizations) {
  return networkErrorMessage(error, appLocalizations) ??
      coreLaunchBlockedMessage(error, appLocalizations) ??
      switch (error) {
        LocalProxyGroupProblem(:final code, :final name) => switch (code) {
          'name' => appLocalizations.localGroupsNameConflict,
          'members' => appLocalizations.localGroupsMembersRequired,
          'parent' => appLocalizations.localGroupsInvalidParent,
          'testUrl' => appLocalizations.localGroupsInvalidTestUrl,
          'managed' => appLocalizations.localGroupsManaged,
          'loading' => appLocalizations.localGroupsLoadFirst,
          'limit' => appLocalizations.localGroupsLimit,
          'inUse' => appLocalizations.localGroupsInUse,
          'inUseProfile' => appLocalizations.localGroupsInUseProfile(name),
          'noMatchingNodes' => appLocalizations.localGroupsNoMatchingNodes,
          'changed' => appLocalizations.localGroupsChanged,
          'foreground' => appLocalizations.localGroupsForegroundRequired,
          _ => appLocalizations.localGroupsApplyFailed,
        },
        CoreMethodException(:final message) => message,
        _ => error.toString(),
      };
}

Locale? getLocaleForString(String? localString) {
  if (localString == null) return null;
  final localSplit = localString.split('_');
  if (localSplit.length == 1) {
    return Locale(localSplit[0]);
  }
  if (localSplit.length == 2) {
    return Locale(localSplit[0], localSplit[1]);
  }
  if (localSplit.length == 3) {
    return Locale.fromSubtags(
      languageCode: localSplit[0],
      scriptCode: localSplit[1],
      countryCode: localSplit[2],
    );
  }
  return null;
}
