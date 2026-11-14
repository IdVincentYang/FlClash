// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../application_routing.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ApplicationRouteTarget _$ApplicationRouteTargetFromJson(
  Map<String, dynamic> json,
) => _ApplicationRouteTarget(
  name: json['name'] as String,
  kind: $enumDecode(_$ApplicationTargetKindEnumMap, json['kind']),
  groupId: (json['groupId'] as num?)?.toInt(),
);

Map<String, dynamic> _$ApplicationRouteTargetToJson(
  _ApplicationRouteTarget instance,
) => <String, dynamic>{
  'name': instance.name,
  'kind': _$ApplicationTargetKindEnumMap[instance.kind]!,
  'groupId': instance.groupId,
};

const _$ApplicationTargetKindEnumMap = {
  ApplicationTargetKind.group: 'group',
  ApplicationTargetKind.node: 'node',
  ApplicationTargetKind.globalGroup: 'globalGroup',
};

_ApplicationRouteRule _$ApplicationRouteRuleFromJson(
  Map<String, dynamic> json,
) => _ApplicationRouteRule(
  packageName: json['packageName'] as String,
  enabled: json['enabled'] as bool? ?? false,
  action:
      $enumDecodeNullable(_$ApplicationRouteActionEnumMap, json['action']) ??
      ApplicationRouteAction.proxy,
  useSharedTarget: json['useSharedTarget'] as bool? ?? true,
  targets:
      (json['targets'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          int.parse(k),
          ApplicationRouteTarget.fromJson(e as Map<String, dynamic>),
        ),
      ) ??
      const {},
);

Map<String, dynamic> _$ApplicationRouteRuleToJson(
  _ApplicationRouteRule instance,
) => <String, dynamic>{
  'packageName': instance.packageName,
  'enabled': instance.enabled,
  'action': _$ApplicationRouteActionEnumMap[instance.action]!,
  'useSharedTarget': instance.useSharedTarget,
  'targets': instance.targets.map((k, e) => MapEntry(k.toString(), e)),
};

const _$ApplicationRouteActionEnumMap = {
  ApplicationRouteAction.proxy: 'proxy',
  ApplicationRouteAction.direct: 'direct',
  ApplicationRouteAction.reject: 'reject',
};

_ApplicationRoutingSettings _$ApplicationRoutingSettingsFromJson(
  Map<String, dynamic> json,
) => _ApplicationRoutingSettings(
  revision: (json['revision'] as num?)?.toInt() ?? 0,
  rules:
      (json['rules'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          ApplicationRouteRule.fromJson(e as Map<String, dynamic>),
        ),
      ) ??
      const {},
  sharedTargets:
      (json['sharedTargets'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          int.parse(k),
          ApplicationRouteTarget.fromJson(e as Map<String, dynamic>),
        ),
      ) ??
      const {},
);

Map<String, dynamic> _$ApplicationRoutingSettingsToJson(
  _ApplicationRoutingSettings instance,
) => <String, dynamic>{
  'revision': instance.revision,
  'rules': instance.rules,
  'sharedTargets': instance.sharedTargets.map(
    (k, e) => MapEntry(k.toString(), e),
  ),
};
