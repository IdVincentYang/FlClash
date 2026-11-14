import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/application_routing.freezed.dart';
part 'generated/application_routing.g.dart';

enum ApplicationRouteAction { proxy, direct, reject }

enum ApplicationTargetKind { group, node, globalGroup }

@freezed
abstract class ApplicationRouteTarget with _$ApplicationRouteTarget {
  const factory ApplicationRouteTarget({
    required String name,
    required ApplicationTargetKind kind,
    int? groupId,
  }) = _ApplicationRouteTarget;

  factory ApplicationRouteTarget.fromJson(Map<String, dynamic> json) =>
      _$ApplicationRouteTargetFromJson(json);
}

@freezed
abstract class ApplicationRouteRule with _$ApplicationRouteRule {
  const factory ApplicationRouteRule({
    required String packageName,
    @Default(false) bool enabled,
    @Default(ApplicationRouteAction.proxy) ApplicationRouteAction action,
    @Default(true) bool useSharedTarget,
    @Default({}) Map<int, ApplicationRouteTarget> targets,
  }) = _ApplicationRouteRule;

  factory ApplicationRouteRule.fromJson(Map<String, dynamic> json) =>
      _$ApplicationRouteRuleFromJson(json);
}

@freezed
abstract class ApplicationRoutingSettings with _$ApplicationRoutingSettings {
  const factory ApplicationRoutingSettings({
    @Default(0) int revision,
    @Default({}) Map<String, ApplicationRouteRule> rules,
    @Default({}) Map<int, ApplicationRouteTarget> sharedTargets,
  }) = _ApplicationRoutingSettings;

  factory ApplicationRoutingSettings.fromJson(Map<String, dynamic> json) =>
      _$ApplicationRoutingSettingsFromJson(json);
}
