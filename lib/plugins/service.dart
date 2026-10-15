import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final _utf8JsonDecoder = utf8.decoder.fuse(json.decoder);

Object? _decodeUtf8Json(Uint8List data) => _utf8JsonDecoder.convert(data);

Future<Object?> _decodeResponse(Uint8List data) async {
  if (data.length < 51200) {
    return _decodeUtf8Json(data);
  }
  return compute(_decodeUtf8Json, data);
}

abstract mixin class ServiceListener {
  void onServiceEvent(CoreEvent event) {}

  void onRequestState(Map<String, Object?> state) {}
}

class Service {
  static Service? _instance;
  late MethodChannel methodChannel;

  final ObserverList<ServiceListener> _listeners =
      ObserverList<ServiceListener>();

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Service._internal() {
    methodChannel = const MethodChannel('$packageName/service');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestState':
          final state = Map<String, Object?>.unmodifiable(
            Map<String, Object?>.from(
              json.decode(call.arguments as String) as Map,
            ),
          );
          for (final listener in List.of(_listeners)) {
            listener.onRequestState(state);
          }
          break;
        case 'event':
          final data = call.arguments as String? ?? '';
          final methodCall = CoreMethodCall.fromJson(
            Map<String, Object?>.from(json.decode(data) as Map),
          );
          for (final event in coreEventsFromData(methodCall.arguments)) {
            for (final listener in List.of(_listeners)) {
              try {
                listener.onServiceEvent(event);
              } catch (error) {
                commonPrint.log(
                  'Unable to dispatch Android Core event '
                  '${event.type.name}: $error',
                  logLevel: LogLevel.error,
                );
              }
            }
          }
          break;
        default:
          throw MissingPluginException();
      }
    });
  }

  Future<CoreMethodResponse?> invokeMethod(CoreMethodCall call) async {
    final data = await methodChannel.invokeMethod<Uint8List>(
      'invokeMethod',
      json.encode(call),
    );
    if (data == null) {
      return null;
    }
    final dataJson = await _decodeResponse(data);
    return CoreMethodResponse.fromJson(dataJson as Map<String, dynamic>);
  }

  Future<bool> start() async {
    return await methodChannel.invokeMethod<bool>('start') ?? false;
  }

  Future<bool> stop() async {
    return await methodChannel.invokeMethod<bool>('stop') ?? false;
  }

  Future<bool> startPrepared(int requestId) async {
    return await methodChannel.invokeMethod<bool>('start', requestId) ?? false;
  }

  Future<bool> stopPrepared(int requestId) async {
    return await methodChannel.invokeMethod<bool>('stop', requestId) ?? false;
  }

  Future<int> prepareRunIntent({
    required bool running,
    String source = 'ui',
    bool? paused,
  }) async {
    final result = await methodChannel.invokeMethod<int>('prepareRunIntent', {
      'running': running,
      'source': source,
      'paused': ?paused,
    });
    if (result == null) throw StateError('Request state unavailable');
    return result;
  }

  Future<bool> failRunIntent(int requestId) async {
    return await methodChannel.invokeMethod<bool>('failRunIntent', requestId) ??
        false;
  }

  Future<Map<String, Object?>> getRequestState() async {
    final result = await methodChannel.invokeMethod<String>('getRequestState');
    if (result == null) throw StateError('Request state unavailable');
    return Map<String, Object?>.from(json.decode(result) as Map);
  }

  Future<bool> initializeRequestState(
    int revision, {
    bool recovery = false,
  }) async {
    return await methodChannel.invokeMethod<bool>('initializeRequestState', {
          'revision': revision,
          'recovery': recovery,
        }) ??
        false;
  }

  Future<Map<String, Object?>> requestControl(Map<String, Object?> data) async {
    final result = await methodChannel.invokeMethod<String>(
      'requestControl',
      json.encode(data),
    );
    if (result == null) throw StateError('Request control unavailable');
    return Map<String, Object?>.from(json.decode(result) as Map);
  }

  Future<String> init() async {
    return await methodChannel.invokeMethod<String>('init') ?? '';
  }

  Future<String> syncState(SharedState state) async {
    return await methodChannel.invokeMethod<String>(
          'syncState',
          json.encode(state),
        ) ??
        '';
  }

  Future<bool> shutdown() async {
    return await methodChannel.invokeMethod<bool>('shutdown') ?? true;
  }

  Future<DateTime?> getRunTime() async {
    final ms = await methodChannel.invokeMethod<int>('getRunTime') ?? 0;
    if (ms == 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(ServiceListener listener) {
    _listeners.add(listener);
  }

  void removeListener(ServiceListener listener) {
    _listeners.remove(listener);
  }
}

Service? get service => system.isAndroid ? Service() : null;
