// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../ip_quality.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$IpQuality {

 String get ip; IpQualitySource get source; IpType? get type; DateTime? get checkedAt; String? get organization; int? get asn; bool? get isProxy; bool? get isVpn; bool? get isTor; bool? get isCompromised; bool? get isHosting; bool? get isAnonymous; bool? get isScraper; bool get warning; Duration? get retryAfter;
/// Create a copy of IpQuality
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IpQualityCopyWith<IpQuality> get copyWith => _$IpQualityCopyWithImpl<IpQuality>(this as IpQuality, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as IpQuality;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IpQuality&&(identical(other.ip, _this.ip) || other.ip == _this.ip)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.checkedAt, _this.checkedAt) || other.checkedAt == _this.checkedAt)&&(identical(other.organization, _this.organization) || other.organization == _this.organization)&&(identical(other.asn, _this.asn) || other.asn == _this.asn)&&(identical(other.isProxy, _this.isProxy) || other.isProxy == _this.isProxy)&&(identical(other.isVpn, _this.isVpn) || other.isVpn == _this.isVpn)&&(identical(other.isTor, _this.isTor) || other.isTor == _this.isTor)&&(identical(other.isCompromised, _this.isCompromised) || other.isCompromised == _this.isCompromised)&&(identical(other.isHosting, _this.isHosting) || other.isHosting == _this.isHosting)&&(identical(other.isAnonymous, _this.isAnonymous) || other.isAnonymous == _this.isAnonymous)&&(identical(other.isScraper, _this.isScraper) || other.isScraper == _this.isScraper)&&(identical(other.warning, _this.warning) || other.warning == _this.warning)&&(identical(other.retryAfter, _this.retryAfter) || other.retryAfter == _this.retryAfter));
}


@override
int get hashCode {
  final _this = this as IpQuality;
  return Object.hash(runtimeType,_this.ip,_this.source,_this.type,_this.checkedAt,_this.organization,_this.asn,_this.isProxy,_this.isVpn,_this.isTor,_this.isCompromised,_this.isHosting,_this.isAnonymous,_this.isScraper,_this.warning,_this.retryAfter);
}

@override
String toString() {
  final _this = this as IpQuality;
  return 'IpQuality(ip: ${_this.ip}, source: ${_this.source}, type: ${_this.type}, checkedAt: ${_this.checkedAt}, organization: ${_this.organization}, asn: ${_this.asn}, isProxy: ${_this.isProxy}, isVpn: ${_this.isVpn}, isTor: ${_this.isTor}, isCompromised: ${_this.isCompromised}, isHosting: ${_this.isHosting}, isAnonymous: ${_this.isAnonymous}, isScraper: ${_this.isScraper}, warning: ${_this.warning}, retryAfter: ${_this.retryAfter})';
}


}

/// @nodoc
abstract mixin class $IpQualityCopyWith<$Res>  {
  factory $IpQualityCopyWith(IpQuality value, $Res Function(IpQuality) _then) = _$IpQualityCopyWithImpl;
@useResult
$Res call({
 String ip, IpQualitySource source, IpType? type, DateTime? checkedAt, String? organization, int? asn, bool? isProxy, bool? isVpn, bool? isTor, bool? isCompromised, bool? isHosting, bool? isAnonymous, bool? isScraper, bool warning, Duration? retryAfter
});




}
/// @nodoc
class _$IpQualityCopyWithImpl<$Res>
    implements $IpQualityCopyWith<$Res> {
  _$IpQualityCopyWithImpl(this._self, this._then);

  final IpQuality _self;
  final $Res Function(IpQuality) _then;

/// Create a copy of IpQuality
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ip = null,Object? source = null,Object? type = freezed,Object? checkedAt = freezed,Object? organization = freezed,Object? asn = freezed,Object? isProxy = freezed,Object? isVpn = freezed,Object? isTor = freezed,Object? isCompromised = freezed,Object? isHosting = freezed,Object? isAnonymous = freezed,Object? isScraper = freezed,Object? warning = null,Object? retryAfter = freezed,}) {
  return _then(IpQuality(
ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as IpQualitySource,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as IpType?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,organization: freezed == organization ? _self.organization : organization // ignore: cast_nullable_to_non_nullable
as String?,asn: freezed == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as int?,isProxy: freezed == isProxy ? _self.isProxy : isProxy // ignore: cast_nullable_to_non_nullable
as bool?,isVpn: freezed == isVpn ? _self.isVpn : isVpn // ignore: cast_nullable_to_non_nullable
as bool?,isTor: freezed == isTor ? _self.isTor : isTor // ignore: cast_nullable_to_non_nullable
as bool?,isCompromised: freezed == isCompromised ? _self.isCompromised : isCompromised // ignore: cast_nullable_to_non_nullable
as bool?,isHosting: freezed == isHosting ? _self.isHosting : isHosting // ignore: cast_nullable_to_non_nullable
as bool?,isAnonymous: freezed == isAnonymous ? _self.isAnonymous : isAnonymous // ignore: cast_nullable_to_non_nullable
as bool?,isScraper: freezed == isScraper ? _self.isScraper : isScraper // ignore: cast_nullable_to_non_nullable
as bool?,warning: null == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as bool,retryAfter: freezed == retryAfter ? _self.retryAfter : retryAfter // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}

}


/// Adds pattern-matching-related methods to [IpQuality].
extension IpQualityPatterns on IpQuality {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IpQuality value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IpQuality() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IpQuality value)  $default,){
final _that = this;
switch (_that) {
case _IpQuality():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IpQuality value)?  $default,){
final _that = this;
switch (_that) {
case _IpQuality() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ip,  IpQualitySource source,  IpType? type,  DateTime? checkedAt,  String? organization,  int? asn,  bool? isProxy,  bool? isVpn,  bool? isTor,  bool? isCompromised,  bool? isHosting,  bool? isAnonymous,  bool? isScraper,  bool warning,  Duration? retryAfter)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IpQuality() when $default != null:
return $default(_that.ip,_that.source,_that.type,_that.checkedAt,_that.organization,_that.asn,_that.isProxy,_that.isVpn,_that.isTor,_that.isCompromised,_that.isHosting,_that.isAnonymous,_that.isScraper,_that.warning,_that.retryAfter);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ip,  IpQualitySource source,  IpType? type,  DateTime? checkedAt,  String? organization,  int? asn,  bool? isProxy,  bool? isVpn,  bool? isTor,  bool? isCompromised,  bool? isHosting,  bool? isAnonymous,  bool? isScraper,  bool warning,  Duration? retryAfter)  $default,) {final _that = this;
switch (_that) {
case _IpQuality():
return $default(_that.ip,_that.source,_that.type,_that.checkedAt,_that.organization,_that.asn,_that.isProxy,_that.isVpn,_that.isTor,_that.isCompromised,_that.isHosting,_that.isAnonymous,_that.isScraper,_that.warning,_that.retryAfter);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ip,  IpQualitySource source,  IpType? type,  DateTime? checkedAt,  String? organization,  int? asn,  bool? isProxy,  bool? isVpn,  bool? isTor,  bool? isCompromised,  bool? isHosting,  bool? isAnonymous,  bool? isScraper,  bool warning,  Duration? retryAfter)?  $default,) {final _that = this;
switch (_that) {
case _IpQuality() when $default != null:
return $default(_that.ip,_that.source,_that.type,_that.checkedAt,_that.organization,_that.asn,_that.isProxy,_that.isVpn,_that.isTor,_that.isCompromised,_that.isHosting,_that.isAnonymous,_that.isScraper,_that.warning,_that.retryAfter);case _:
  return null;

}
}

}

/// @nodoc


class _IpQuality implements IpQuality {
  const _IpQuality({required this.ip, required this.source, this.type, this.checkedAt, this.organization, this.asn, this.isProxy, this.isVpn, this.isTor, this.isCompromised, this.isHosting, this.isAnonymous, this.isScraper, this.warning = false, this.retryAfter});
  

@override final  String ip;
@override final  IpQualitySource source;
@override final  IpType? type;
@override final  DateTime? checkedAt;
@override final  String? organization;
@override final  int? asn;
@override final  bool? isProxy;
@override final  bool? isVpn;
@override final  bool? isTor;
@override final  bool? isCompromised;
@override final  bool? isHosting;
@override final  bool? isAnonymous;
@override final  bool? isScraper;
@override@JsonKey() final  bool warning;
@override final  Duration? retryAfter;

/// Create a copy of IpQuality
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IpQualityCopyWith<_IpQuality> get copyWith => __$IpQualityCopyWithImpl<_IpQuality>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _IpQuality&&(identical(other.ip, ip) || other.ip == ip)&&(identical(other.source, source) || other.source == source)&&(identical(other.type, type) || other.type == type)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.organization, organization) || other.organization == organization)&&(identical(other.asn, asn) || other.asn == asn)&&(identical(other.isProxy, isProxy) || other.isProxy == isProxy)&&(identical(other.isVpn, isVpn) || other.isVpn == isVpn)&&(identical(other.isTor, isTor) || other.isTor == isTor)&&(identical(other.isCompromised, isCompromised) || other.isCompromised == isCompromised)&&(identical(other.isHosting, isHosting) || other.isHosting == isHosting)&&(identical(other.isAnonymous, isAnonymous) || other.isAnonymous == isAnonymous)&&(identical(other.isScraper, isScraper) || other.isScraper == isScraper)&&(identical(other.warning, warning) || other.warning == warning)&&(identical(other.retryAfter, retryAfter) || other.retryAfter == retryAfter));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ip,source,type,checkedAt,organization,asn,isProxy,isVpn,isTor,isCompromised,isHosting,isAnonymous,isScraper,warning,retryAfter);
}

@override
String toString() {
    return 'IpQuality(ip: $ip, source: $source, type: $type, checkedAt: $checkedAt, organization: $organization, asn: $asn, isProxy: $isProxy, isVpn: $isVpn, isTor: $isTor, isCompromised: $isCompromised, isHosting: $isHosting, isAnonymous: $isAnonymous, isScraper: $isScraper, warning: $warning, retryAfter: $retryAfter)';
}


}

/// @nodoc
abstract mixin class _$IpQualityCopyWith<$Res> implements $IpQualityCopyWith<$Res> {
  factory _$IpQualityCopyWith(_IpQuality value, $Res Function(_IpQuality) _then) = __$IpQualityCopyWithImpl;
@override @useResult
$Res call({
 String ip, IpQualitySource source, IpType? type, DateTime? checkedAt, String? organization, int? asn, bool? isProxy, bool? isVpn, bool? isTor, bool? isCompromised, bool? isHosting, bool? isAnonymous, bool? isScraper, bool warning, Duration? retryAfter
});




}
/// @nodoc
class __$IpQualityCopyWithImpl<$Res>
    implements _$IpQualityCopyWith<$Res> {
  __$IpQualityCopyWithImpl(this._self, this._then);

  final _IpQuality _self;
  final $Res Function(_IpQuality) _then;

/// Create a copy of IpQuality
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ip = null,Object? source = null,Object? type = freezed,Object? checkedAt = freezed,Object? organization = freezed,Object? asn = freezed,Object? isProxy = freezed,Object? isVpn = freezed,Object? isTor = freezed,Object? isCompromised = freezed,Object? isHosting = freezed,Object? isAnonymous = freezed,Object? isScraper = freezed,Object? warning = null,Object? retryAfter = freezed,}) {
  return _then(_IpQuality(
ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as IpQualitySource,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as IpType?,checkedAt: freezed == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,organization: freezed == organization ? _self.organization : organization // ignore: cast_nullable_to_non_nullable
as String?,asn: freezed == asn ? _self.asn : asn // ignore: cast_nullable_to_non_nullable
as int?,isProxy: freezed == isProxy ? _self.isProxy : isProxy // ignore: cast_nullable_to_non_nullable
as bool?,isVpn: freezed == isVpn ? _self.isVpn : isVpn // ignore: cast_nullable_to_non_nullable
as bool?,isTor: freezed == isTor ? _self.isTor : isTor // ignore: cast_nullable_to_non_nullable
as bool?,isCompromised: freezed == isCompromised ? _self.isCompromised : isCompromised // ignore: cast_nullable_to_non_nullable
as bool?,isHosting: freezed == isHosting ? _self.isHosting : isHosting // ignore: cast_nullable_to_non_nullable
as bool?,isAnonymous: freezed == isAnonymous ? _self.isAnonymous : isAnonymous // ignore: cast_nullable_to_non_nullable
as bool?,isScraper: freezed == isScraper ? _self.isScraper : isScraper // ignore: cast_nullable_to_non_nullable
as bool?,warning: null == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as bool,retryAfter: freezed == retryAfter ? _self.retryAfter : retryAfter // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}


}

// dart format on
