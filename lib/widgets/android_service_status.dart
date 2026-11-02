import 'package:fl_clash/common/android_service_state.dart';
import 'package:fl_clash/l10n/l10n.dart';

String androidServiceStatusLabel(
  AppLocalizations localizations,
  AndroidServiceStatus status,
) => switch (status) {
  AndroidServiceStatus.applying => localizations.configApplying,
  AndroidServiceStatus.stopping => localizations.androidServiceStopping,
  AndroidServiceStatus.suspended => localizations.androidServiceSuspended,
  AndroidServiceStatus.stopped => localizations.androidServiceStopped,
  AndroidServiceStatus.vpnActive => localizations.androidServiceVpnActive,
  AndroidServiceStatus.proxyOnly => localizations.androidServiceProxyOnly,
  AndroidServiceStatus.unavailable => localizations.androidServiceUnavailable,
};
