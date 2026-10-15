import 'dart:async';
import 'dart:io' as io;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

typedef DAVClientFactory = DAVClient Function(DAVProps props);

class DAVClient {
  DAVClient(this.props) : fileName = props.fileName;
  final DAVProps props;
  final String fileName;
  final _sessions = <RequestSession, String>{};
  int _pingGeneration = 0;
  bool _closed = false;

  @protected
  Request get requestClient => request;

  DAVTransport _transport(RequestSession session) => DAVTransport(
    uri: props.uri,
    user: props.user,
    password: props.password,
    dio: session.dio,
  );

  Future<T> operation<T>(
    String kind,
    Future<T> Function(RequestSession session) action,
  ) async {
    if (_closed) throw const RequestUnavailable('request_cancelled');
    final pingGeneration = _pingGeneration;
    final session = await requestClient.begin(
      key: 'dav:$kind',
      url: props.uri,
      mode: props.requestMode,
      proxy: props.requestProxy,
      sourceIsCurrent: () async => requestClient.isDAVCurrent(props),
    );
    if (_closed || kind == 'ping' && pingGeneration != _pingGeneration) {
      session.close();
      throw const RequestUnavailable('request_cancelled');
    }
    _sessions[session] = kind;
    try {
      return await session.run(() => action(session));
    } finally {
      session.close();
      _sessions.remove(session);
    }
  }

  void close() {
    _closed = true;
    _pingGeneration++;
    for (final session in List.of(_sessions.keys)) {
      session.close();
    }
  }

  void cancelPing() {
    _pingGeneration++;
    for (final entry in _sessions.entries.toList()) {
      if (entry.value == 'ping') entry.key.close();
    }
  }

  Future<bool> ping() async {
    try {
      return await operation('ping', (session) async {
        await _transport(session).options('/');
        await session.check();
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  String get root => '/$appName';
  String get backupFile => '$root/$fileName';

  Future<void> upload(String localPath) async {
    final current = RequestSession.current;
    if (current == null) return operation('backup', (_) => upload(localPath));
    final transport = _transport(current);
    await transport.mkcol(root);
    await current.check();
    await transport.put(backupFile, await io.File(localPath).readAsBytes());
    await current.check();
  }

  Future<void> download(String localPath) async {
    final current = RequestSession.current;
    if (current == null) {
      return operation('restore', (_) => download(localPath));
    }
    final bytes = await _transport(current).get(backupFile);
    await current.check();
    await io.File(localPath).safeWriteAsBytes(bytes);
  }
}

class DAVConnectionController extends ValueNotifier<bool?> {
  DAVConnectionController({DAVClientFactory? createClient})
    : _createClient = createClient ?? DAVClient.new,
      super(null);

  final DAVClientFactory _createClient;

  DAVProps? _lastProps;
  bool _hasUpdated = false;
  int _requestId = 0;
  bool _disposed = false;
  bool _visible = true;

  DAVClient? client;

  Future<void> update(DAVProps? props) async {
    if (_disposed || _hasUpdated && props == _lastProps) return;
    final nextClient = props == null ? null : _createClient(props);
    client?.close();
    client = nextClient;

    final rawProps = props?.copyWith(fileName: '');
    final rawLastProps = _lastProps?.copyWith(fileName: '');
    final isSameCredentials = _hasUpdated && rawProps == rawLastProps;
    _lastProps = props;
    _hasUpdated = true;
    if (!_visible) return;
    if (isSameCredentials) {
      return;
    }

    await _ping();
  }

  Future<void> _ping() async {
    final requestId = ++_requestId;
    value = null;
    final result = await client?.ping() ?? false;
    if (!_disposed && requestId == _requestId) {
      value = result;
    }
  }

  Future<void> setVisible(bool visible) async {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    if (!visible) {
      _requestId++;
      client?.cancelPing();
      value = null;
    } else {
      await _ping();
    }
  }

  @override
  void dispose() {
    client?.close();
    _disposed = true;
    _requestId++;
    super.dispose();
  }
}
