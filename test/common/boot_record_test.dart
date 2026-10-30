import 'dart:convert';

import 'package:fl_clash/common/boot_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/boot_fixture.dart';

BootDecision decide(
  BootRecord record, {
  AppExitInfo? exit,
  int? profileId = 7,
}) => resolveBootDecision(
  record: record,
  exitInfo: exit,
  context: bootContext,
  profileId: profileId,
);

AppExitInfo exitInfo(
  AppExitReason reason, {
  int time = 2000,
  int pid = 100,
  String name = 'example.app',
}) => AppExitInfo(
  reason: reason,
  timestamp: time,
  pid: pid,
  processName: name,
  description: 'synthetic private description',
);

void main() {
  test(
    'Android reason codes preserve crash, external and unknown distinctions',
    () {
      for (var code = 0; code <= 16; code++) {
        expect(AppExitReason.fromCode(code), AppExitReason.values[code]);
      }
      expect(AppExitReason.fromCode('4'), AppExitReason.unknown);
      expect(AppExitReason.fromCode(99), AppExitReason.unknown);
      expect(AppExitReason.crashNative.isCrash, true);
      expect(AppExitReason.signaled.isExternalStop, true);
      expect(AppExitReason.other.isExternalStop, false);
    },
  );

  test('exit payload validates time and does not print raw description', () {
    expect(AppExitInfo.fromJson({'timestamp': -1}), isNull);
    expect(AppExitInfo.fromJson({'reason': 4}), isNull);
    final info = AppExitInfo.fromJson({
      'timestamp': 2000,
      'reason': 4,
      'pid': 100,
      'processName': 'example.app',
      'description': 'private',
    });
    expect(info?.pid, 100);
    expect(info?.processName, 'example.app');
    expect(info?.toString(), isNot(contains('private')));
  });

  test('current schema round trips and running resets the streak', () {
    final value = interruptedBoot(count: 2, phase: BootPhase.recovery);
    expect(BootRecordRead.decode(json.encode(value)).record, value);
    expect(value.withStage(BootStage.running).failureCount, 0);
    expect(value.withStage(BootStage.closed).failureCount, 0);
  });

  test('legacy null stage is closed and counters are bounded', () {
    final raw = const BootRecord(startedAt: 12, failureCount: 20).toJson()
      ..['stage'] = null;
    final read = BootRecordRead.decode(json.encode(raw));
    expect(read.health, BootRecordHealth.valid);
    expect(read.record?.stage, BootStage.closed);
    expect(read.record?.failureCount, 2);
    expect(read.record?.pid, isNull);
  });

  test('missing, damaged and future format are distinct without throwing', () {
    expect(BootRecordRead.decode(null).health, BootRecordHealth.missing);
    for (final raw in ['not json', '[]', '{}', '"private"', 'x' * 8193]) {
      expect(BootRecordRead.decode(raw).health, BootRecordHealth.damaged);
    }
    expect(
      BootRecordRead.decode('{"version":2}').health,
      BootRecordHealth.newer,
    );
    expect(
      BootRecordRead.decode(null, malformed: true).health,
      BootRecordHealth.damaged,
    );
  });

  test('invalid fields cannot silently become healthy records', () {
    for (final field in {
      'stage': 'bad',
      'phase': 'bad',
      'profileId': '7',
      'pid': -1,
      'startedAt': -1,
      'failureCount': -1,
      'handledExitAt': '0',
      'processEpoch': 9,
    }.entries) {
      final value = interruptedBoot().toJson()..[field.key] = field.value;
      expect(
        BootRecordRead.decode(json.encode(value)).health,
        BootRecordHealth.damaged,
        reason: field.key,
      );
    }
  });

  test(
    'running and closed never turn a runtime crash into startup recovery',
    () {
      for (final stage in [BootStage.running, BootStage.closed]) {
        expect(
          decide(
            interruptedBoot().withStage(stage),
            exit: exitInfo(AppExitReason.crash),
          ).isDegraded,
          false,
        );
      }
    },
  );

  test(
    'only matched process, name, time and unconsumed exit confirm a crash',
    () {
      final record = interruptedBoot();
      expect(
        decide(record, exit: exitInfo(AppExitReason.crash)).crashConfirmed,
        true,
      );
      for (final exit in [
        exitInfo(AppExitReason.crash, pid: 99),
        exitInfo(AppExitReason.crash, name: 'other'),
        exitInfo(AppExitReason.crash, time: 999),
        exitInfo(AppExitReason.crash, time: 5001),
      ]) {
        final result = decide(record, exit: exit);
        expect(result.isDegraded, true);
        expect(result.crashConfirmed, false);
        expect(result.handledExitAt, 0);
      }
      final consumed = BootRecord.fromJson(
        record.toJson()..['handledExitAt'] = 2000,
      )!;
      expect(
        decide(consumed, exit: exitInfo(AppExitReason.crash)).crashConfirmed,
        false,
      );
    },
  );

  test(
    'all matching external reasons veto failures without claiming a cause',
    () {
      for (final reason in AppExitReason.values.where(
        (r) => r.isExternalStop,
      )) {
        final result = decide(
          interruptedBoot(count: 1),
          exit: exitInfo(reason),
        );
        expect(result.isDegraded, false, reason: reason.name);
        expect(result.failureCount, 0);
        expect(result.handledExitAt, 2000);
      }
      expect(
        decide(
          interruptedBoot(),
          exit: exitInfo(AppExitReason.userRequested, pid: 99),
        ).isDegraded,
        true,
      );
    },
  );

  test(
    'unknown interruptions saturate, preserve profile and report failure phase',
    () {
      final result = decide(
        interruptedBoot(count: 2, phase: BootPhase.recovery),
      );
      expect(result.recovery, BootRecovery.repeated);
      expect(result.failureCount, 2);
      expect(result.crashConfirmed, false);
      expect(result.failedProfileId, 7);
      expect(result.failedPhase, BootPhase.recovery);
    },
  );

  test('new profile does not inherit another profile failure count', () {
    final result = decide(interruptedBoot(count: 2), profileId: 8);
    expect(result.isDegraded, true);
    expect(result.failureCount, 0);
  });

  test(
    'same process engine replacement does not count another process failure',
    () {
      final result = decide(
        interruptedBoot(count: 1, epoch: 'current'),
        exit: exitInfo(AppExitReason.crash),
      );
      expect(result.failureCount, 1);
      expect(result.crashConfirmed, false);
      expect(result.isDegraded, true);
    },
  );

  test('legacy incomplete record cannot borrow an unrelated recent crash', () {
    const legacy = BootRecord(
      stage: BootStage.starting,
      startedAt: 1000,
      profileId: 7,
    );
    expect(
      decide(legacy, exit: exitInfo(AppExitReason.crash)).crashConfirmed,
      false,
    );
  });
}
