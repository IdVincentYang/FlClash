// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SubscriptionInfo _$SubscriptionInfoFromJson(Map<String, dynamic> json) =>
    _SubscriptionInfo(
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      expire: (json['expire'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$SubscriptionInfoToJson(_SubscriptionInfo instance) =>
    <String, dynamic>{
      'upload': instance.upload,
      'download': instance.download,
      'total': instance.total,
      'expire': instance.expire,
    };

_Profile _$ProfileFromJson(Map<String, dynamic> json) => _Profile(
  id: (json['id'] as num).toInt(),
  label: json['label'] as String? ?? '',
  currentGroupName: json['currentGroupName'] as String?,
  url: json['url'] as String? ?? '',
  requestMode:
      $enumDecodeNullable(_$RequestModeEnumMap, json['requestMode']) ??
      RequestMode.auto,
  requestProxy: json['requestProxy'] as String?,
  lastUpdateDate: json['lastUpdateDate'] == null
      ? null
      : DateTime.parse(json['lastUpdateDate'] as String),
  autoUpdateDuration: Duration(
    microseconds: (json['autoUpdateDuration'] as num).toInt(),
  ),
  subscriptionInfo: json['subscriptionInfo'] == null
      ? null
      : SubscriptionInfo.fromJson(
          json['subscriptionInfo'] as Map<String, dynamic>,
        ),
  autoUpdate: json['autoUpdate'] as bool? ?? true,
  selectedMap:
      (json['selectedMap'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  unfoldSet:
      (json['unfoldSet'] as List<dynamic>?)?.map((e) => e as String).toSet() ??
      const {},
  localGroups:
      (json['localGroups'] as List<dynamic>?)
          ?.map((e) => LocalProxyGroup.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  overwriteType:
      $enumDecodeNullable(_$OverwriteTypeEnumMap, json['overwriteType']) ??
      OverwriteType.standard,
  scriptId: (json['scriptId'] as num?)?.toInt(),
  matchTarget: json['matchTarget'] as String?,
  order: (json['order'] as num?)?.toInt(),
);

Map<String, dynamic> _$ProfileToJson(_Profile instance) => <String, dynamic>{
  'id': instance.id,
  'label': instance.label,
  'currentGroupName': instance.currentGroupName,
  'url': instance.url,
  'requestMode': _$RequestModeEnumMap[instance.requestMode]!,
  'requestProxy': instance.requestProxy,
  'lastUpdateDate': instance.lastUpdateDate?.toIso8601String(),
  'autoUpdateDuration': instance.autoUpdateDuration.inMicroseconds,
  'subscriptionInfo': instance.subscriptionInfo,
  'autoUpdate': instance.autoUpdate,
  'selectedMap': instance.selectedMap,
  'unfoldSet': instance.unfoldSet.toList(),
  'localGroups': instance.localGroups,
  'overwriteType': _$OverwriteTypeEnumMap[instance.overwriteType]!,
  'scriptId': instance.scriptId,
  'matchTarget': instance.matchTarget,
  'order': instance.order,
};

const _$RequestModeEnumMap = {
  RequestMode.auto: 'auto',
  RequestMode.proxy: 'proxy',
  RequestMode.direct: 'direct',
};

const _$OverwriteTypeEnumMap = {
  OverwriteType.standard: 'standard',
  OverwriteType.script: 'script',
  OverwriteType.custom: 'custom',
};

_LocalProxyGroup _$LocalProxyGroupFromJson(Map<String, dynamic> json) =>
    _LocalProxyGroup(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      type:
          $enumDecodeNullable(_$GroupTypeEnumMap, json['type']) ??
          GroupType.Selector,
      nodes:
          (json['nodes'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      regex: json['regex'] as String? ?? '',
      matchedNodes:
          (json['matchedNodes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      excludedNodes:
          (json['excludedNodes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      parents:
          (json['parents'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      parent: json['parent'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      testUrl: json['testUrl'] as String? ?? '',
    );

Map<String, dynamic> _$LocalProxyGroupToJson(_LocalProxyGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': _$GroupTypeEnumMap[instance.type]!,
      'nodes': instance.nodes,
      'regex': instance.regex,
      'matchedNodes': instance.matchedNodes,
      'excludedNodes': instance.excludedNodes,
      'parents': instance.parents,
      'parent': instance.parent,
      'enabled': instance.enabled,
      'testUrl': instance.testUrl,
    };

const _$GroupTypeEnumMap = {
  GroupType.Selector: 'select',
  GroupType.URLTest: 'url-test',
  GroupType.Fallback: 'fallback',
  GroupType.LoadBalance: 'load-balance',
  GroupType.Relay: 'relay',
};

_StandardOverwrite _$StandardOverwriteFromJson(Map<String, dynamic> json) =>
    _StandardOverwrite(
      addedRules:
          (json['addedRules'] as List<dynamic>?)
              ?.map((e) => Rule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      disabledRuleIds:
          (json['disabledRuleIds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );

Map<String, dynamic> _$StandardOverwriteToJson(_StandardOverwrite instance) =>
    <String, dynamic>{
      'addedRules': instance.addedRules,
      'disabledRuleIds': instance.disabledRuleIds,
    };

_ScriptOverwrite _$ScriptOverwriteFromJson(Map<String, dynamic> json) =>
    _ScriptOverwrite(scriptId: (json['scriptId'] as num?)?.toInt());

Map<String, dynamic> _$ScriptOverwriteToJson(_ScriptOverwrite instance) =>
    <String, dynamic>{'scriptId': instance.scriptId};
