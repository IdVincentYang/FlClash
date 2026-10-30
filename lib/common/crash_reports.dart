import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../plugins/app.dart';

class ErrorReports {
  ErrorReports({
    bool? supported,
    Future<Map<String, Object?>> Function(Map<String, Object?>)? save,
    Duration timeout = const Duration(seconds: 2),
  }) : _supported = supported ?? Platform.isAndroid,
       _save = save ?? _platformSave,
       _timeout = timeout;

  final bool _supported;
  final Future<Map<String, Object?>> Function(Map<String, Object?>) _save;
  final Duration _timeout;
  bool _formatting = false;
  int _pending = 0;
  String _origin = 'flutter';

  static Future<Map<String, Object?>> _platformSave(
    Map<String, Object?> value,
  ) async =>
      await app?.captureErrorReport(value) ?? const {'status': 'unsupported'};

  void install(FlutterExceptionHandler delegate) {
    FlutterError.onError = (details) {
      unawaited(capture(_origin, details.exception, details.stack));
      delegate(details);
    };
  }

  void reportZone(Object error, StackTrace stack) {
    final previous = _origin;
    _origin = 'zone';
    try {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    } finally {
      _origin = previous;
    }
  }

  void startupError(Object error, StackTrace stack, VoidCallback present) {
    unawaited(capture('startup', error, stack));
    present();
  }

  Future<String> capture(String source, Object error, StackTrace? stack) async {
    if (!_supported) return 'unsupported';
    if (_formatting || _pending >= 4) return 'busy';
    if (!const ['flutter', 'zone', 'startup'].contains(source)) {
      return 'invalid';
    }
    late final String raw;
    late final bool truncated;
    _formatting = true;
    try {
      final message = error.toString();
      final trace = stack?.toString() ?? '';
      final text = '${message.take(32768)}\n${trace.take(32768)}';
      final bytes = utf8.encode(text);
      truncated =
          message.length > 32768 ||
          trace.length > 32768 ||
          bytes.length > 65532;
      raw = utf8.decode(bytes.take(65532).toList(), allowMalformed: true);
    } catch (_) {
      return 'format_failed';
    } finally {
      _formatting = false;
    }
    _pending++;
    try {
      final reply = await _save({
        'source': source,
        'raw': raw,
        'truncated': truncated,
      }).timeout(_timeout);
      return reply['status'] is String ? reply['status']! as String : 'io';
    } on TimeoutException {
      return 'deadline';
    } catch (_) {
      return 'io';
    } finally {
      _pending--;
    }
  }
}

extension on String {
  String take(int limit) => length <= limit ? this : substring(0, limit);
}

final errorReports = ErrorReports();
