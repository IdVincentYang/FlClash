// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../connection_observation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ApplicationIdentity _$ApplicationIdentityFromJson(Map<String, dynamic> json) =>
    _ApplicationIdentity(
      status: json['status'] as String? ?? 'unknown',
      uid: (json['uid'] as num?)?.toInt(),
      userScope: json['userScope'] as String? ?? 'unknown',
      packages:
          (json['packages'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      method: json['method'] as String? ?? 'unavailable',
    );

Map<String, dynamic> _$ApplicationIdentityToJson(
  _ApplicationIdentity instance,
) => <String, dynamic>{
  'status': instance.status,
  'uid': instance.uid,
  'userScope': instance.userScope,
  'packages': instance.packages,
  'method': instance.method,
};

_ConnectionCapture _$ConnectionCaptureFromJson(Map<String, dynamic> json) =>
    _ConnectionCapture(
      status: json['status'] as String? ?? 'unknown',
      serviceId: json['serviceId'] as String? ?? '',
      generation: (json['generation'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ConnectionCaptureToJson(_ConnectionCapture instance) =>
    <String, dynamic>{
      'status': instance.status,
      'serviceId': instance.serviceId,
      'generation': instance.generation,
    };

_ConnectionConfiguration _$ConnectionConfigurationFromJson(
  Map<String, dynamic> json,
) => _ConnectionConfiguration(
  status: json['status'] as String? ?? 'unknown',
  inputId: json['inputId'] as String? ?? '',
  mode: json['mode'] as String? ?? '',
  routeEpoch: (json['routeEpoch'] as num?)?.toInt(),
  picksVersion: (json['picksVersion'] as num?)?.toInt(),
);

Map<String, dynamic> _$ConnectionConfigurationToJson(
  _ConnectionConfiguration instance,
) => <String, dynamic>{
  'status': instance.status,
  'inputId': instance.inputId,
  'mode': instance.mode,
  'routeEpoch': instance.routeEpoch,
  'picksVersion': instance.picksVersion,
};

_ConnectionObservation _$ConnectionObservationFromJson(
  Map<String, dynamic> json,
) => _ConnectionObservation(
  version: (json['version'] as num?)?.toInt() ?? 1,
  runtimeEpoch: json['runtimeEpoch'] as String? ?? '',
  application: json['application'] == null
      ? const ApplicationIdentity()
      : ApplicationIdentity.fromJson(
          json['application'] as Map<String, dynamic>,
        ),
  capture: json['capture'] == null
      ? const ConnectionCapture()
      : ConnectionCapture.fromJson(json['capture'] as Map<String, dynamic>),
  configuration: json['configuration'] == null
      ? const ConnectionConfiguration()
      : ConnectionConfiguration.fromJson(
          json['configuration'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$ConnectionObservationToJson(
  _ConnectionObservation instance,
) => <String, dynamic>{
  'version': instance.version,
  'runtimeEpoch': instance.runtimeEpoch,
  'application': instance.application,
  'capture': instance.capture,
  'configuration': instance.configuration,
};
