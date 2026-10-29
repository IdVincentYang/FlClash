import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

final dataMutations = SerialTaskScheduler();

class RequestUnavailable implements Exception {
  const RequestUnavailable(this.code);
  final String code;
  @override
  String toString() => switch (code) {
    'profile_download_timeout' =>
      currentAppLocalizations.profileDownloadTimeout,
    'profile_download_too_large' =>
      currentAppLocalizations.profileDownloadTooLarge,
    'profile_download_failed' => currentAppLocalizations.profileDownloadFailed,
    'profile_invalid' => currentAppLocalizations.profileInvalidBody,
    'profile_refresh_failed' ||
    'profile_publish_failed' ||
    'profile_cleanup_failed' => currentAppLocalizations.profileRefreshFailed,
    'request_partial_commit' => currentAppLocalizations.requestPartialCommit,
    'profile_saved_recovery_required' =>
      currentAppLocalizations.profileSavedRecoveryRequired,
    'managed_maintenance_target_required' =>
      currentAppLocalizations.policyMaintenanceRequired,
    'managed_policy_edit_required' =>
      currentAppLocalizations.policyManagedEditRequired,
    'managed_policy_android_required' =>
      currentAppLocalizations.policyAndroidRequired,
    _ => currentAppLocalizations.requestRouteUnavailable,
  };
}

class _SessionHttpOverrides extends HttpOverrides {}

class RequestSource {
  RequestSource._(
    this.owner,
    this.key,
    this.dataset,
    this.revision,
    this.client,
    Map<String, Object?> snapshot,
  ) : snapshot = Map.unmodifiable({
        ...snapshot,
        if (snapshot['state'] is Map)
          'state': Map<String, Object?>.unmodifiable(
            Map<String, Object?>.from(snapshot['state'] as Map),
          ),
      });
  final Request owner;
  final String key;
  final int dataset, revision;
  final String? client;
  final Map<String, Object?> snapshot;
}

class RequestSession {
  RequestSession._(
    this.owner,
    this.key,
    this.id,
    this.client,
    this.state,
    this.dio, {
    this.closeClient,
    this.generation = const {},
    this.ownsDio = true,
    required this.cancellationGeneration,
  });

  final Request owner;
  final String key;
  final String? id;
  final String? client;
  final Map<String, Object?> state;
  final Map<String, Object?> generation;
  final Dio dio;
  final bool ownsDio;
  final int cancellationGeneration;
  final void Function()? closeClient;
  final cancelToken = CancelToken();
  bool _closed = false;
  bool _granted = false;
  bool get committed => _granted;
  bool get isActive => !_closed && !cancelToken.isCancelled;
  static final Object _zoneKey = Object();
  static RequestSession? get current =>
      Zone.current[_zoneKey] as RequestSession?;

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void ensureActive() {
    if (_closed) throw const RequestUnavailable('request_cancelled');
  }

  Future<void> check() async {
    ensureActive();
    if (id != null) {
      final result = await owner._control({
        'action': 'check',
        'id': id,
        'client': client,
      });
      if (result['ok'] != true) {
        close();
        throw const RequestUnavailable('request_cancelled');
      }
    }
    ensureActive();
  }

  Future<bool> lifecycleCurrent({bool sourceInvalidated = false}) async {
    if (id == null) return true;
    final snapshot = await owner._control({
      'action': 'inspect',
      'client': client,
      'key': key,
    });
    final current = Map<String, Object?>.from(snapshot['state'] as Map);
    return current['processEpoch'] == state['processEpoch'] &&
        current['revision'] == state['revision'] &&
        current['phase'] == 'started' &&
        snapshot['phase'] == 'ready' &&
        snapshot['owner'] == generation['owner'] &&
        snapshot['dataset'] == generation['dataset'] &&
        snapshot['operation'] == generation['operation'] &&
        snapshot['sourceRevision'] ==
            (generation['sourceRevision'] as int) + (sourceInvalidated ? 1 : 0);
  }

  Future<T> commit<T>(Future<T> Function() action) =>
      dataMutations.run(() async {
        await check();
        if (_granted) throw StateError('Request result already committed');
        if (id != null) {
          final result = await owner._commitControl({
            'action': 'grant',
            'id': id,
            'client': client,
          }, check);
          if (result['ok'] != true) {
            throw const RequestUnavailable('request_cancelled');
          }
        }
        _granted = true;
        return owner._runReceipt(id, () => run(action));
      });

  void close() {
    if (_closed) return;
    _closed = true;
    cancelToken.cancel('request_cancelled');
    if (ownsDio) dio.close(force: true);
    closeClient?.call();
    owner._sessions.remove(this);
    if (id != null) {
      unawaited(
        owner
            ._control({'action': 'cancel', 'id': id, 'client': client})
            .catchError((Object _) => <String, Object?>{}),
      );
    }
  }
}

class _LocalReceipt {
  _LocalReceipt(this.owner, this.id);
  final Request owner;
  final String? id;
  bool active = true;
  bool applicationInputsInvalidated = false;
}

class Request with ServiceListener {
  Request() : _native = null, _android = null;
  Request.scoped({required Service native, required bool isAndroid})
    : _native = native,
      _android = isAndroid;
  final Service? _native;
  final bool? _android;
  bool get _isAndroid => _android ?? system.isAndroid;
  Service? get _service => _native ?? service;

  final _sessions = <RequestSession>{};
  final _cancellations = <String, int>{};
  int _datasetRevision = 0;
  final _legacyDio = Dio(BaseOptions(headers: {'User-Agent': browserUa}));
  ProviderContainer? _container;
  Future<void>? _attachment;
  String? _client;
  Map<String, Object?>? _nativeState;
  String? userAgent;
  RequestSession? _versionSession;
  Map<String, dynamic>? _versionData;
  bool partialCommit = false;
  static final Object _receiptKey = Object();

  _LocalReceipt? get _receipt {
    final receipt = Zone.current[_receiptKey];
    return receipt is _LocalReceipt &&
            identical(receipt.owner, this) &&
            receipt.active
        ? receipt
        : null;
  }

  bool get applicationInputsInvalidated =>
      _receipt?.applicationInputsInvalidated == true;

  bool get hasNativeClient => _isAndroid && _client != null;
  bool get isAttached => _container != null;

  Future<Map<String, Object?>?> captureNativeRunState() async {
    await _attachment;
    if (!hasNativeClient) return null;
    return Map.unmodifiable(await _service!.getRequestState());
  }

  Future<T> _runReceipt<T>(String? id, Future<T> Function() action) async {
    File? marker;
    final receipt = _LocalReceipt(this, id);
    try {
      return await runZoned(() async {
        try {
          marker = _isAndroid && id != null
              ? File('${await appPath.homeDirPath}/request-recovery-required')
              : null;
          if (marker != null && !partialCommit) {
            final staged = File('${marker!.path}.pending');
            try {
              await staged.writeAsString('pending local commit', flush: true);
              await staged.rename(marker!.path);
            } finally {
              await staged.safeDelete();
            }
          }
          return await action();
        } finally {
          if (id != null) {
            try {
              await _control({
                'action': 'complete',
                'id': id,
                'client': _client,
              });
            } catch (_) {
              try {
                await markPartialCommit();
              } catch (_) {}
              throw const RequestUnavailable('request_partial_commit');
            }
          }
        }
      }, zoneValues: {_receiptKey: receipt});
    } finally {
      receipt.active = false;
      if (!partialCommit) await marker?.safeDelete();
    }
  }

  Future<void> markPartialCommit() async {
    await markRecoveryRequired();
    await invalidateDataset();
  }

  Future<void> markRecoveryRequired() async {
    partialCommit = true;
    await File(
      '${await appPath.homeDirPath}/request-recovery-required',
    ).writeAsString('recovery required', flush: true);
  }

  Future<void> clearPartialCommit() async {
    await File(
      '${await appPath.homeDirPath}/request-recovery-required',
    ).safeDelete();
    partialCommit = false;
  }

  Dio get dio =>
      RequestSession.current?.dio ??
      (_isAndroid
          ? throw const RequestUnavailable('request_scope_required')
          : _legacyDio);

  void attach(ProviderContainer container) {
    if (identical(_container, container) && _attachment != null) return;
    _service?.removeListener(this);
    _container = container;
    _service?.addListener(this);
    _attachment = _attachNative();
  }

  Future<void> _attachNative() async {
    if (!_isAndroid) return;
    final result = await _control({'action': 'attach'});
    _client = result['client'] as String?;
    partialCommit = await File(
      '${await appPath.homeDirPath}/request-recovery-required',
    ).exists();
    if (_client == null) {
      throw const RequestUnavailable('request_state_unavailable');
    }
  }

  bool isDAVCurrent(DAVProps props) =>
      _container?.read(davSettingProvider) == props;

  Future<void> ready() async {
    await _attachment;
    if (!_isAndroid) return;
    for (var attempt = 0; ; attempt++) {
      final result = await _control({'action': 'ready', 'client': _client});
      if (result['ready'] != false) return;
      if (attempt >= 200) {
        partialCommit = true;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<Map<String, Object?>> _control(Map<String, Object?> value) async {
    final result = await _service!.requestControl(value);
    if (result['error'] case final String error) {
      throw RequestUnavailable(error);
    }
    return result;
  }

  Future<Map<String, Object?>> _commitControl(
    Map<String, Object?> value, [
    Future<void> Function()? check,
  ]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      try {
        return await _control(value);
      } on RequestUnavailable catch (error) {
        if (error.code != 'request_commit_busy' ||
            DateTime.now().isAfter(deadline)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await check?.call();
      }
    }
  }

  @override
  void onRequestState(Map<String, Object?> state) {
    final previous = _nativeState;
    if (previous != null &&
        previous['processEpoch'] == state['processEpoch'] &&
        (state['revision'] as int) <= (previous['revision'] as int)) {
      return;
    }
    _nativeState = state;
    final container = _container;
    if (state['phase'] == 'started' &&
        previous?['phase'] != 'started' &&
        container != null &&
        container.read(initProvider)) {
      unawaited(
        container.read(profilesActionProvider.notifier).autoUpdateProfiles(),
      );
    }
    for (final session in List.of(_sessions)) {
      if (session.state['processEpoch'] != state['processEpoch'] ||
          session.state['revision'] != state['revision']) {
        session.close();
      }
    }
  }

  Future<T> mutate<T>(Future<T> Function() action) =>
      dataMutations.run(() => localCommit(action));

  Future<T> localCommit<T>(Future<T> Function() action) async {
    await _attachment;
    if (!_isAndroid || _client == null) return _runReceipt(null, action);
    final result = await _commitControl({'action': 'lock', 'client': _client});
    return _runReceipt(result['id'] as String, action);
  }

  void cancelKey(String key) {
    _cancellations[key] = (_cancellations[key] ?? 0) + 1;
    for (final session in List.of(_sessions)) {
      if (session.key == key) session.close();
    }
  }

  Future<void> invalidate(String key) async {
    cancelKey(key);
    for (final session in List.of(_sessions)) {
      if (session.key == key ||
          key == 'dav' && session.key.startsWith('dav:')) {
        session.close();
      }
    }
    await _attachment;
    if (_isAndroid && _client != null && key == 'dav') {
      for (final target in ['dav:ping', 'dav:backup', 'dav:restore']) {
        await _control({
          'action': 'invalidate',
          'client': _client,
          'key': target,
        });
      }
    } else if (_isAndroid && _client != null) {
      await _control({'action': 'invalidate', 'client': _client, 'key': key});
    }
    if (key == 'application-config') {
      _receipt?.applicationInputsInvalidated = true;
    }
  }

  Future<void> invalidateDataset({String? committingId}) async {
    _datasetRevision++;
    committingId ??= _receipt?.id;
    for (final session in List.of(_sessions)) {
      session.close();
    }
    await _attachment;
    if (_isAndroid && _client != null) {
      await _control({'action': 'invalidateDataset', 'client': _client});
      for (var attempt = 0; ; attempt++) {
        final result = await _control({
          'action': 'inspect',
          'client': _client,
          'id': committingId,
        });
        if (result['commits'] == 0) break;
        if (attempt >= 200) {
          throw const RequestUnavailable('request_commit_busy');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    _receipt?.applicationInputsInvalidated = true;
  }

  Future<void> detach() async {
    _datasetRevision++;
    for (final session in List.of(_sessions)) {
      session.close();
    }
    if (_isAndroid && _client != null) {
      await _control({'action': 'detach', 'client': _client});
    }
  }

  Future<RequestSource> captureSource(String key) async {
    await _attachment;
    final snapshot = _isAndroid
        ? await _control({'action': 'inspect', 'client': _client, 'key': key})
        : <String, Object?>{};
    return RequestSource._(
      this,
      key,
      _datasetRevision,
      _cancellations[key] ?? 0,
      _client,
      snapshot,
    );
  }

  bool _localSourceCurrent(RequestSource source) =>
      identical(source.owner, this) &&
      source.dataset == _datasetRevision &&
      source.revision == (_cancellations[source.key] ?? 0) &&
      source.client == _client;

  bool _nativeSourceCurrent(
    RequestSource source,
    Map<String, Object?> snapshot,
  ) {
    final before = source.snapshot['state'] as Map?;
    final current = snapshot['state'] as Map?;
    return before?['processEpoch'] == current?['processEpoch'] &&
        before?['revision'] == current?['revision'] &&
        [
          'owner',
          'dataset',
          'sourceRevision',
          'operation',
        ].every((field) => source.snapshot[field] == snapshot[field]);
  }

  Future<bool> configSourceCurrent(RequestSource source) async {
    if (!_localSourceCurrent(source)) return false;
    if (!_isAndroid) return true;
    final current = await _control({
      'action': 'inspect',
      'client': _client,
      'key': source.key,
    });
    return _localSourceCurrent(source) &&
        current['dataset'] == source.snapshot['dataset'] &&
        current['sourceRevision'] == source.snapshot['sourceRevision'];
  }

  Future<bool> sourceCurrent(RequestSource source) async {
    if (!_localSourceCurrent(source)) return false;
    if (!_isAndroid) return true;
    final snapshot = await _control({
      'action': 'inspect',
      'client': _client,
      'key': source.key,
    });
    return _localSourceCurrent(source) &&
        _nativeSourceCurrent(source, snapshot);
  }

  bool _queuedLocalCurrent(RequestSource source, int generation) =>
      identical(source.owner, this) &&
      source.client == _client &&
      source.dataset == _datasetRevision &&
      (_cancellations[source.key] ?? 0) == generation;

  Future<bool> materialSessionCurrent(
    RequestSession session,
    RequestSource source,
  ) async {
    if (!_localSourceCurrent(source) ||
        session.cancellationGeneration != source.revision ||
        session.key != source.key) {
      return false;
    }
    if (_isAndroid &&
        (session.generation['dataset'] != source.snapshot['dataset'] ||
            session.generation['sourceRevision'] !=
                source.snapshot['sourceRevision'])) {
      return false;
    }
    try {
      await session.check();
      return _localSourceCurrent(source);
    } catch (_) {
      return false;
    }
  }

  Future<RequestSession> begin({
    required String key,
    required String url,
    RequestMode mode = RequestMode.auto,
    String? proxy,
    bool automatic = false,
    bool diagnostic = false,
    bool allowBootstrap = false,
    bool bootstrapIfUnconfigured = false,
    String? label,
    Future<bool> Function()? sourceIsCurrent,
    String? explicitTarget,
    RequestSource? expectedSource,
    RequestSource? queuedMaterialSource,
  }) async {
    if (expectedSource != null && queuedMaterialSource != null) {
      throw ArgumentError('Conflicting request source constraints');
    }
    if (queuedMaterialSource != null &&
        (queuedMaterialSource.key != key ||
            !_localSourceCurrent(queuedMaterialSource))) {
      throw const RequestUnavailable('request_cancelled');
    }
    if (expectedSource != null &&
        (expectedSource.key != key || !_localSourceCurrent(expectedSource))) {
      throw const RequestUnavailable('request_cancelled');
    }
    final generation = await dataMutations.run(() async {
      if (queuedMaterialSource != null &&
              !_localSourceCurrent(queuedMaterialSource) ||
          expectedSource != null && !_localSourceCurrent(expectedSource) ||
          sourceIsCurrent != null && !await sourceIsCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
      cancelKey(key);
      return _cancellations[key] ?? 0;
    });
    await _attachment;
    if (partialCommit) throw const RequestUnavailable('request_partial_commit');
    final container = _container;
    if (!_isAndroid) {
      await dataMutations.run(() async {
        if ((_cancellations[key] ?? 0) != generation ||
            queuedMaterialSource != null &&
                !_queuedLocalCurrent(queuedMaterialSource, generation) ||
            expectedSource != null &&
                expectedSource.dataset != _datasetRevision ||
            sourceIsCurrent != null && !await sourceIsCurrent()) {
          throw const RequestUnavailable('request_cancelled');
        }
      });
      final session = _makeSession(
        key,
        null,
        const {},
        null,
        diagnostic: diagnostic,
      );
      _sessions.add(session);
      return session;
    }
    if (container == null) {
      throw const RequestUnavailable('request_not_attached');
    }
    final snapshot = await _control({
      'action': 'inspect',
      'client': _client,
      'key': key,
    });
    if (expectedSource != null &&
        !_nativeSourceCurrent(expectedSource, snapshot)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final state = Map<String, Object?>.from(
      (expectedSource?.snapshot['state'] ?? snapshot['state']) as Map,
    );
    onRequestState(state);
    final maintenance = [
      'initializedIdle',
      'userStop',
      'excludedSsid',
    ].contains(state['reason']);
    final running =
        state['intentRunning'] == true &&
        state['phase'] == 'started' &&
        state['paused'] != true &&
        snapshot['phase'] == 'ready';
    final managed = (snapshot['policyVersion'] as num? ?? 0) != 0;
    final defaultProxy = snapshot['maintenanceProxy'] as String? ?? '';
    if (mode == RequestMode.proxy &&
        managed &&
        (proxy == null || proxy.isEmpty || proxy == 'GLOBAL') &&
        defaultProxy.isEmpty) {
      throw const RequestUnavailable('managed_maintenance_target_required');
    }
    String target;
    String kind = 'maintenance';
    String? permit;
    if (explicitTarget != null) {
      target = explicitTarget;
    } else if (!(managed && mode == RequestMode.proxy) &&
        (allowBootstrap ||
            bootstrapIfUnconfigured && snapshot['hasProxy'] == false) &&
        !running &&
        !automatic) {
      final accepted = await dialogs.showMessage(
        title: currentAppLocalizations.requestDirectRecoveryTitle,
        message: TextSpan(
          text:
              '${label ?? currentAppLocalizations.requestMode}\n${currentAppLocalizations.requestDirectRecoveryMessage(Uri.parse(url).host)}',
        ),
      );
      if (accepted != true) {
        throw const RequestUnavailable('bootstrap_required');
      }
      final permission = await _control({
        'action': 'permit',
        'client': _client,
        'key': key,
        'url': url,
        'dataset': snapshot['dataset'],
        'sourceRevision': snapshot['sourceRevision'],
        'expectedState': {
          'epoch': state['processEpoch'],
          'revision': state['revision'],
        },
      });
      permit = permission['permit'] as String;
      target = 'DIRECT';
      kind = 'bootstrap';
    } else if (mode == RequestMode.direct) {
      target = 'DIRECT';
    } else if (mode == RequestMode.proxy) {
      target = proxy == null || proxy.isEmpty || proxy == 'GLOBAL'
          ? (managed ? defaultProxy : 'GLOBAL')
          : proxy;
    } else if (running) {
      target = '';
    } else if (maintenance && !automatic) {
      target = 'DIRECT';
    } else {
      throw const RequestUnavailable('request_blocked');
    }
    final auth = container
        .read(networkSettingProvider)
        .authentication
        .credentials;
    final credential = auth.isEmpty ? '' : auth.first;
    final separator = credential.indexOf(':');
    final result = await dataMutations.run(() async {
      if ((_cancellations[key] ?? 0) != generation ||
          expectedSource != null &&
              expectedSource.dataset != _datasetRevision) {
        throw const RequestUnavailable('request_cancelled');
      }
      if (queuedMaterialSource != null) {
        final current = await _control({
          'action': 'inspect',
          'client': _client,
          'key': key,
        });
        if (!_queuedLocalCurrent(queuedMaterialSource, generation) ||
            current['dataset'] != queuedMaterialSource.snapshot['dataset'] ||
            current['sourceRevision'] !=
                queuedMaterialSource.snapshot['sourceRevision']) {
          throw const RequestUnavailable('request_cancelled');
        }
      }
      if (sourceIsCurrent != null && !await sourceIsCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
      if (expectedSource != null) {
        final current = await _control({
          'action': 'inspect',
          'client': _client,
          'key': key,
        });
        if (!_nativeSourceCurrent(expectedSource, current)) {
          throw const RequestUnavailable('request_cancelled');
        }
      }
      return _control({
        'action': 'begin',
        'client': _client,
        'kind': kind,
        'trigger': automatic ? 'automatic' : 'manual',
        'key': key,
        'url': url,
        'mode': kind == 'bootstrap' ? 'direct' : mode.name,
        'proxy': target,
        'permit': ?permit,
        'owner': snapshot['owner'],
        'dataset': snapshot['dataset'],
        'sourceRevision': snapshot['sourceRevision'],
        'expectedState': {
          'epoch': state['processEpoch'],
          'revision': state['revision'],
        },
        'user': separator < 0 ? credential : credential.substring(0, separator),
        'password': separator < 0 ? '' : credential.substring(separator + 1),
      });
    });
    final session = _makeSession(
      key,
      result['id'] as String,
      state,
      result,
      diagnostic: diagnostic,
    );
    if ((_cancellations[key] ?? 0) != generation) {
      session.close();
      throw const RequestUnavailable('request_cancelled');
    }
    _sessions.add(session);
    return session;
  }

  Future<bool> recoverMissingGeo(CoreController core) async {
    if (!_isAndroid) return false;
    final result = await _control({'action': 'inspect', 'client': _client});
    final raw = result['bootstrap'];
    if (raw is! Map) return false;
    final name = raw['Name'] as String;
    final url = raw['URL'] as String;
    final session = await begin(
      key: 'geo:$name',
      url: url,
      allowBootstrap: true,
      label: name,
    );
    try {
      final message = await session.run(() => core.updateGeoData(name));
      if (message.isNotEmpty) throw MessageException(message);
      await session.check();
      return true;
    } finally {
      session.close();
    }
  }

  RequestSession _makeSession(
    String key,
    String? id,
    Map<String, Object?> state,
    Map<String, Object?>? grant, {
    bool diagnostic = false,
  }) {
    final container = _container;
    if (container == null) {
      if (diagnostic) throw const RequestUnavailable('request_not_attached');
      return RequestSession._(
        this,
        key,
        id,
        _client,
        state,
        _legacyDio,
        ownsDio: false,
        cancellationGeneration: _cancellations[key] ?? 0,
      );
    }
    final client = HttpOverrides.runWithHttpOverrides(
      () => HttpClient(),
      _SessionHttpOverrides(),
    );
    final ua = diagnostic
        ? browserUa
        : container.read(patchClashConfigProvider).globalUa.takeFirstValid([
            userAgent,
            globalState.packageInfo.ua,
          ]);
    client.userAgent = ua;
    client.badCertificateCallback = (certificate, host, port) =>
        !diagnostic &&
        FlClashHttpOverrides.allowBadCertificate(
          container,
          certificate,
          host,
          port,
        );
    if (grant != null) {
      client.findProxy = (_) =>
          'PROXY ${grant['user']}:${grant['password']}@${grant['endpoint']}';
    } else {
      client.findProxy = (url) => FlClashHttpOverrides.findProxyFor(
        container,
        url,
        logRequest: !diagnostic,
      );
    }
    final scopedDio = Dio(
      BaseOptions(headers: {'User-Agent': ua}, followRedirects: !diagnostic),
    );
    scopedDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => client,
    );
    final session = RequestSession._(
      this,
      key,
      id,
      _client,
      state,
      scopedDio,
      generation: grant ?? const {},
      cancellationGeneration: _cancellations[key] ?? 0,
      closeClient: () => client.close(force: true),
    );
    scopedDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            if (diagnostic) {
              options.followRedirects = false;
              options.headers = {'User-Agent': browserUa};
            }
            await session.check();
            handler.next(options);
          } catch (error) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: error,
                type: DioExceptionType.cancel,
              ),
            );
          }
        },
        onResponse: (response, handler) async {
          try {
            await session.check();
            handler.next(response);
          } catch (error) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                error: error,
                type: DioExceptionType.cancel,
              ),
            );
          }
        },
      ),
    );
    return session;
  }

  Future<T> withSession<T>({
    required String key,
    required String url,
    RequestMode mode = RequestMode.auto,
    String? proxy,
    bool automatic = false,
    bool diagnostic = false,
    Future<bool> Function()? sourceIsCurrent,
    String? explicitTarget,
    required Future<T> Function(RequestSession session) action,
  }) async {
    final session = await begin(
      key: key,
      url: url,
      mode: mode,
      proxy: proxy,
      automatic: automatic,
      diagnostic: diagnostic,
      sourceIsCurrent: sourceIsCurrent,
      explicitTarget: explicitTarget,
    );
    try {
      return await session.run(() => action(session));
    } finally {
      session.close();
    }
  }

  Future<({RequestFile file, Headers headers})> downloadFileForUrl(
    String url, {
    int maxBytes = 16 * 1024 * 1024,
    Duration deadline = const Duration(seconds: 90),
  }) async {
    final session = RequestSession.current;
    session?.ensureActive();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const RequestUnavailable('profile_download_failed');
    }
    final file = await RequestFile.stage(const []);
    final watch = Stopwatch()..start();
    final token = session?.cancelToken ?? CancelToken();
    var expired = false;
    void cancelDownload() {
      expired = true;
      token.cancel('profile_download_timeout');
      session?.close();
    }

    final timer = Timer(deadline, cancelDownload);
    Duration remaining() {
      final value = deadline - watch.elapsed;
      if (value <= Duration.zero) {
        cancelDownload();
        throw const RequestUnavailable('profile_download_timeout');
      }
      return value;
    }

    try {
      final response = await dio
          .get<ResponseBody>(
            url,
            options: Options(responseType: ResponseType.stream),
            cancelToken: token,
          )
          .timeout(remaining());
      final body = response.data;
      if (body == null) {
        throw const RequestUnavailable('profile_download_failed');
      }
      final declared = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (declared != null && declared > maxBytes) {
        await body.stream.listen((_) {}).cancel();
        throw const RequestUnavailable('profile_download_too_large');
      }
      await file.receive(body.stream, maxBytes: maxBytes, remaining: remaining);
      remaining();
      return (file: file, headers: response.headers);
    } catch (error) {
      token.cancel('profile_download_cancelled');
      session?.close();
      await file.close();
      if (expired || error is TimeoutException) {
        throw const RequestUnavailable('profile_download_timeout');
      }
      if (error is RequestUnavailable) rethrow;
      if (error is DioException && error.type == DioExceptionType.cancel) {
        throw const RequestUnavailable('request_cancelled');
      }
      throw const RequestUnavailable('profile_download_failed');
    } finally {
      timer.cancel();
      watch.stop();
    }
  }

  Future<Response<Uint8List>> getFileResponseForUrl(String url) async {
    final response = await downloadFileForUrl(url);
    try {
      return Response<Uint8List>(
        data: await response.file.staged.readAsBytes(),
        headers: response.headers,
        requestOptions: RequestOptions(path: url),
        statusCode: HttpStatus.ok,
      );
    } finally {
      await response.file.close();
    }
  }

  Future<Response<String>> getTextResponseForUrl(String url) => dio.get<String>(
    url,
    options: Options(responseType: ResponseType.plain),
    cancelToken: RequestSession.current?.cancelToken,
  );

  Future<void> validateVersionResult(Map<String, dynamic> data) async {
    if (!identical(data, _versionData) || _versionSession == null) {
      throw const RequestUnavailable('request_cancelled');
    }
    await _versionSession!.check();
  }

  void releaseVersionResult(Map<String, dynamic> data) {
    if (!identical(data, _versionData)) return;
    _versionSession?.close();
    _versionSession = null;
    _versionData = null;
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    const url = 'https://api.github.com/repos/$repository/releases/latest';
    _versionSession?.close();
    _versionData = null;
    _versionSession = null;
    final session = await begin(key: 'versionCheck', url: url);
    var retained = false;
    try {
      final response = await session.dio.get<Map<String, dynamic>>(
        url,
        cancelToken: session.cancelToken,
      );
      await session.check();
      if (response.statusCode != 200) return null;
      final data = response.data!;
      final remoteVersion = data['tag_name'] as String;
      if (compareVersions(
            remoteVersion.replaceAll('v', ''),
            globalState.packageInfo.version,
          ) <=
          0) {
        return null;
      }
      _versionSession = session;
      _versionData = data;
      retained = true;
      return data;
    } finally {
      if (!retained) session.close();
    }
  }
}

final request = Request();

String? getFileNameForDisposition(String? disposition) {
  if (disposition == null) return null;
  final parseValue = HeaderValue.parse(disposition);
  final parameters = parseValue.parameters;
  final fileNamePointKey = parameters.keys.firstWhere(
    (key) => key == 'filename*',
    orElse: () => '',
  );
  if (fileNamePointKey.isNotEmpty) {
    final res = parameters[fileNamePointKey]?.split("''") ?? [];
    if (res.length >= 2) {
      return Uri.decodeComponent(res[1]);
    }
  }
  final fileNameKey = parameters.keys.firstWhere(
    (key) => key == 'filename',
    orElse: () => '',
  );
  if (fileNameKey.isEmpty) return null;
  return parameters[fileNameKey];
}
