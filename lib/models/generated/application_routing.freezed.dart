// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../application_routing.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ApplicationRouteTarget {

 String get name; ApplicationTargetKind get kind; int? get groupId;
/// Create a copy of ApplicationRouteTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApplicationRouteTargetCopyWith<ApplicationRouteTarget> get copyWith => _$ApplicationRouteTargetCopyWithImpl<ApplicationRouteTarget>(this as ApplicationRouteTarget, _$identity);

  /// Serializes this ApplicationRouteTarget to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ApplicationRouteTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationRouteTarget&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.groupId, _this.groupId) || other.groupId == _this.groupId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ApplicationRouteTarget;
  return Object.hash(runtimeType,_this.name,_this.kind,_this.groupId);
}

@override
String toString() {
  final _this = this as ApplicationRouteTarget;
  return 'ApplicationRouteTarget(name: ${_this.name}, kind: ${_this.kind}, groupId: ${_this.groupId})';
}


}

/// @nodoc
abstract mixin class $ApplicationRouteTargetCopyWith<$Res>  {
  factory $ApplicationRouteTargetCopyWith(ApplicationRouteTarget value, $Res Function(ApplicationRouteTarget) _then) = _$ApplicationRouteTargetCopyWithImpl;
@useResult
$Res call({
 String name, ApplicationTargetKind kind, int? groupId
});




}
/// @nodoc
class _$ApplicationRouteTargetCopyWithImpl<$Res>
    implements $ApplicationRouteTargetCopyWith<$Res> {
  _$ApplicationRouteTargetCopyWithImpl(this._self, this._then);

  final ApplicationRouteTarget _self;
  final $Res Function(ApplicationRouteTarget) _then;

/// Create a copy of ApplicationRouteTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? kind = null,Object? groupId = freezed,}) {
  return _then(ApplicationRouteTarget(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ApplicationTargetKind,groupId: freezed == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ApplicationRouteTarget].
extension ApplicationRouteTargetPatterns on ApplicationRouteTarget {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApplicationRouteTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApplicationRouteTarget() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApplicationRouteTarget value)  $default,){
final _that = this;
switch (_that) {
case _ApplicationRouteTarget():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApplicationRouteTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ApplicationRouteTarget() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  ApplicationTargetKind kind,  int? groupId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationRouteTarget() when $default != null:
return $default(_that.name,_that.kind,_that.groupId);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  ApplicationTargetKind kind,  int? groupId)  $default,) {final _that = this;
switch (_that) {
case _ApplicationRouteTarget():
return $default(_that.name,_that.kind,_that.groupId);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  ApplicationTargetKind kind,  int? groupId)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationRouteTarget() when $default != null:
return $default(_that.name,_that.kind,_that.groupId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApplicationRouteTarget implements ApplicationRouteTarget {
  const _ApplicationRouteTarget({required this.name, required this.kind, this.groupId});
  factory _ApplicationRouteTarget.fromJson(Map<String, dynamic> json) => _$ApplicationRouteTargetFromJson(json);

@override final  String name;
@override final  ApplicationTargetKind kind;
@override final  int? groupId;

/// Create a copy of ApplicationRouteTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApplicationRouteTargetCopyWith<_ApplicationRouteTarget> get copyWith => __$ApplicationRouteTargetCopyWithImpl<_ApplicationRouteTarget>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ApplicationRouteTargetToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationRouteTarget&&(identical(other.name, name) || other.name == name)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.groupId, groupId) || other.groupId == groupId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,kind,groupId);
}

@override
String toString() {
    return 'ApplicationRouteTarget(name: $name, kind: $kind, groupId: $groupId)';
}


}

/// @nodoc
abstract mixin class _$ApplicationRouteTargetCopyWith<$Res> implements $ApplicationRouteTargetCopyWith<$Res> {
  factory _$ApplicationRouteTargetCopyWith(_ApplicationRouteTarget value, $Res Function(_ApplicationRouteTarget) _then) = __$ApplicationRouteTargetCopyWithImpl;
@override @useResult
$Res call({
 String name, ApplicationTargetKind kind, int? groupId
});




}
/// @nodoc
class __$ApplicationRouteTargetCopyWithImpl<$Res>
    implements _$ApplicationRouteTargetCopyWith<$Res> {
  __$ApplicationRouteTargetCopyWithImpl(this._self, this._then);

  final _ApplicationRouteTarget _self;
  final $Res Function(_ApplicationRouteTarget) _then;

/// Create a copy of ApplicationRouteTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? kind = null,Object? groupId = freezed,}) {
  return _then(_ApplicationRouteTarget(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ApplicationTargetKind,groupId: freezed == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$ApplicationRouteRule {

 String get packageName; bool get enabled; ApplicationRouteAction get action; bool get useSharedTarget; Map<int, ApplicationRouteTarget> get targets;
/// Create a copy of ApplicationRouteRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApplicationRouteRuleCopyWith<ApplicationRouteRule> get copyWith => _$ApplicationRouteRuleCopyWithImpl<ApplicationRouteRule>(this as ApplicationRouteRule, _$identity);

  /// Serializes this ApplicationRouteRule to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ApplicationRouteRule;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationRouteRule&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.useSharedTarget, _this.useSharedTarget) || other.useSharedTarget == _this.useSharedTarget)&&const DeepCollectionEquality().equals(other.targets, _this.targets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ApplicationRouteRule;
  return Object.hash(runtimeType,_this.packageName,_this.enabled,_this.action,_this.useSharedTarget,const DeepCollectionEquality().hash(_this.targets));
}

@override
String toString() {
  final _this = this as ApplicationRouteRule;
  return 'ApplicationRouteRule(packageName: ${_this.packageName}, enabled: ${_this.enabled}, action: ${_this.action}, useSharedTarget: ${_this.useSharedTarget}, targets: ${_this.targets})';
}


}

/// @nodoc
abstract mixin class $ApplicationRouteRuleCopyWith<$Res>  {
  factory $ApplicationRouteRuleCopyWith(ApplicationRouteRule value, $Res Function(ApplicationRouteRule) _then) = _$ApplicationRouteRuleCopyWithImpl;
@useResult
$Res call({
 String packageName, bool enabled, ApplicationRouteAction action, bool useSharedTarget, Map<int, ApplicationRouteTarget> targets
});




}
/// @nodoc
class _$ApplicationRouteRuleCopyWithImpl<$Res>
    implements $ApplicationRouteRuleCopyWith<$Res> {
  _$ApplicationRouteRuleCopyWithImpl(this._self, this._then);

  final ApplicationRouteRule _self;
  final $Res Function(ApplicationRouteRule) _then;

/// Create a copy of ApplicationRouteRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? packageName = null,Object? enabled = null,Object? action = null,Object? useSharedTarget = null,Object? targets = null,}) {
  return _then(ApplicationRouteRule(
packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ApplicationRouteAction,useSharedTarget: null == useSharedTarget ? _self.useSharedTarget : useSharedTarget // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,
  ));
}

}


/// Adds pattern-matching-related methods to [ApplicationRouteRule].
extension ApplicationRouteRulePatterns on ApplicationRouteRule {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApplicationRouteRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApplicationRouteRule() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApplicationRouteRule value)  $default,){
final _that = this;
switch (_that) {
case _ApplicationRouteRule():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApplicationRouteRule value)?  $default,){
final _that = this;
switch (_that) {
case _ApplicationRouteRule() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String packageName,  bool enabled,  ApplicationRouteAction action,  bool useSharedTarget,  Map<int, ApplicationRouteTarget> targets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationRouteRule() when $default != null:
return $default(_that.packageName,_that.enabled,_that.action,_that.useSharedTarget,_that.targets);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String packageName,  bool enabled,  ApplicationRouteAction action,  bool useSharedTarget,  Map<int, ApplicationRouteTarget> targets)  $default,) {final _that = this;
switch (_that) {
case _ApplicationRouteRule():
return $default(_that.packageName,_that.enabled,_that.action,_that.useSharedTarget,_that.targets);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String packageName,  bool enabled,  ApplicationRouteAction action,  bool useSharedTarget,  Map<int, ApplicationRouteTarget> targets)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationRouteRule() when $default != null:
return $default(_that.packageName,_that.enabled,_that.action,_that.useSharedTarget,_that.targets);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApplicationRouteRule implements ApplicationRouteRule {
  const _ApplicationRouteRule({required this.packageName, this.enabled = false, this.action = ApplicationRouteAction.proxy, this.useSharedTarget = true,  Map<int, ApplicationRouteTarget> targets = const {}}): _targets = targets;
  factory _ApplicationRouteRule.fromJson(Map<String, dynamic> json) => _$ApplicationRouteRuleFromJson(json);

@override final  String packageName;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  ApplicationRouteAction action;
@override@JsonKey() final  bool useSharedTarget;
 final  Map<int, ApplicationRouteTarget> _targets;
@override@JsonKey() Map<int, ApplicationRouteTarget> get targets {
  if (_targets is EqualUnmodifiableMapView) return _targets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_targets);
}


/// Create a copy of ApplicationRouteRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApplicationRouteRuleCopyWith<_ApplicationRouteRule> get copyWith => __$ApplicationRouteRuleCopyWithImpl<_ApplicationRouteRule>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ApplicationRouteRuleToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationRouteRule&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.action, action) || other.action == action)&&(identical(other.useSharedTarget, useSharedTarget) || other.useSharedTarget == useSharedTarget)&&const DeepCollectionEquality().equals(other.targets, _targets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,packageName,enabled,action,useSharedTarget,const DeepCollectionEquality().hash(_targets));
}

@override
String toString() {
    return 'ApplicationRouteRule(packageName: $packageName, enabled: $enabled, action: $action, useSharedTarget: $useSharedTarget, targets: $targets)';
}


}

/// @nodoc
abstract mixin class _$ApplicationRouteRuleCopyWith<$Res> implements $ApplicationRouteRuleCopyWith<$Res> {
  factory _$ApplicationRouteRuleCopyWith(_ApplicationRouteRule value, $Res Function(_ApplicationRouteRule) _then) = __$ApplicationRouteRuleCopyWithImpl;
@override @useResult
$Res call({
 String packageName, bool enabled, ApplicationRouteAction action, bool useSharedTarget, Map<int, ApplicationRouteTarget> targets
});




}
/// @nodoc
class __$ApplicationRouteRuleCopyWithImpl<$Res>
    implements _$ApplicationRouteRuleCopyWith<$Res> {
  __$ApplicationRouteRuleCopyWithImpl(this._self, this._then);

  final _ApplicationRouteRule _self;
  final $Res Function(_ApplicationRouteRule) _then;

/// Create a copy of ApplicationRouteRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? packageName = null,Object? enabled = null,Object? action = null,Object? useSharedTarget = null,Object? targets = null,}) {
  return _then(_ApplicationRouteRule(
packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ApplicationRouteAction,useSharedTarget: null == useSharedTarget ? _self.useSharedTarget : useSharedTarget // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,
  ));
}


}


/// @nodoc
mixin _$ApplicationRoutingSettings {

 int get revision; Map<String, ApplicationRouteRule> get rules; Map<int, ApplicationRouteTarget> get sharedTargets;
/// Create a copy of ApplicationRoutingSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApplicationRoutingSettingsCopyWith<ApplicationRoutingSettings> get copyWith => _$ApplicationRoutingSettingsCopyWithImpl<ApplicationRoutingSettings>(this as ApplicationRoutingSettings, _$identity);

  /// Serializes this ApplicationRoutingSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ApplicationRoutingSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationRoutingSettings&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&const DeepCollectionEquality().equals(other.rules, _this.rules)&&const DeepCollectionEquality().equals(other.sharedTargets, _this.sharedTargets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ApplicationRoutingSettings;
  return Object.hash(runtimeType,_this.revision,const DeepCollectionEquality().hash(_this.rules),const DeepCollectionEquality().hash(_this.sharedTargets));
}

@override
String toString() {
  final _this = this as ApplicationRoutingSettings;
  return 'ApplicationRoutingSettings(revision: ${_this.revision}, rules: ${_this.rules}, sharedTargets: ${_this.sharedTargets})';
}


}

/// @nodoc
abstract mixin class $ApplicationRoutingSettingsCopyWith<$Res>  {
  factory $ApplicationRoutingSettingsCopyWith(ApplicationRoutingSettings value, $Res Function(ApplicationRoutingSettings) _then) = _$ApplicationRoutingSettingsCopyWithImpl;
@useResult
$Res call({
 int revision, Map<String, ApplicationRouteRule> rules, Map<int, ApplicationRouteTarget> sharedTargets
});




}
/// @nodoc
class _$ApplicationRoutingSettingsCopyWithImpl<$Res>
    implements $ApplicationRoutingSettingsCopyWith<$Res> {
  _$ApplicationRoutingSettingsCopyWithImpl(this._self, this._then);

  final ApplicationRoutingSettings _self;
  final $Res Function(ApplicationRoutingSettings) _then;

/// Create a copy of ApplicationRoutingSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? rules = null,Object? sharedTargets = null,}) {
  return _then(ApplicationRoutingSettings(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,rules: null == rules ? _self.rules : rules // ignore: cast_nullable_to_non_nullable
as Map<String, ApplicationRouteRule>,sharedTargets: null == sharedTargets ? _self.sharedTargets : sharedTargets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,
  ));
}

}


/// Adds pattern-matching-related methods to [ApplicationRoutingSettings].
extension ApplicationRoutingSettingsPatterns on ApplicationRoutingSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApplicationRoutingSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApplicationRoutingSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApplicationRoutingSettings value)  $default,){
final _that = this;
switch (_that) {
case _ApplicationRoutingSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApplicationRoutingSettings value)?  $default,){
final _that = this;
switch (_that) {
case _ApplicationRoutingSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  Map<String, ApplicationRouteRule> rules,  Map<int, ApplicationRouteTarget> sharedTargets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationRoutingSettings() when $default != null:
return $default(_that.revision,_that.rules,_that.sharedTargets);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  Map<String, ApplicationRouteRule> rules,  Map<int, ApplicationRouteTarget> sharedTargets)  $default,) {final _that = this;
switch (_that) {
case _ApplicationRoutingSettings():
return $default(_that.revision,_that.rules,_that.sharedTargets);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  Map<String, ApplicationRouteRule> rules,  Map<int, ApplicationRouteTarget> sharedTargets)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationRoutingSettings() when $default != null:
return $default(_that.revision,_that.rules,_that.sharedTargets);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApplicationRoutingSettings implements ApplicationRoutingSettings {
  const _ApplicationRoutingSettings({this.revision = 0,  Map<String, ApplicationRouteRule> rules = const {},  Map<int, ApplicationRouteTarget> sharedTargets = const {}}): _rules = rules,_sharedTargets = sharedTargets;
  factory _ApplicationRoutingSettings.fromJson(Map<String, dynamic> json) => _$ApplicationRoutingSettingsFromJson(json);

@override@JsonKey() final  int revision;
 final  Map<String, ApplicationRouteRule> _rules;
@override@JsonKey() Map<String, ApplicationRouteRule> get rules {
  if (_rules is EqualUnmodifiableMapView) return _rules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_rules);
}

 final  Map<int, ApplicationRouteTarget> _sharedTargets;
@override@JsonKey() Map<int, ApplicationRouteTarget> get sharedTargets {
  if (_sharedTargets is EqualUnmodifiableMapView) return _sharedTargets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_sharedTargets);
}


/// Create a copy of ApplicationRoutingSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApplicationRoutingSettingsCopyWith<_ApplicationRoutingSettings> get copyWith => __$ApplicationRoutingSettingsCopyWithImpl<_ApplicationRoutingSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ApplicationRoutingSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationRoutingSettings&&(identical(other.revision, revision) || other.revision == revision)&&const DeepCollectionEquality().equals(other.rules, _rules)&&const DeepCollectionEquality().equals(other.sharedTargets, _sharedTargets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,revision,const DeepCollectionEquality().hash(_rules),const DeepCollectionEquality().hash(_sharedTargets));
}

@override
String toString() {
    return 'ApplicationRoutingSettings(revision: $revision, rules: $rules, sharedTargets: $sharedTargets)';
}


}

/// @nodoc
abstract mixin class _$ApplicationRoutingSettingsCopyWith<$Res> implements $ApplicationRoutingSettingsCopyWith<$Res> {
  factory _$ApplicationRoutingSettingsCopyWith(_ApplicationRoutingSettings value, $Res Function(_ApplicationRoutingSettings) _then) = __$ApplicationRoutingSettingsCopyWithImpl;
@override @useResult
$Res call({
 int revision, Map<String, ApplicationRouteRule> rules, Map<int, ApplicationRouteTarget> sharedTargets
});




}
/// @nodoc
class __$ApplicationRoutingSettingsCopyWithImpl<$Res>
    implements _$ApplicationRoutingSettingsCopyWith<$Res> {
  __$ApplicationRoutingSettingsCopyWithImpl(this._self, this._then);

  final _ApplicationRoutingSettings _self;
  final $Res Function(_ApplicationRoutingSettings) _then;

/// Create a copy of ApplicationRoutingSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? rules = null,Object? sharedTargets = null,}) {
  return _then(_ApplicationRoutingSettings(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,rules: null == rules ? _self._rules : rules // ignore: cast_nullable_to_non_nullable
as Map<String, ApplicationRouteRule>,sharedTargets: null == sharedTargets ? _self._sharedTargets : sharedTargets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,
  ));
}


}

// dart format on
