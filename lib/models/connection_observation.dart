import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/connection_observation.freezed.dart';
part 'generated/connection_observation.g.dart';

@freezed
abstract class ApplicationIdentity with _$ApplicationIdentity {
  const ApplicationIdentity._();

  const factory ApplicationIdentity({
    @Default('unknown') String status,
    int? uid,
    @Default('unknown') String userScope,
    @Default([]) List<String> packages,
    @Default('unavailable') String method,
  }) = _ApplicationIdentity;

  factory ApplicationIdentity.fromJson(Map<String, Object?> json) =>
      _$ApplicationIdentityFromJson(json);

  String? get packageName =>
      status == 'known' &&
          uid != null &&
          uid! >= 0 &&
          userScope == 'current' &&
          packages.length == 1 &&
          packages.single.isNotEmpty
      ? packages.single
      : null;
}

@freezed
abstract class ConnectionCapture with _$ConnectionCapture {
  const ConnectionCapture._();

  const factory ConnectionCapture({
    @Default('unknown') String status,
    @Default('') String serviceId,
    int? generation,
  }) = _ConnectionCapture;

  factory ConnectionCapture.fromJson(Map<String, Object?> json) =>
      _$ConnectionCaptureFromJson(json);

  bool get isVpn =>
      status == 'vpn' && serviceId.isNotEmpty && (generation ?? 0) > 0;
}

@freezed
abstract class ConnectionConfiguration with _$ConnectionConfiguration {
  const factory ConnectionConfiguration({
    @Default('unknown') String status,
    @Default('') String inputId,
    @Default('') String mode,
    int? routeEpoch,
    int? picksVersion,
  }) = _ConnectionConfiguration;

  factory ConnectionConfiguration.fromJson(Map<String, Object?> json) =>
      _$ConnectionConfigurationFromJson(json);
}

@freezed
abstract class ConnectionObservation with _$ConnectionObservation {
  const factory ConnectionObservation({
    @Default(1) int version,
    @Default('') String runtimeEpoch,
    @Default(ApplicationIdentity()) ApplicationIdentity application,
    @Default(ConnectionCapture()) ConnectionCapture capture,
    @Default(ConnectionConfiguration()) ConnectionConfiguration configuration,
  }) = _ConnectionObservation;

  factory ConnectionObservation.fromJson(Map<String, Object?> json) =>
      json['version'] == 1
      ? _$ConnectionObservationFromJson(json)
      : ConnectionObservation(version: (json['version'] as num?)?.toInt() ?? 0);
}
