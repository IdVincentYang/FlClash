import 'dart:convert';

import 'package:fl_clash/common/boot_guard.dart';
import 'package:fl_clash/common/boot_record.dart';

const bootContext = BootContext(
  pid: 200,
  processName: 'example.app',
  processEpoch: 'current',
  attempt: 'current:1',
  processStartedAt: 5000,
);

BootRecord interruptedBoot({
  int? profileId = 7,
  int count = 0,
  String epoch = 'previous',
  BootPhase phase = BootPhase.setup,
}) => BootRecord(
  version: 1,
  stage: BootStage.starting,
  phase: phase,
  profileId: profileId,
  startedAt: 1000,
  failureCount: count,
  pid: 100,
  processEpoch: epoch,
  attempt: '$epoch:1',
);

class BootFixture {
  String? raw;
  bool current = true;
  bool malformed = false;
  String writeStatus = 'ok';
  final calls = <(String, Map<String, Object?>)>[];
  Future<Map<String, Object?>> Function(String, Map<String, Object?>)?
  intercept;

  BootFixture({this.raw});

  BootRecord? get record => BootRecordRead.decode(raw).record;
  Iterable<(String, Map<String, Object?>)> get writes =>
      calls.where((call) => call.$1 == 'write');

  Future<Map<String, Object?>> control(
    String action,
    Map<String, Object?> arguments,
  ) async {
    calls.add((action, arguments));
    if (intercept != null) return intercept!(action, arguments);
    return respond(action, arguments);
  }

  Future<Map<String, Object?>> respond(
    String action,
    Map<String, Object?> arguments,
  ) async {
    if ((action == 'write' || action == 'close') &&
        arguments['record'] is String &&
        writeStatus == 'ok') {
      raw = arguments['record'] as String;
    }
    return {
      'status': action == 'write' ? writeStatus : 'ok',
      'current': current,
      'writable': true,
      'busy': false,
      'attempt': bootContext.attempt,
      'pid': bootContext.pid,
      'processEpoch': bootContext.processEpoch,
      'processName': bootContext.processName,
      'processStartedAt': bootContext.processStartedAt,
      if (action == 'begin') ...{'record': raw, 'malformed': malformed},
    };
  }

  BootGuard guard({
    bool supported = true,
    AppExitInfo? exit,
    Duration timeout = const Duration(seconds: 2),
  }) => BootGuard(
    supported: supported,
    control: control,
    readExitInfo: (_) async => exit,
    now: () => 6000,
    timeout: timeout,
  );

  static String encode(BootRecord value) => json.encode(value);
}
