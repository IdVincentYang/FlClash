// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../connection_observation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ApplicationIdentity {

 String get status; int? get uid; String get userScope; List<String> get packages; String get method;
/// Create a copy of ApplicationIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApplicationIdentityCopyWith<ApplicationIdentity> get copyWith => _$ApplicationIdentityCopyWithImpl<ApplicationIdentity>(this as ApplicationIdentity, _$identity);

  /// Serializes this ApplicationIdentity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ApplicationIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationIdentity&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.uid, _this.uid) || other.uid == _this.uid)&&(identical(other.userScope, _this.userScope) || other.userScope == _this.userScope)&&const DeepCollectionEquality().equals(other.packages, _this.packages)&&(identical(other.method, _this.method) || other.method == _this.method));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ApplicationIdentity;
  return Object.hash(runtimeType,_this.status,_this.uid,_this.userScope,const DeepCollectionEquality().hash(_this.packages),_this.method);
}

@override
String toString() {
  final _this = this as ApplicationIdentity;
  return 'ApplicationIdentity(status: ${_this.status}, uid: ${_this.uid}, userScope: ${_this.userScope}, packages: ${_this.packages}, method: ${_this.method})';
}


}

/// @nodoc
abstract mixin class $ApplicationIdentityCopyWith<$Res>  {
  factory $ApplicationIdentityCopyWith(ApplicationIdentity value, $Res Function(ApplicationIdentity) _then) = _$ApplicationIdentityCopyWithImpl;
@useResult
$Res call({
 String status, int? uid, String userScope, List<String> packages, String method
});




}
/// @nodoc
class _$ApplicationIdentityCopyWithImpl<$Res>
    implements $ApplicationIdentityCopyWith<$Res> {
  _$ApplicationIdentityCopyWithImpl(this._self, this._then);

  final ApplicationIdentity _self;
  final $Res Function(ApplicationIdentity) _then;

/// Create a copy of ApplicationIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? uid = freezed,Object? userScope = null,Object? packages = null,Object? method = null,}) {
  return _then(ApplicationIdentity(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,uid: freezed == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as int?,userScope: null == userScope ? _self.userScope : userScope // ignore: cast_nullable_to_non_nullable
as String,packages: null == packages ? _self.packages : packages // ignore: cast_nullable_to_non_nullable
as List<String>,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ApplicationIdentity].
extension ApplicationIdentityPatterns on ApplicationIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApplicationIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApplicationIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApplicationIdentity value)  $default,){
final _that = this;
switch (_that) {
case _ApplicationIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApplicationIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _ApplicationIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status,  int? uid,  String userScope,  List<String> packages,  String method)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationIdentity() when $default != null:
return $default(_that.status,_that.uid,_that.userScope,_that.packages,_that.method);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status,  int? uid,  String userScope,  List<String> packages,  String method)  $default,) {final _that = this;
switch (_that) {
case _ApplicationIdentity():
return $default(_that.status,_that.uid,_that.userScope,_that.packages,_that.method);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status,  int? uid,  String userScope,  List<String> packages,  String method)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationIdentity() when $default != null:
return $default(_that.status,_that.uid,_that.userScope,_that.packages,_that.method);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ApplicationIdentity extends ApplicationIdentity {
  const _ApplicationIdentity({this.status = 'unknown', this.uid, this.userScope = 'unknown',  List<String> packages = const [], this.method = 'unavailable'}): _packages = packages,super._();
  factory _ApplicationIdentity.fromJson(Map<String, dynamic> json) => _$ApplicationIdentityFromJson(json);

@override@JsonKey() final  String status;
@override final  int? uid;
@override@JsonKey() final  String userScope;
 final  List<String> _packages;
@override@JsonKey() List<String> get packages {
  if (_packages is EqualUnmodifiableListView) return _packages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_packages);
}

@override@JsonKey() final  String method;

/// Create a copy of ApplicationIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApplicationIdentityCopyWith<_ApplicationIdentity> get copyWith => __$ApplicationIdentityCopyWithImpl<_ApplicationIdentity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ApplicationIdentityToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationIdentity&&(identical(other.status, status) || other.status == status)&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.userScope, userScope) || other.userScope == userScope)&&const DeepCollectionEquality().equals(other.packages, _packages)&&(identical(other.method, method) || other.method == method));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,uid,userScope,const DeepCollectionEquality().hash(_packages),method);
}

@override
String toString() {
    return 'ApplicationIdentity(status: $status, uid: $uid, userScope: $userScope, packages: $packages, method: $method)';
}


}

/// @nodoc
abstract mixin class _$ApplicationIdentityCopyWith<$Res> implements $ApplicationIdentityCopyWith<$Res> {
  factory _$ApplicationIdentityCopyWith(_ApplicationIdentity value, $Res Function(_ApplicationIdentity) _then) = __$ApplicationIdentityCopyWithImpl;
@override @useResult
$Res call({
 String status, int? uid, String userScope, List<String> packages, String method
});




}
/// @nodoc
class __$ApplicationIdentityCopyWithImpl<$Res>
    implements _$ApplicationIdentityCopyWith<$Res> {
  __$ApplicationIdentityCopyWithImpl(this._self, this._then);

  final _ApplicationIdentity _self;
  final $Res Function(_ApplicationIdentity) _then;

/// Create a copy of ApplicationIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? uid = freezed,Object? userScope = null,Object? packages = null,Object? method = null,}) {
  return _then(_ApplicationIdentity(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,uid: freezed == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as int?,userScope: null == userScope ? _self.userScope : userScope // ignore: cast_nullable_to_non_nullable
as String,packages: null == packages ? _self._packages : packages // ignore: cast_nullable_to_non_nullable
as List<String>,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ConnectionCapture {

 String get status; String get serviceId; int? get generation;
/// Create a copy of ConnectionCapture
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionCaptureCopyWith<ConnectionCapture> get copyWith => _$ConnectionCaptureCopyWithImpl<ConnectionCapture>(this as ConnectionCapture, _$identity);

  /// Serializes this ConnectionCapture to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ConnectionCapture;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionCapture&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.serviceId, _this.serviceId) || other.serviceId == _this.serviceId)&&(identical(other.generation, _this.generation) || other.generation == _this.generation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ConnectionCapture;
  return Object.hash(runtimeType,_this.status,_this.serviceId,_this.generation);
}

@override
String toString() {
  final _this = this as ConnectionCapture;
  return 'ConnectionCapture(status: ${_this.status}, serviceId: ${_this.serviceId}, generation: ${_this.generation})';
}


}

/// @nodoc
abstract mixin class $ConnectionCaptureCopyWith<$Res>  {
  factory $ConnectionCaptureCopyWith(ConnectionCapture value, $Res Function(ConnectionCapture) _then) = _$ConnectionCaptureCopyWithImpl;
@useResult
$Res call({
 String status, String serviceId, int? generation
});




}
/// @nodoc
class _$ConnectionCaptureCopyWithImpl<$Res>
    implements $ConnectionCaptureCopyWith<$Res> {
  _$ConnectionCaptureCopyWithImpl(this._self, this._then);

  final ConnectionCapture _self;
  final $Res Function(ConnectionCapture) _then;

/// Create a copy of ConnectionCapture
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? serviceId = null,Object? generation = freezed,}) {
  return _then(ConnectionCapture(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,serviceId: null == serviceId ? _self.serviceId : serviceId // ignore: cast_nullable_to_non_nullable
as String,generation: freezed == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConnectionCapture].
extension ConnectionCapturePatterns on ConnectionCapture {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionCapture value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionCapture() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionCapture value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionCapture():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionCapture value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionCapture() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status,  String serviceId,  int? generation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionCapture() when $default != null:
return $default(_that.status,_that.serviceId,_that.generation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status,  String serviceId,  int? generation)  $default,) {final _that = this;
switch (_that) {
case _ConnectionCapture():
return $default(_that.status,_that.serviceId,_that.generation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status,  String serviceId,  int? generation)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionCapture() when $default != null:
return $default(_that.status,_that.serviceId,_that.generation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConnectionCapture extends ConnectionCapture {
  const _ConnectionCapture({this.status = 'unknown', this.serviceId = '', this.generation}): super._();
  factory _ConnectionCapture.fromJson(Map<String, dynamic> json) => _$ConnectionCaptureFromJson(json);

@override@JsonKey() final  String status;
@override@JsonKey() final  String serviceId;
@override final  int? generation;

/// Create a copy of ConnectionCapture
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionCaptureCopyWith<_ConnectionCapture> get copyWith => __$ConnectionCaptureCopyWithImpl<_ConnectionCapture>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConnectionCaptureToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionCapture&&(identical(other.status, status) || other.status == status)&&(identical(other.serviceId, serviceId) || other.serviceId == serviceId)&&(identical(other.generation, generation) || other.generation == generation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,serviceId,generation);
}

@override
String toString() {
    return 'ConnectionCapture(status: $status, serviceId: $serviceId, generation: $generation)';
}


}

/// @nodoc
abstract mixin class _$ConnectionCaptureCopyWith<$Res> implements $ConnectionCaptureCopyWith<$Res> {
  factory _$ConnectionCaptureCopyWith(_ConnectionCapture value, $Res Function(_ConnectionCapture) _then) = __$ConnectionCaptureCopyWithImpl;
@override @useResult
$Res call({
 String status, String serviceId, int? generation
});




}
/// @nodoc
class __$ConnectionCaptureCopyWithImpl<$Res>
    implements _$ConnectionCaptureCopyWith<$Res> {
  __$ConnectionCaptureCopyWithImpl(this._self, this._then);

  final _ConnectionCapture _self;
  final $Res Function(_ConnectionCapture) _then;

/// Create a copy of ConnectionCapture
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? serviceId = null,Object? generation = freezed,}) {
  return _then(_ConnectionCapture(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,serviceId: null == serviceId ? _self.serviceId : serviceId // ignore: cast_nullable_to_non_nullable
as String,generation: freezed == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$ConnectionConfiguration {

 String get status; String get inputId; String get mode; int? get routeEpoch; int? get picksVersion;
/// Create a copy of ConnectionConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionConfigurationCopyWith<ConnectionConfiguration> get copyWith => _$ConnectionConfigurationCopyWithImpl<ConnectionConfiguration>(this as ConnectionConfiguration, _$identity);

  /// Serializes this ConnectionConfiguration to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ConnectionConfiguration;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionConfiguration&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.routeEpoch, _this.routeEpoch) || other.routeEpoch == _this.routeEpoch)&&(identical(other.picksVersion, _this.picksVersion) || other.picksVersion == _this.picksVersion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ConnectionConfiguration;
  return Object.hash(runtimeType,_this.status,_this.inputId,_this.mode,_this.routeEpoch,_this.picksVersion);
}

@override
String toString() {
  final _this = this as ConnectionConfiguration;
  return 'ConnectionConfiguration(status: ${_this.status}, inputId: ${_this.inputId}, mode: ${_this.mode}, routeEpoch: ${_this.routeEpoch}, picksVersion: ${_this.picksVersion})';
}


}

/// @nodoc
abstract mixin class $ConnectionConfigurationCopyWith<$Res>  {
  factory $ConnectionConfigurationCopyWith(ConnectionConfiguration value, $Res Function(ConnectionConfiguration) _then) = _$ConnectionConfigurationCopyWithImpl;
@useResult
$Res call({
 String status, String inputId, String mode, int? routeEpoch, int? picksVersion
});




}
/// @nodoc
class _$ConnectionConfigurationCopyWithImpl<$Res>
    implements $ConnectionConfigurationCopyWith<$Res> {
  _$ConnectionConfigurationCopyWithImpl(this._self, this._then);

  final ConnectionConfiguration _self;
  final $Res Function(ConnectionConfiguration) _then;

/// Create a copy of ConnectionConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? inputId = null,Object? mode = null,Object? routeEpoch = freezed,Object? picksVersion = freezed,}) {
  return _then(ConnectionConfiguration(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,routeEpoch: freezed == routeEpoch ? _self.routeEpoch : routeEpoch // ignore: cast_nullable_to_non_nullable
as int?,picksVersion: freezed == picksVersion ? _self.picksVersion : picksVersion // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConnectionConfiguration].
extension ConnectionConfigurationPatterns on ConnectionConfiguration {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionConfiguration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionConfiguration() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionConfiguration value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionConfiguration():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionConfiguration value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionConfiguration() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status,  String inputId,  String mode,  int? routeEpoch,  int? picksVersion)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionConfiguration() when $default != null:
return $default(_that.status,_that.inputId,_that.mode,_that.routeEpoch,_that.picksVersion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status,  String inputId,  String mode,  int? routeEpoch,  int? picksVersion)  $default,) {final _that = this;
switch (_that) {
case _ConnectionConfiguration():
return $default(_that.status,_that.inputId,_that.mode,_that.routeEpoch,_that.picksVersion);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status,  String inputId,  String mode,  int? routeEpoch,  int? picksVersion)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionConfiguration() when $default != null:
return $default(_that.status,_that.inputId,_that.mode,_that.routeEpoch,_that.picksVersion);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConnectionConfiguration implements ConnectionConfiguration {
  const _ConnectionConfiguration({this.status = 'unknown', this.inputId = '', this.mode = '', this.routeEpoch, this.picksVersion});
  factory _ConnectionConfiguration.fromJson(Map<String, dynamic> json) => _$ConnectionConfigurationFromJson(json);

@override@JsonKey() final  String status;
@override@JsonKey() final  String inputId;
@override@JsonKey() final  String mode;
@override final  int? routeEpoch;
@override final  int? picksVersion;

/// Create a copy of ConnectionConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionConfigurationCopyWith<_ConnectionConfiguration> get copyWith => __$ConnectionConfigurationCopyWithImpl<_ConnectionConfiguration>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConnectionConfigurationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionConfiguration&&(identical(other.status, status) || other.status == status)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.routeEpoch, routeEpoch) || other.routeEpoch == routeEpoch)&&(identical(other.picksVersion, picksVersion) || other.picksVersion == picksVersion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,inputId,mode,routeEpoch,picksVersion);
}

@override
String toString() {
    return 'ConnectionConfiguration(status: $status, inputId: $inputId, mode: $mode, routeEpoch: $routeEpoch, picksVersion: $picksVersion)';
}


}

/// @nodoc
abstract mixin class _$ConnectionConfigurationCopyWith<$Res> implements $ConnectionConfigurationCopyWith<$Res> {
  factory _$ConnectionConfigurationCopyWith(_ConnectionConfiguration value, $Res Function(_ConnectionConfiguration) _then) = __$ConnectionConfigurationCopyWithImpl;
@override @useResult
$Res call({
 String status, String inputId, String mode, int? routeEpoch, int? picksVersion
});




}
/// @nodoc
class __$ConnectionConfigurationCopyWithImpl<$Res>
    implements _$ConnectionConfigurationCopyWith<$Res> {
  __$ConnectionConfigurationCopyWithImpl(this._self, this._then);

  final _ConnectionConfiguration _self;
  final $Res Function(_ConnectionConfiguration) _then;

/// Create a copy of ConnectionConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? inputId = null,Object? mode = null,Object? routeEpoch = freezed,Object? picksVersion = freezed,}) {
  return _then(_ConnectionConfiguration(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,routeEpoch: freezed == routeEpoch ? _self.routeEpoch : routeEpoch // ignore: cast_nullable_to_non_nullable
as int?,picksVersion: freezed == picksVersion ? _self.picksVersion : picksVersion // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$ConnectionObservation {

 int get version; String get runtimeEpoch; ApplicationIdentity get application; ConnectionCapture get capture; ConnectionConfiguration get configuration;
/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionObservationCopyWith<ConnectionObservation> get copyWith => _$ConnectionObservationCopyWithImpl<ConnectionObservation>(this as ConnectionObservation, _$identity);

  /// Serializes this ConnectionObservation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ConnectionObservation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionObservation&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.runtimeEpoch, _this.runtimeEpoch) || other.runtimeEpoch == _this.runtimeEpoch)&&(identical(other.application, _this.application) || other.application == _this.application)&&(identical(other.capture, _this.capture) || other.capture == _this.capture)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ConnectionObservation;
  return Object.hash(runtimeType,_this.version,_this.runtimeEpoch,_this.application,_this.capture,_this.configuration);
}

@override
String toString() {
  final _this = this as ConnectionObservation;
  return 'ConnectionObservation(version: ${_this.version}, runtimeEpoch: ${_this.runtimeEpoch}, application: ${_this.application}, capture: ${_this.capture}, configuration: ${_this.configuration})';
}


}

/// @nodoc
abstract mixin class $ConnectionObservationCopyWith<$Res>  {
  factory $ConnectionObservationCopyWith(ConnectionObservation value, $Res Function(ConnectionObservation) _then) = _$ConnectionObservationCopyWithImpl;
@useResult
$Res call({
 int version, String runtimeEpoch, ApplicationIdentity application, ConnectionCapture capture, ConnectionConfiguration configuration
});


$ApplicationIdentityCopyWith<$Res> get application;$ConnectionCaptureCopyWith<$Res> get capture;$ConnectionConfigurationCopyWith<$Res> get configuration;

}
/// @nodoc
class _$ConnectionObservationCopyWithImpl<$Res>
    implements $ConnectionObservationCopyWith<$Res> {
  _$ConnectionObservationCopyWithImpl(this._self, this._then);

  final ConnectionObservation _self;
  final $Res Function(ConnectionObservation) _then;

/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? runtimeEpoch = null,Object? application = null,Object? capture = null,Object? configuration = null,}) {
  return _then(ConnectionObservation(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,application: null == application ? _self.application : application // ignore: cast_nullable_to_non_nullable
as ApplicationIdentity,capture: null == capture ? _self.capture : capture // ignore: cast_nullable_to_non_nullable
as ConnectionCapture,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConnectionConfiguration,
  ));
}
/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApplicationIdentityCopyWith<$Res> get application {
  
  return $ApplicationIdentityCopyWith<$Res>(_self.application, (value) {
    return _then(_self.copyWith(application: value));
  });
}/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConnectionCaptureCopyWith<$Res> get capture {
  
  return $ConnectionCaptureCopyWith<$Res>(_self.capture, (value) {
    return _then(_self.copyWith(capture: value));
  });
}/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConnectionConfigurationCopyWith<$Res> get configuration {
  
  return $ConnectionConfigurationCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConnectionObservation].
extension ConnectionObservationPatterns on ConnectionObservation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConnectionObservation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConnectionObservation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConnectionObservation value)  $default,){
final _that = this;
switch (_that) {
case _ConnectionObservation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConnectionObservation value)?  $default,){
final _that = this;
switch (_that) {
case _ConnectionObservation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int version,  String runtimeEpoch,  ApplicationIdentity application,  ConnectionCapture capture,  ConnectionConfiguration configuration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConnectionObservation() when $default != null:
return $default(_that.version,_that.runtimeEpoch,_that.application,_that.capture,_that.configuration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int version,  String runtimeEpoch,  ApplicationIdentity application,  ConnectionCapture capture,  ConnectionConfiguration configuration)  $default,) {final _that = this;
switch (_that) {
case _ConnectionObservation():
return $default(_that.version,_that.runtimeEpoch,_that.application,_that.capture,_that.configuration);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int version,  String runtimeEpoch,  ApplicationIdentity application,  ConnectionCapture capture,  ConnectionConfiguration configuration)?  $default,) {final _that = this;
switch (_that) {
case _ConnectionObservation() when $default != null:
return $default(_that.version,_that.runtimeEpoch,_that.application,_that.capture,_that.configuration);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConnectionObservation implements ConnectionObservation {
  const _ConnectionObservation({this.version = 1, this.runtimeEpoch = '', this.application = const ApplicationIdentity(), this.capture = const ConnectionCapture(), this.configuration = const ConnectionConfiguration()});
  factory _ConnectionObservation.fromJson(Map<String, dynamic> json) => _$ConnectionObservationFromJson(json);

@override@JsonKey() final  int version;
@override@JsonKey() final  String runtimeEpoch;
@override@JsonKey() final  ApplicationIdentity application;
@override@JsonKey() final  ConnectionCapture capture;
@override@JsonKey() final  ConnectionConfiguration configuration;

/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionObservationCopyWith<_ConnectionObservation> get copyWith => __$ConnectionObservationCopyWithImpl<_ConnectionObservation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConnectionObservationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConnectionObservation&&(identical(other.version, version) || other.version == version)&&(identical(other.runtimeEpoch, runtimeEpoch) || other.runtimeEpoch == runtimeEpoch)&&(identical(other.application, application) || other.application == application)&&(identical(other.capture, capture) || other.capture == capture)&&(identical(other.configuration, configuration) || other.configuration == configuration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,version,runtimeEpoch,application,capture,configuration);
}

@override
String toString() {
    return 'ConnectionObservation(version: $version, runtimeEpoch: $runtimeEpoch, application: $application, capture: $capture, configuration: $configuration)';
}


}

/// @nodoc
abstract mixin class _$ConnectionObservationCopyWith<$Res> implements $ConnectionObservationCopyWith<$Res> {
  factory _$ConnectionObservationCopyWith(_ConnectionObservation value, $Res Function(_ConnectionObservation) _then) = __$ConnectionObservationCopyWithImpl;
@override @useResult
$Res call({
 int version, String runtimeEpoch, ApplicationIdentity application, ConnectionCapture capture, ConnectionConfiguration configuration
});


@override $ApplicationIdentityCopyWith<$Res> get application;@override $ConnectionCaptureCopyWith<$Res> get capture;@override $ConnectionConfigurationCopyWith<$Res> get configuration;

}
/// @nodoc
class __$ConnectionObservationCopyWithImpl<$Res>
    implements _$ConnectionObservationCopyWith<$Res> {
  __$ConnectionObservationCopyWithImpl(this._self, this._then);

  final _ConnectionObservation _self;
  final $Res Function(_ConnectionObservation) _then;

/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? runtimeEpoch = null,Object? application = null,Object? capture = null,Object? configuration = null,}) {
  return _then(_ConnectionObservation(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,application: null == application ? _self.application : application // ignore: cast_nullable_to_non_nullable
as ApplicationIdentity,capture: null == capture ? _self.capture : capture // ignore: cast_nullable_to_non_nullable
as ConnectionCapture,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConnectionConfiguration,
  ));
}

/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApplicationIdentityCopyWith<$Res> get application {
  
  return $ApplicationIdentityCopyWith<$Res>(_self.application, (value) {
    return _then(_self.copyWith(application: value));
  });
}/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConnectionCaptureCopyWith<$Res> get capture {
  
  return $ConnectionCaptureCopyWith<$Res>(_self.capture, (value) {
    return _then(_self.copyWith(capture: value));
  });
}/// Create a copy of ConnectionObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConnectionConfigurationCopyWith<$Res> get configuration {
  
  return $ConnectionConfigurationCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}
}

// dart format on
