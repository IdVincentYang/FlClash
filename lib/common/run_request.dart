import 'dart:async';

class RunRequestScope {
  static final Object _key = Object();

  static int? get current => Zone.current[_key] as int?;

  static Future<T> run<T>(int requestId, Future<T> Function() action) {
    return runZoned(action, zoneValues: {_key: requestId});
  }
}
