import 'package:fl_clash/enum/enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/ip_quality.freezed.dart';

@freezed
abstract class IpQuality with _$IpQuality {
  const factory IpQuality({
    required String ip,
    required IpQualitySource source,
    IpType? type,
    DateTime? checkedAt,
    String? organization,
    int? asn,
    bool? isProxy,
    bool? isVpn,
    bool? isTor,
    bool? isCompromised,
    bool? isHosting,
    bool? isAnonymous,
    bool? isScraper,
    @Default(false) bool warning,
    Duration? retryAfter,
  }) = _IpQuality;
}
