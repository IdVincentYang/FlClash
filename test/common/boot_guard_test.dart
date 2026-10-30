import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/boot_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/boot_fixture.dart';

void main() {
  test(
    'a status reply from before close cannot restore current permission',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard();
      await guard.evaluate(profileId: 7);
      final status = Completer<Map<String, Object?>>();
      fixture.intercept = (action, _) async =>
          action == 'status' ? status.future : {'status': 'ok'};
      final checking = guard.isCurrent();
      await Future<void>.delayed(Duration.zero);
      final closing = guard.markClosed();
      expect(identical(closing, guard.markClosed()), true);
      await closing;
      status.complete({'current': true});
      expect(await checking, false);
    },
  );
  test(
    'unavailable preferences do not begin record IO or persist on exit',
    () async {
      final fixture = BootFixture(raw: 'preserved');
      final guard = fixture.guard();
      expect(
        (await guard.evaluate(
          profileId: 7,
          preferencesAvailable: false,
        )).recovery,
        BootRecovery.unavailable,
      );
      expect(fixture.calls, isEmpty);
      expect(await guard.isCurrent(), true);
      await guard.markRunning();
      await guard.markClosed();
      expect(fixture.calls.map((c) => c.$1), ['status', 'close']);
      expect(fixture.calls.last.$2, isEmpty);
      expect(fixture.raw, 'preserved');
    },
  );
  test(
    'late begin answer after timeout cannot start writing a record',
    () async {
      final fixture = BootFixture();
      final begin = Completer<Map<String, Object?>>();
      fixture.intercept = (action, _) async =>
          action == 'begin' ? begin.future : {'status': 'ok', 'current': true};
      final guard = fixture.guard(timeout: const Duration(milliseconds: 5));
      expect(
        (await guard.evaluate(profileId: 7)).recovery,
        BootRecovery.unavailable,
      );
      begin.complete({
        'status': 'ok',
        'current': true,
        'writable': true,
        'pid': 200,
        'processName': 'example.app',
        'processEpoch': 'current',
        'attempt': 'current:1',
        'processStartedAt': 5000,
      });
      await Future<void>.delayed(Duration.zero);
      await guard.markRunning();
      expect(fixture.writes, isEmpty);
      expect(guard.decision.recovery, BootRecovery.unavailable);
    },
  );
  test(
    'first launch and subsequent phase changes retain identity and selection',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard();
      expect((await guard.evaluate(profileId: 7)).isDegraded, false);
      await guard.markPhase(BootPhase.core);
      expect(fixture.record?.profileId, 7);
      expect(fixture.record?.phase, BootPhase.core);
      expect(fixture.record?.pid, bootContext.pid);
      expect(fixture.record?.attempt, bootContext.attempt);
      await guard.markRunning();
      expect(fixture.record?.stage, BootStage.running);
    },
  );

  test(
    'concurrent evaluate is one future and cannot replace the selected input',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard();
      final a = guard.evaluate(profileId: 7), b = guard.evaluate(profileId: 8);
      expect(identical(a, b), true);
      await Future.wait([a, b]);
      expect(fixture.calls.where((c) => c.$1 == 'begin').length, 1);
      expect(fixture.record?.profileId, 7);
    },
  );

  test(
    'repeated recovery retains profile and completes without preserving a failure streak',
    () async {
      final fixture = BootFixture(
        raw: BootFixture.encode(interruptedBoot(count: 1)),
      );
      final guard = fixture.guard();
      expect(
        (await guard.evaluate(profileId: 7)).recovery,
        BootRecovery.repeated,
      );
      expect(fixture.record?.profileId, 7);
      await guard.markRunning();
      expect(fixture.record?.failureCount, 0);
    },
  );

  test('only matched exits advance the consumed cursor', () async {
    final fixture = BootFixture(raw: BootFixture.encode(interruptedBoot()));
    await fixture
        .guard(
          exit: const AppExitInfo(
            reason: AppExitReason.crash,
            timestamp: 9000,
            pid: 100,
            processName: 'example.app',
          ),
        )
        .evaluate(profileId: 7);
    expect(fixture.record?.handledExitAt, 0);
    final matched = BootFixture(raw: BootFixture.encode(interruptedBoot()));
    await matched
        .guard(
          exit: const AppExitInfo(
            reason: AppExitReason.userRequested,
            timestamp: 2000,
            pid: 100,
            processName: 'example.app',
          ),
        )
        .evaluate(profileId: 7);
    expect(matched.record?.handledExitAt, 2000);
  });

  test('damaged record is preserved until explicit rebuild', () async {
    final fixture = BootFixture(raw: '{private malformed');
    final guard = fixture.guard();
    expect(
      (await guard.evaluate(profileId: 7)).recovery,
      BootRecovery.damagedRecord,
    );
    await guard.markPhase(BootPhase.recovery);
    expect(fixture.raw, '{private malformed');
    expect(fixture.writes, isEmpty);
    expect(await guard.rebuildRecord(), true);
    expect(fixture.record?.profileId, 7);
    expect(guard.decision.isDegraded, true);
  });

  test('future schema is never overwritten, even by ready or close', () async {
    const raw = '{"version":2,"future":"private"}';
    final fixture = BootFixture(raw: raw);
    final guard = fixture.guard();
    expect(
      (await guard.evaluate(profileId: 7)).recovery,
      BootRecovery.newerRecord,
    );
    await guard.rebuildRecord();
    await guard.markRunning();
    await guard.markClosed();
    expect(fixture.raw, raw);
  });

  test(
    'commit false disables further record writes but leaves current session usable',
    () async {
      final fixture = BootFixture()..writeStatus = 'io';
      final guard = fixture.guard();
      expect(
        (await guard.evaluate(profileId: 7)).recovery,
        BootRecovery.unavailable,
      );
      await guard.markPhase(BootPhase.core);
      await guard.markRunning();
      expect(fixture.writes.length, 1);
      expect(await guard.isCurrent(), true);
    },
  );

  test(
    'busy begin has no automatic retry and remains a usable frontend session',
    () async {
      final fixture = BootFixture();
      fixture.intercept = (action, args) async => {
        'status': action == 'begin' ? 'busy' : 'ok',
        'current': true,
      };
      final guard = fixture.guard();
      expect(
        (await guard.evaluate(profileId: 7)).recovery,
        BootRecovery.unavailable,
      );
      expect(await guard.isCurrent(), true);
      await guard.markRunning();
      expect(fixture.calls.where((c) => c.$1 == 'begin').length, 1);
      expect(fixture.writes, isEmpty);
    },
  );

  test(
    'timed out write can finish natively but cannot restore Dart write permission',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard(timeout: const Duration(milliseconds: 5));
      await guard.evaluate(profileId: 7);
      final late = Completer<Map<String, Object?>>();
      fixture.intercept = (action, args) async =>
          action == 'write' ? late.future : {'status': 'ok', 'current': true};
      await guard.markPhase(BootPhase.core);
      expect(guard.decision.recovery, BootRecovery.unavailable);
      late.complete({'status': 'ok', 'current': true, 'writable': true});
      await Future<void>.delayed(Duration.zero);
      await guard.markRunning();
      expect(fixture.writes.length, 2);
      expect(fixture.calls.where((c) => c.$1 == 'revoke'), isNotEmpty);
    },
  );

  test(
    'close admission is terminal while a phase write is still pending',
    () async {
      final fixture = BootFixture();
      final guard = fixture.guard();
      await guard.evaluate(profileId: 7);
      final late = Completer<Map<String, Object?>>();
      fixture.intercept = (action, args) async =>
          action == 'write' ? late.future : {'status': 'ok', 'current': false};
      final writing = guard.markPhase(BootPhase.core);
      await Future<void>.delayed(Duration.zero);
      await guard.markClosed();
      late.complete({'status': 'stale'});
      await writing;
      await guard.markRunning();
      expect(await guard.isCurrent(), false);
      expect(fixture.writes.length, 2);
      expect(
        json.decode(
          fixture.calls.firstWhere((c) => c.$1 == 'close').$2['record']
              as String,
        )['stage'],
        'closed',
      );
    },
  );

  test(
    'session replacement aborts rebuild and cannot become current again',
    () async {
      final fixture = BootFixture(raw: 'broken');
      final guard = fixture.guard();
      await guard.evaluate(profileId: 7);
      fixture.current = false;
      expect(await guard.rebuildRecord(), false);
      fixture.current = true;
      expect(await guard.isCurrent(), false);
      expect(fixture.writes, isEmpty);
    },
  );

  test('other platforms have no storage or platform IO', () async {
    final fixture = BootFixture();
    final guard = fixture.guard(supported: false);
    await guard.evaluate(profileId: 7);
    await guard.markPhase(BootPhase.core);
    await guard.markRunning();
    await guard.markClosed();
    expect(fixture.calls, isEmpty);
  });
}
