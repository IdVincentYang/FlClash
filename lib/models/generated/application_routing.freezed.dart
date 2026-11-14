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
mixin _$HostRuleBinding {

 String? get packageName; int? get profileId;@JsonKey(includeFromJson: false, includeToJson: false) bool get legacy; Map<int, ApplicationRouteTarget> get targets;@JsonKey(includeFromJson: false, includeToJson: false) List<int> get disabledProfiles;
/// Create a copy of HostRuleBinding
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HostRuleBindingCopyWith<HostRuleBinding> get copyWith => _$HostRuleBindingCopyWithImpl<HostRuleBinding>(this as HostRuleBinding, _$identity);

  /// Serializes this HostRuleBinding to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as HostRuleBinding;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HostRuleBinding&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.legacy, _this.legacy) || other.legacy == _this.legacy)&&const DeepCollectionEquality().equals(other.targets, _this.targets)&&const DeepCollectionEquality().equals(other.disabledProfiles, _this.disabledProfiles));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as HostRuleBinding;
  return Object.hash(runtimeType,_this.packageName,_this.profileId,_this.legacy,const DeepCollectionEquality().hash(_this.targets),const DeepCollectionEquality().hash(_this.disabledProfiles));
}

@override
String toString() {
  final _this = this as HostRuleBinding;
  return 'HostRuleBinding(packageName: ${_this.packageName}, profileId: ${_this.profileId}, legacy: ${_this.legacy}, targets: ${_this.targets}, disabledProfiles: ${_this.disabledProfiles})';
}


}

/// @nodoc
abstract mixin class $HostRuleBindingCopyWith<$Res>  {
  factory $HostRuleBindingCopyWith(HostRuleBinding value, $Res Function(HostRuleBinding) _then) = _$HostRuleBindingCopyWithImpl;
@useResult
$Res call({
 String? packageName, int? profileId,@JsonKey(includeFromJson: false, includeToJson: false) bool legacy, Map<int, ApplicationRouteTarget> targets,@JsonKey(includeFromJson: false, includeToJson: false) List<int> disabledProfiles
});




}
/// @nodoc
class _$HostRuleBindingCopyWithImpl<$Res>
    implements $HostRuleBindingCopyWith<$Res> {
  _$HostRuleBindingCopyWithImpl(this._self, this._then);

  final HostRuleBinding _self;
  final $Res Function(HostRuleBinding) _then;

/// Create a copy of HostRuleBinding
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? packageName = freezed,Object? profileId = freezed,Object? legacy = null,Object? targets = null,Object? disabledProfiles = null,}) {
  return _then(HostRuleBinding(
packageName: freezed == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String?,profileId: freezed == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as int?,legacy: null == legacy ? _self.legacy : legacy // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,disabledProfiles: null == disabledProfiles ? _self.disabledProfiles : disabledProfiles // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

}


/// Adds pattern-matching-related methods to [HostRuleBinding].
extension HostRuleBindingPatterns on HostRuleBinding {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HostRuleBinding value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HostRuleBinding() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HostRuleBinding value)  $default,){
final _that = this;
switch (_that) {
case _HostRuleBinding():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HostRuleBinding value)?  $default,){
final _that = this;
switch (_that) {
case _HostRuleBinding() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? packageName,  int? profileId, @JsonKey(includeFromJson: false, includeToJson: false)  bool legacy,  Map<int, ApplicationRouteTarget> targets, @JsonKey(includeFromJson: false, includeToJson: false)  List<int> disabledProfiles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HostRuleBinding() when $default != null:
return $default(_that.packageName,_that.profileId,_that.legacy,_that.targets,_that.disabledProfiles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? packageName,  int? profileId, @JsonKey(includeFromJson: false, includeToJson: false)  bool legacy,  Map<int, ApplicationRouteTarget> targets, @JsonKey(includeFromJson: false, includeToJson: false)  List<int> disabledProfiles)  $default,) {final _that = this;
switch (_that) {
case _HostRuleBinding():
return $default(_that.packageName,_that.profileId,_that.legacy,_that.targets,_that.disabledProfiles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? packageName,  int? profileId, @JsonKey(includeFromJson: false, includeToJson: false)  bool legacy,  Map<int, ApplicationRouteTarget> targets, @JsonKey(includeFromJson: false, includeToJson: false)  List<int> disabledProfiles)?  $default,) {final _that = this;
switch (_that) {
case _HostRuleBinding() when $default != null:
return $default(_that.packageName,_that.profileId,_that.legacy,_that.targets,_that.disabledProfiles);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _HostRuleBinding implements HostRuleBinding {
  const _HostRuleBinding({this.packageName, this.profileId, @JsonKey(includeFromJson: false, includeToJson: false) this.legacy = false,  Map<int, ApplicationRouteTarget> targets = const {}, @JsonKey(includeFromJson: false, includeToJson: false)  List<int> disabledProfiles = const []}): _targets = targets,_disabledProfiles = disabledProfiles;
  factory _HostRuleBinding.fromJson(Map<String, dynamic> json) => _$HostRuleBindingFromJson(json);

@override final  String? packageName;
@override final  int? profileId;
@override@JsonKey(includeFromJson: false, includeToJson: false) final  bool legacy;
 final  Map<int, ApplicationRouteTarget> _targets;
@override@JsonKey() Map<int, ApplicationRouteTarget> get targets {
  if (_targets is EqualUnmodifiableMapView) return _targets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_targets);
}

 final  List<int> _disabledProfiles;
@override@JsonKey(includeFromJson: false, includeToJson: false) List<int> get disabledProfiles {
  if (_disabledProfiles is EqualUnmodifiableListView) return _disabledProfiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_disabledProfiles);
}


/// Create a copy of HostRuleBinding
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HostRuleBindingCopyWith<_HostRuleBinding> get copyWith => __$HostRuleBindingCopyWithImpl<_HostRuleBinding>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$HostRuleBindingToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _HostRuleBinding&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.legacy, legacy) || other.legacy == legacy)&&const DeepCollectionEquality().equals(other.targets, _targets)&&const DeepCollectionEquality().equals(other.disabledProfiles, _disabledProfiles));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,packageName,profileId,legacy,const DeepCollectionEquality().hash(_targets),const DeepCollectionEquality().hash(_disabledProfiles));
}

@override
String toString() {
    return 'HostRuleBinding(packageName: $packageName, profileId: $profileId, legacy: $legacy, targets: $targets, disabledProfiles: $disabledProfiles)';
}


}

/// @nodoc
abstract mixin class _$HostRuleBindingCopyWith<$Res> implements $HostRuleBindingCopyWith<$Res> {
  factory _$HostRuleBindingCopyWith(_HostRuleBinding value, $Res Function(_HostRuleBinding) _then) = __$HostRuleBindingCopyWithImpl;
@override @useResult
$Res call({
 String? packageName, int? profileId,@JsonKey(includeFromJson: false, includeToJson: false) bool legacy, Map<int, ApplicationRouteTarget> targets,@JsonKey(includeFromJson: false, includeToJson: false) List<int> disabledProfiles
});




}
/// @nodoc
class __$HostRuleBindingCopyWithImpl<$Res>
    implements _$HostRuleBindingCopyWith<$Res> {
  __$HostRuleBindingCopyWithImpl(this._self, this._then);

  final _HostRuleBinding _self;
  final $Res Function(_HostRuleBinding) _then;

/// Create a copy of HostRuleBinding
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? packageName = freezed,Object? profileId = freezed,Object? legacy = null,Object? targets = null,Object? disabledProfiles = null,}) {
  return _then(_HostRuleBinding(
packageName: freezed == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String?,profileId: freezed == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as int?,legacy: null == legacy ? _self.legacy : legacy // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,disabledProfiles: null == disabledProfiles ? _self._disabledProfiles : disabledProfiles // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}


}


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

 String get packageName; bool get enabled; bool get hasDefault; ApplicationRouteAction get action; bool get useSharedTarget; Map<int, ApplicationRouteTarget> get targets;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationRouteRule&&(identical(other.packageName, _this.packageName) || other.packageName == _this.packageName)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.hasDefault, _this.hasDefault) || other.hasDefault == _this.hasDefault)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.useSharedTarget, _this.useSharedTarget) || other.useSharedTarget == _this.useSharedTarget)&&const DeepCollectionEquality().equals(other.targets, _this.targets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ApplicationRouteRule;
  return Object.hash(runtimeType,_this.packageName,_this.enabled,_this.hasDefault,_this.action,_this.useSharedTarget,const DeepCollectionEquality().hash(_this.targets));
}

@override
String toString() {
  final _this = this as ApplicationRouteRule;
  return 'ApplicationRouteRule(packageName: ${_this.packageName}, enabled: ${_this.enabled}, hasDefault: ${_this.hasDefault}, action: ${_this.action}, useSharedTarget: ${_this.useSharedTarget}, targets: ${_this.targets})';
}


}

/// @nodoc
abstract mixin class $ApplicationRouteRuleCopyWith<$Res>  {
  factory $ApplicationRouteRuleCopyWith(ApplicationRouteRule value, $Res Function(ApplicationRouteRule) _then) = _$ApplicationRouteRuleCopyWithImpl;
@useResult
$Res call({
 String packageName, bool enabled, bool hasDefault, ApplicationRouteAction action, bool useSharedTarget, Map<int, ApplicationRouteTarget> targets
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
@pragma('vm:prefer-inline') @override $Res call({Object? packageName = null,Object? enabled = null,Object? hasDefault = null,Object? action = null,Object? useSharedTarget = null,Object? targets = null,}) {
  return _then(ApplicationRouteRule(
packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,hasDefault: null == hasDefault ? _self.hasDefault : hasDefault // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String packageName,  bool enabled,  bool hasDefault,  ApplicationRouteAction action,  bool useSharedTarget,  Map<int, ApplicationRouteTarget> targets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationRouteRule() when $default != null:
return $default(_that.packageName,_that.enabled,_that.hasDefault,_that.action,_that.useSharedTarget,_that.targets);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String packageName,  bool enabled,  bool hasDefault,  ApplicationRouteAction action,  bool useSharedTarget,  Map<int, ApplicationRouteTarget> targets)  $default,) {final _that = this;
switch (_that) {
case _ApplicationRouteRule():
return $default(_that.packageName,_that.enabled,_that.hasDefault,_that.action,_that.useSharedTarget,_that.targets);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String packageName,  bool enabled,  bool hasDefault,  ApplicationRouteAction action,  bool useSharedTarget,  Map<int, ApplicationRouteTarget> targets)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationRouteRule() when $default != null:
return $default(_that.packageName,_that.enabled,_that.hasDefault,_that.action,_that.useSharedTarget,_that.targets);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApplicationRouteRule implements ApplicationRouteRule {
  const _ApplicationRouteRule({required this.packageName, this.enabled = false, this.hasDefault = true, this.action = ApplicationRouteAction.proxy, this.useSharedTarget = true,  Map<int, ApplicationRouteTarget> targets = const {}}): _targets = targets;
  factory _ApplicationRouteRule.fromJson(Map<String, dynamic> json) => _$ApplicationRouteRuleFromJson(json);

@override final  String packageName;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool hasDefault;
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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationRouteRule&&(identical(other.packageName, packageName) || other.packageName == packageName)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.hasDefault, hasDefault) || other.hasDefault == hasDefault)&&(identical(other.action, action) || other.action == action)&&(identical(other.useSharedTarget, useSharedTarget) || other.useSharedTarget == useSharedTarget)&&const DeepCollectionEquality().equals(other.targets, _targets));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,packageName,enabled,hasDefault,action,useSharedTarget,const DeepCollectionEquality().hash(_targets));
}

@override
String toString() {
    return 'ApplicationRouteRule(packageName: $packageName, enabled: $enabled, hasDefault: $hasDefault, action: $action, useSharedTarget: $useSharedTarget, targets: $targets)';
}


}

/// @nodoc
abstract mixin class _$ApplicationRouteRuleCopyWith<$Res> implements $ApplicationRouteRuleCopyWith<$Res> {
  factory _$ApplicationRouteRuleCopyWith(_ApplicationRouteRule value, $Res Function(_ApplicationRouteRule) _then) = __$ApplicationRouteRuleCopyWithImpl;
@override @useResult
$Res call({
 String packageName, bool enabled, bool hasDefault, ApplicationRouteAction action, bool useSharedTarget, Map<int, ApplicationRouteTarget> targets
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
@override @pragma('vm:prefer-inline') $Res call({Object? packageName = null,Object? enabled = null,Object? hasDefault = null,Object? action = null,Object? useSharedTarget = null,Object? targets = null,}) {
  return _then(_ApplicationRouteRule(
packageName: null == packageName ? _self.packageName : packageName // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,hasDefault: null == hasDefault ? _self.hasDefault : hasDefault // ignore: cast_nullable_to_non_nullable
as bool,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as ApplicationRouteAction,useSharedTarget: null == useSharedTarget ? _self.useSharedTarget : useSharedTarget // ignore: cast_nullable_to_non_nullable
as bool,targets: null == targets ? _self._targets : targets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,
  ));
}


}


/// @nodoc
mixin _$ApplicationRoutingSettings {

 int get revision; Map<String, ApplicationRouteRule> get rules; Map<int, ApplicationRouteTarget> get sharedTargets;@JsonKey(includeFromJson: false, includeToJson: false) List<Rule> get hostRules;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationRoutingSettings&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&const DeepCollectionEquality().equals(other.rules, _this.rules)&&const DeepCollectionEquality().equals(other.sharedTargets, _this.sharedTargets)&&const DeepCollectionEquality().equals(other.hostRules, _this.hostRules));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ApplicationRoutingSettings;
  return Object.hash(runtimeType,_this.revision,const DeepCollectionEquality().hash(_this.rules),const DeepCollectionEquality().hash(_this.sharedTargets),const DeepCollectionEquality().hash(_this.hostRules));
}

@override
String toString() {
  final _this = this as ApplicationRoutingSettings;
  return 'ApplicationRoutingSettings(revision: ${_this.revision}, rules: ${_this.rules}, sharedTargets: ${_this.sharedTargets}, hostRules: ${_this.hostRules})';
}


}

/// @nodoc
abstract mixin class $ApplicationRoutingSettingsCopyWith<$Res>  {
  factory $ApplicationRoutingSettingsCopyWith(ApplicationRoutingSettings value, $Res Function(ApplicationRoutingSettings) _then) = _$ApplicationRoutingSettingsCopyWithImpl;
@useResult
$Res call({
 int revision, Map<String, ApplicationRouteRule> rules, Map<int, ApplicationRouteTarget> sharedTargets,@JsonKey(includeFromJson: false, includeToJson: false) List<Rule> hostRules
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
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? rules = null,Object? sharedTargets = null,Object? hostRules = null,}) {
  return _then(ApplicationRoutingSettings(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,rules: null == rules ? _self.rules : rules // ignore: cast_nullable_to_non_nullable
as Map<String, ApplicationRouteRule>,sharedTargets: null == sharedTargets ? _self.sharedTargets : sharedTargets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,hostRules: null == hostRules ? _self.hostRules : hostRules // ignore: cast_nullable_to_non_nullable
as List<Rule>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  Map<String, ApplicationRouteRule> rules,  Map<int, ApplicationRouteTarget> sharedTargets, @JsonKey(includeFromJson: false, includeToJson: false)  List<Rule> hostRules)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationRoutingSettings() when $default != null:
return $default(_that.revision,_that.rules,_that.sharedTargets,_that.hostRules);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  Map<String, ApplicationRouteRule> rules,  Map<int, ApplicationRouteTarget> sharedTargets, @JsonKey(includeFromJson: false, includeToJson: false)  List<Rule> hostRules)  $default,) {final _that = this;
switch (_that) {
case _ApplicationRoutingSettings():
return $default(_that.revision,_that.rules,_that.sharedTargets,_that.hostRules);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  Map<String, ApplicationRouteRule> rules,  Map<int, ApplicationRouteTarget> sharedTargets, @JsonKey(includeFromJson: false, includeToJson: false)  List<Rule> hostRules)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationRoutingSettings() when $default != null:
return $default(_that.revision,_that.rules,_that.sharedTargets,_that.hostRules);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApplicationRoutingSettings implements ApplicationRoutingSettings {
  const _ApplicationRoutingSettings({this.revision = 0,  Map<String, ApplicationRouteRule> rules = const {},  Map<int, ApplicationRouteTarget> sharedTargets = const {}, @JsonKey(includeFromJson: false, includeToJson: false)  List<Rule> hostRules = const []}): _rules = rules,_sharedTargets = sharedTargets,_hostRules = hostRules;
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

 final  List<Rule> _hostRules;
@override@JsonKey(includeFromJson: false, includeToJson: false) List<Rule> get hostRules {
  if (_hostRules is EqualUnmodifiableListView) return _hostRules;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_hostRules);
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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationRoutingSettings&&(identical(other.revision, revision) || other.revision == revision)&&const DeepCollectionEquality().equals(other.rules, _rules)&&const DeepCollectionEquality().equals(other.sharedTargets, _sharedTargets)&&const DeepCollectionEquality().equals(other.hostRules, _hostRules));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,revision,const DeepCollectionEquality().hash(_rules),const DeepCollectionEquality().hash(_sharedTargets),const DeepCollectionEquality().hash(_hostRules));
}

@override
String toString() {
    return 'ApplicationRoutingSettings(revision: $revision, rules: $rules, sharedTargets: $sharedTargets, hostRules: $hostRules)';
}


}

/// @nodoc
abstract mixin class _$ApplicationRoutingSettingsCopyWith<$Res> implements $ApplicationRoutingSettingsCopyWith<$Res> {
  factory _$ApplicationRoutingSettingsCopyWith(_ApplicationRoutingSettings value, $Res Function(_ApplicationRoutingSettings) _then) = __$ApplicationRoutingSettingsCopyWithImpl;
@override @useResult
$Res call({
 int revision, Map<String, ApplicationRouteRule> rules, Map<int, ApplicationRouteTarget> sharedTargets,@JsonKey(includeFromJson: false, includeToJson: false) List<Rule> hostRules
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
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? rules = null,Object? sharedTargets = null,Object? hostRules = null,}) {
  return _then(_ApplicationRoutingSettings(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,rules: null == rules ? _self._rules : rules // ignore: cast_nullable_to_non_nullable
as Map<String, ApplicationRouteRule>,sharedTargets: null == sharedTargets ? _self._sharedTargets : sharedTargets // ignore: cast_nullable_to_non_nullable
as Map<int, ApplicationRouteTarget>,hostRules: null == hostRules ? _self._hostRules : hostRules // ignore: cast_nullable_to_non_nullable
as List<Rule>,
  ));
}


}

// dart format on
