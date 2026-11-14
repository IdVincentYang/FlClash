import 'package:freezed_annotation/freezed_annotation.dart';
import 'clash_config.dart';

part 'generated/application_routing.freezed.dart';
part 'generated/application_routing.g.dart';

enum ApplicationRouteAction { proxy, direct, reject }

enum ApplicationTargetKind { group, node, globalGroup }

@freezed
abstract class HostRuleBinding with _$HostRuleBinding {
  const factory HostRuleBinding({
    String? packageName,
    int? profileId,
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default(false)
    bool legacy,
    @Default({}) Map<int, ApplicationRouteTarget> targets,
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default([])
    List<int> disabledProfiles,
  }) = _HostRuleBinding;

  factory HostRuleBinding.fromJson(Map<String, dynamic> json) =>
      _$HostRuleBindingFromJson(json);
}

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
    @Default(true) bool hasDefault,
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
    @JsonKey(includeFromJson: false, includeToJson: false)
    @Default([])
    List<Rule> hostRules,
  }) = _ApplicationRoutingSettings;

  factory ApplicationRoutingSettings.fromJson(Map<String, dynamic> json) =>
      _$ApplicationRoutingSettingsFromJson(json);
}
