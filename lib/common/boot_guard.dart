import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/plugins/app.dart';

typedef BootControl =
    Future<Map<String, Object?>> Function(
      String action,
      Map<String, Object?> arguments,
    );

class BootGuard {
  final bool _supported;
  final BootControl _control;
  final Future<AppExitInfo?> Function(int pid) _readExitInfo;
  final int Function() _now;
  final Duration _timeout;
  Future<BootDecision>? _evaluation;
  Future<void>? _closure;
  Future<void> _writes = Future.value();
  BootDecision _decision = const BootDecision();
  BootRecord? _record;
  BootContext? _context;
  bool _writable = false;
  bool _closed = false;
  bool _lostSession = false;
  bool _repairPending = false;

  BootGuard({
    bool? supported,
    BootControl? control,
    Future<AppExitInfo?> Function(int pid)? readExitInfo,
    int Function()? now,
    Duration timeout = const Duration(seconds: 2),
  }) : _supported = supported ?? system.isAndroid,
       _control = control ?? _platformControl,
       _readExitInfo = readExitInfo ?? _platformExit,
       _now = now ?? _currentMilliseconds,
       _timeout = timeout;

  static int _currentMilliseconds() => DateTime.now().millisecondsSinceEpoch;

  static Future<Map<String, Object?>> _platformControl(
    String action,
    Map<String, Object?> arguments,
  ) async => await app?.bootRecord(action, arguments) ?? const {'status': 'io'};

  static Future<AppExitInfo?> _platformExit(int pid) async =>
      app?.getLastExitInfo(pid: pid);

  BootDecision get decision => _decision;

  Future<BootDecision> evaluate({
    required int? profileId,
    bool preferencesAvailable = true,
  }) => _evaluation ??= _evaluate(profileId, preferencesAvailable);

  Future<Map<String, Object?>> _call(
    String action, [
    Map<String, Object?> arguments = const {},
  ]) => _control(action, arguments).timeout(_timeout);

  void _unavailable() {
    _writable = false;
    _decision = const BootDecision(recovery: BootRecovery.unavailable);
    unawaited(_call('revoke').then<void>((_) {}, onError: (Object _) {}));
  }

  Future<BootDecision> _evaluate(
    int? profileId,
    bool preferencesAvailable,
  ) async {
    if (!_supported || _closed) return _decision;
    if (!preferencesAvailable) {
      _decision = const BootDecision(recovery: BootRecovery.unavailable);
      return _decision;
    }
    Map<String, Object?> value;
    try {
      value = await _call('begin');
    } catch (_) {
      _unavailable();
      return _decision;
    }
    _context = BootContext.fromJson(value);
    if (_closed) return _decision;
    if (value['status'] != 'ok' || _context == null) {
      _unavailable();
      return _decision;
    }
    _writable = value['writable'] == true;
    final previous = BootRecordRead.decode(
      value['record'] as String?,
      malformed: value['malformed'] == true,
    );
    AppExitInfo? exit;
    final record = previous.record;
    if (record?.stage == BootStage.starting &&
        record?.pid != null &&
        record?.processEpoch != _context!.processEpoch) {
      try {
        exit = await _readExitInfo(record!.pid!).timeout(_timeout);
      } catch (_) {
        exit = null;
      }
    }
    if (_closed) return _decision;
    _decision = switch (previous.health) {
      BootRecordHealth.damaged => const BootDecision(
        recovery: BootRecovery.damagedRecord,
      ),
      BootRecordHealth.newer => const BootDecision(
        recovery: BootRecovery.newerRecord,
      ),
      _ => resolveBootDecision(
        record: record,
        exitInfo: exit,
        context: _context!,
        profileId: profileId,
      ),
    };
    final consumed = _decision.handledExitAt;
    final previousConsumed = record?.handledExitAt ?? 0;
    _record = BootRecord(
      version: 1,
      stage: BootStage.starting,
      profileId: profileId,
      startedAt: _now(),
      failureCount: _decision.failureCount,
      lastFailedProfileId: _decision.failedProfileId,
      handledExitAt: consumed > 0
          ? consumed
          : previousConsumed <= _now()
          ? previousConsumed
          : 0,
      pid: _context!.pid,
      processEpoch: _context!.processEpoch,
      attempt: _context!.attempt,
    );
    _repairPending = previous.health == BootRecordHealth.damaged;
    if (previous.health == BootRecordHealth.newer) _writable = false;
    if (!_repairPending) await _save();
    return _decision;
  }

  Future<bool> isCurrent() async {
    if (_closed || _lostSession) return false;
    if (!_supported) return true;
    try {
      final status = await _call('status');
      if (status['current'] == true && !_closed && !_lostSession) return true;
    } catch (_) {
      _unavailable();
    }
    _lostSession = true;
    return false;
  }

  Future<bool> rebuildRecord() async {
    if (!_repairPending || !await isCurrent()) return false;
    _repairPending = false;
    await _enqueue(_save);
    return _writable;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result;
    return result;
  }

  Future<void> _save() async {
    if (!_supported ||
        !_writable ||
        _repairPending ||
        _closed ||
        _record == null) {
      return;
    }
    try {
      final result = await _call('write', {
        'attempt': _context!.attempt,
        'record': json.encode(_record),
      });
      if (result['status'] != 'ok') _unavailable();
    } catch (_) {
      _unavailable();
    }
  }

  Future<void> markPhase(BootPhase phase) => _enqueue(() async {
    if (_closed || _record == null) return;
    _record = _record!.withStage(BootStage.starting, phase: phase);
    await _save();
  });

  Future<void> markRunning() => _enqueue(() async {
    if (_closed || _record == null) return;
    _record = _record!.withStage(BootStage.running);
    await _save();
  });

  Future<void> markClosed() => _closure ??= _markClosed();

  Future<void> _markClosed() async {
    if (_closed) return;
    _closed = true;
    if (!_supported) return;
    try {
      await _call('close', {
        if (_writable && !_repairPending && _record != null)
          'record': json.encode(_record!.withStage(BootStage.closed)),
      });
    } catch (_) {
      _writable = false;
    }
  }
}

final bootGuard = BootGuard();
