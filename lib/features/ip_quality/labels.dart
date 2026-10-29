import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:material_ui/material_ui.dart';

extension IpTypeLabel on IpType {
  String label(BuildContext context) {
    final localizations = context.appLocalizations;
    return switch (this) {
      IpType.residential => localizations.ipTypeResidential,
      IpType.wireless => localizations.ipTypeWireless,
      IpType.business => localizations.ipTypeBusiness,
      IpType.hosting => localizations.ipTypeHosting,
    };
  }
}

String ipLookupReason(BuildContext context, String? code) {
  final l = context.appLocalizations;
  return switch (code) {
    'timeout' => l.timeout,
    'route-unavailable' => l.requestRouteUnavailable,
    'cancelled' => l.ipLookupCancelled,
    'body-limit' => l.ipLookupBodyLimit,
    'ip-mismatch' => l.ipLookupIpMismatch,
    'tls-failed' => l.ipLookupTlsFailed,
    'rate-limited' => l.ipSourceRateLimited,
    'http-failed' ||
    'recipient-blocked' ||
    'source-denied' ||
    'source-error' => l.ipLookupHttpFailed,
    'invalid-ip' || 'invalid-response' || 'read-error' => l.ipLookupInvalid,
    _ => l.serviceFailed,
  };
}
