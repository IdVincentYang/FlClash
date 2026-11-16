import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:fl_clash/common/boot_guard.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/boot_fixture.dart';
import '../helpers/failing_preferences.dart';
import '../helpers/policy_core_bridge.dart';

class _Native extends Mock implements Service {}

class _ObservedCompleter<T> implements Completer<T> {
  _ObservedCompleter(this.actual);

  final Completer<T> actual;
  void Function()? onRead;

  @override
  Future<T> get future {
    onRead?.call();
    return actual.future;
  }

  @override
  bool get isCompleted => actual.isCompleted;
  @override
  void complete([FutureOr<T>? value]) => actual.complete(value);
  @override
  void completeError(Object error, [StackTrace? stackTrace]) =>
      actual.completeError(error, stackTrace);
}

class _ExitAction extends SystemAction {
  _ExitAction(this.requestClient, this.nativeService, this.startupGuard);
  @override
  final Request requestClient;
  @override
  final Service nativeService;
  @override
  final BootGuard startupGuard;
  final calls = <String>[];
  final failures = <String, Error>{};
  Duration watchdog = const Duration(hours: 1);
  @override
  Duration get exitWatchdogDuration => watchdog;

  Future<void> step(String name) async {
    calls.add(name);
    if (failures[name] case final error?) throw error;
  }

  @override
  Future<void> shutdownTray() => step('tray');
  @override
  Future<void> shutdownDns() => step('dns');
  @override
  Future<void> stopSystemProxy() => step('proxy');
  @override
  Future<void> closeWindow() => step('window');
  @override
  Future<void> closeCore() => step('core');
  @override
  Future<void> exitApplication() => step('exit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final executable = Platform.environment['FLCLASH_EXIT_CORE_BRIDGE'];
  late Directory home;
  late PolicyCoreBridge bridge;
  late _Native native;
  late Request client;
  late _ExitAction action;
  late ProviderContainer container;
  late FailingPreferences storage;
  late BootFixture boot;
  late DebugPrintCallback previousPrint;
  final logs = <String>[];
  final controls = <Map<String, Object?>>[];
  final controlResults = <Map<String, Object?>>[];
  final faults = <String, Object>{};
  final stacks = <String, StackTrace>{};
  Completer<void>? prepareGate;
  Completer<void>? prepareEntered;
  Future<void> Function(String action)? beforeControl;
  Future<void> Function(String action)? afterControl;
  final extraContainers = <ProviderContainer>[];
  var rejectAck = false;

  Future<Map<String, Object?>> control(Map<String, Object?> data) =>
      bridge.call('control', data);

  Future<({Object? error, StackTrace? stack})> finishExit([
    bool needSave = true,
  ]) async {
    try {
      await action.handleExit(needSave);
      return (error: null, stack: null);
    } catch (error, stack) {
      return (error: error, stack: stack);
    }
  }

  void expectIndependentCleanup() {
    for (final name in ['tray', 'dns', 'proxy', 'window', 'core', 'exit']) {
      expect(action.calls.where((call) => call == name), hasLength(1));
    }
    expect(boot.calls.where((call) => call.$1 == 'close'), hasLength(1));
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.isInit;
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'exit-fixture',
      packageName: 'exit-fixture',
      version: '1',
      buildNumber: '1',
    );
  });

  setUp(() async {
    if (executable == null) return;
    home = await Directory.systemTemp.createTemp('exit-core-');
    AppPath.supportDirectory = () async => home;
    AppPath.temporaryDirectory = () async => home;
    AppPath.cacheDirectory = () async => home;
    bridge = PolicyCoreBridge(
      await Process.start(
        executable,
        [r'-test.run=^TestApplicationInputBridge$'],
        workingDirectory: Directory('core').absolute.path,
        environment: {'FLCLASH_APPLICATION_INPUT_BRIDGE_HOME': home.path},
      ),
    );
    faults.clear();
    stacks.clear();
    controls.clear();
    controlResults.clear();
    logs.clear();
    prepareGate = null;
    prepareEntered = null;
    beforeControl = null;
    afterControl = null;
    extraContainers.clear();
    rejectAck = false;
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    final actual = await SharedPreferences.getInstance();
    await actual.remove(configKey);
    storage = FailingPreferences(actual, []);
    preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
      ..complete(storage);
    native = _Native();
    when(() => native.requestControl(any())).thenAnswer((invocation) async {
      final data = Map<String, Object?>.from(
        invocation.positionalArguments.single as Map,
      );
      controls.add(data);
      final name = data['action']! as String;
      await beforeControl?.call(name);
      if (faults[name] case final error?) {
        Error.throwWithStackTrace(error, stacks[name] ?? StackTrace.current);
      }
      final result = await control(data);
      controlResults.add(result);
      await afterControl?.call(name);
      if (name == 'complete' && rejectAck) throw StateError('ack-lost');
      return result;
    });
    when(native.getRequestState).thenAnswer((_) => bridge.call('nativeState'));
    when(
      () => native.prepareRunIntent(running: false, source: 'exit'),
    ).thenAnswer((_) async {
      action.calls.add('prepare');
      prepareEntered?.complete();
      await prepareGate?.future;
      if (faults['prepare'] case final error?) {
        Error.throwWithStackTrace(
          error,
          stacks['prepare'] ?? StackTrace.current,
        );
      }
      return 1;
    });
    client = Request.scoped(native: native, isAndroid: true);
    boot = BootFixture();
    final guard = boot.guard();
    await guard.evaluate(profileId: null);
    boot.calls.clear();
    action = _ExitAction(client, native, guard);
    container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    globalState.container = container;
    container.read(systemActionProvider.notifier);
    client.attach(container);
    await client.ready();
    final stats = await bridge.call('requestKeyStats');
    expect(stats['clientReady'], true);
    controls.clear();
    controlResults.clear();
  });

  tearDown(() async {
    if (executable == null) return;
    if (prepareGate case final gate? when !gate.isCompleted) gate.complete();
    beforeControl = null;
    afterControl = null;
    faults.clear();
    rejectAck = false;
    try {
      await client.detach();
    } finally {
      container.dispose();
      for (final other in extraContainers) {
        other.dispose();
      }
      await bridge.close();
      await home.delete(recursive: true);
      debugPrint = previousPrint;
    }
  });

  Future<void> replaceAttachment() async {
    final other = ProviderContainer();
    extraContainers.add(other);
    client.attach(other);
    await client.ready();
  }

  Future<RequestSession> begin(String key) => client.begin(
    key: key,
    url: 'http://127.0.0.1/',
    mode: RequestMode.direct,
    explicitTarget: 'DIRECT',
  );

  group(
    'actual exit cleanup with Core receipts',
    () {
      for (final failure in ['prepare', 'detach', 'both', 'none']) {
        test('$failure preserves qualified saving and cleanup', () async {
          final first = StateError('$failure-first');
          final trace = StackTrace.fromString('original-$failure-stack');
          if (failure == 'prepare' || failure == 'both') {
            faults['prepare'] = first;
            stacks['prepare'] = trace;
          }
          if (failure == 'detach' || failure == 'both') {
            faults['detach'] = failure == 'both'
                ? StateError('detach-secondary')
                : first;
            stacks['detach'] = trace;
          }
          final result = await finishExit();
          expect(result.error, failure == 'none' ? isNull : same(first));
          if (failure != 'none') expect(result.stack.toString(), '$trace');
          expect(storage.writes, 1);
          expect(await preferences.getConfig(), isNotNull);
          final actions = controls.map((c) => c['action']).toList();
          expect(
            actions,
            containsAllInOrder(['lock', 'beginCommit', 'complete', 'detach']),
          );
          expectIndependentCleanup();
          if (failure == 'both') {
            expect(logs.join('\n'), contains('detach-secondary'));
          }
        });
      }

      test('save opt-out still attempts every independent cleanup', () async {
        faults['prepare'] = StateError('prepare');
        expect((await finishExit(false)).error, same(faults['prepare']));
        expect(storage.writes, 0);
        expect(controls.map((c) => c['action']), isNot(contains('lock')));
        expect(controls.map((c) => c['action']), contains('detach'));
        expectIndependentCleanup();
      });

      test(
        'Core rejects beginCommit after detach despite lock success',
        () async {
          final identity = (await bridge.call('requestKeyStats'))['client'];
          expect(await control({'action': 'detach', 'client': identity}), {
            'ok': true,
          });
          final receipt = await control({'action': 'lock', 'client': identity});
          expect(receipt['id'], isA<String>());
          expect(
            await control({
              'action': 'beginCommit',
              'client': identity,
              'id': receipt['id'],
            }),
            {'error': 'request_cancelled'},
          );
          await control({
            'action': 'complete',
            'client': identity,
            'id': receipt['id'],
          });
        },
      );

      for (final fault in ['fault', 'writer']) {
        test('$fault refuses saving without skipping cleanup', () async {
          if (fault == 'fault') {
            await bridge.call('exitFault');
          } else {
            final identity = (await bridge.call('requestKeyStats'))['client'];
            final receipt = await control({
              'action': 'lock',
              'client': identity,
            });
            await control({
              'action': 'beginCommit',
              'client': identity,
              'id': receipt['id'],
            });
            await control({'action': 'detach', 'client': identity});
            await control({'action': 'ready', 'client': identity});
            expect((await bridge.call('requestKeyStats'))['writers'], 1);
          }
          final result = await finishExit();
          expect(
            result.error,
            isA<RequestUnavailable>().having(
              (e) => e.code,
              'code',
              'request_restart_required',
            ),
          );
          expect(storage.writes, 0);
          expect(controls.map((c) => c['action']), contains('lock'));
          expectIndependentCleanup();
          if (fault == 'writer') {
            expect(
              await File('${home.path}/request-recovery-required').exists(),
              true,
            );
            expect((await bridge.call('requestKeyStats'))['writers'], 1);
          }
        });
      }

      test(
        'ack loss retains recovery responsibility after actual writing',
        () async {
          rejectAck = true;
          expect((await finishExit()).error, isA<RequestUnavailable>());
          expect(storage.writes, 1);
          expect(
            await File('${home.path}/request-recovery-required').exists(),
            true,
          );
          expectIndependentCleanup();
        },
      );

      test(
        'parallel failures preserve the actual first error and all facts',
        () async {
          for (final name in ['tray', 'dns', 'proxy']) {
            action.failures[name] = StateError('$name-failure');
          }
          expect((await finishExit()).error, same(action.failures['tray']));
          expect(storage.writes, 1);
          expectIndependentCleanup();
          for (final name in ['tray', 'dns', 'proxy']) {
            expect(logs.join('\n'), contains('$name-failure'));
          }
        },
      );
      test(
        'BootGuard close IO failure is an attempt, not durable success',
        () async {
          boot.intercept = (name, arguments) async {
            if (name == 'close') throw StateError('boot-close-io');
            return boot.respond(name, arguments);
          };
          expect((await finishExit()).error, isNull);
          expect(await action.startupGuard.isCurrent(), false);
          expect(boot.record?.stage?.name, isNot('closed'));
          expect(storage.writes, 1);
          expectIndependentCleanup();
        },
      );

      test(
        'preferences failure still completes its receipt and detaches',
        () async {
          storage = FailingPreferences(storage.actual, [PreferenceWrite.fail]);
          preferences.sharedPreferencesCompleter =
              Completer<SharedPreferences?>()..complete(storage);
          expect(
            (await finishExit()).error,
            isA<RequestUnavailable>().having(
              (e) => e.code,
              'code',
              'preferences_save_failed',
            ),
          );
          expect(storage.writes, 1);
          expect(await preferences.getConfig(), isNull);
          expect(
            controls.map((c) => c['action']),
            containsAllInOrder(['beginCommit', 'complete', 'detach']),
          );
          expect((await bridge.call('requestKeyStats'))['commits'], 0);
          expectIndependentCleanup();
        },
      );

      test(
        'quiesce closes existing and refuses new Android sessions',
        () async {
          await bridge.call('sourceState');
          final session = await begin('active');
          final scope = client.quiesceForExit();
          expect(session.cancelToken.isCancelled, true);
          await expectLater(
            session.check(),
            throwsA(isA<RequestUnavailable>()),
          );
          final starts = controls.where((c) => c['action'] == 'begin').length;
          await expectLater(begin('new'), throwsA(isA<RequestUnavailable>()));
          expect(
            controls.where((c) => c['action'] == 'begin'),
            hasLength(starts),
          );
          expect((await bridge.call('requestKeyStats'))['clientReady'], true);
          var writes = 0;
          await scope.commit(() async {
            writes++;
          });
          expect(writes, 1);
          await scope.detach();
          expect((await bridge.call('requestKeyStats'))['clientReady'], false);
        },
      );

      test(
        'quiesce fences a begin already waiting in the serial queue',
        () async {
          await bridge.call('sourceState');
          final gate = Completer<void>();
          final blocked = dataMutations.run(() => gate.future);
          final pending = expectLater(
            begin('queued'),
            throwsA(isA<RequestUnavailable>()),
          );
          final scope = client.quiesceForExit();
          gate.complete();
          await blocked;
          await pending;
          expect(controls.where((c) => c['action'] == 'begin'), isEmpty);
          await scope.detach();
        },
      );

      for (final held in ['inspect', 'begin']) {
        test('quiesce fences begin awaiting $held native response', () async {
          await bridge.call('sourceState');
          final gate = Completer<void>();
          final entered = Completer<void>();
          beforeControl = (name) async {
            if (name == held && !entered.isCompleted) {
              entered.complete();
              await gate.future;
            }
          };
          final pending = expectLater(
            begin('awaiting'),
            throwsA(isA<RequestUnavailable>()),
          );
          await entered.future;
          final scope = client.quiesceForExit();
          gate.complete();
          await pending;
          await Future<void>.delayed(Duration.zero);
          expect((await bridge.call('requestKeyStats'))['leases'], 0);
          await scope.detach();
        });
      }

      for (final held in ['prepare', 'lock', 'beginCommit']) {
        test(
          'old exit cannot save or detach new attachment during $held',
          () async {
            final entered = Completer<void>();
            final gate = Completer<void>();
            if (held == 'prepare') {
              prepareGate = gate;
              prepareEntered = entered;
            } else {
              afterControl = (name) async {
                if (name == held && !entered.isCompleted) {
                  entered.complete();
                  await gate.future;
                }
              };
            }
            final exiting = finishExit();
            await entered.future;
            await replaceAttachment();
            final newer = await bridge.call('requestKeyStats');
            controls.clear();
            gate.complete();
            expect((await exiting).error, isA<RequestUnavailable>());
            expect(storage.writes, 0);
            expect(client.isAttached, true);
            expect(client.hasNativeClient, true);
            final now = await bridge.call('requestKeyStats');
            expect(now['client'], newer['client']);
            expect(now['clientReady'], true);
            expect(now['writers'], 0);
            if (held == 'beginCommit') {
              expect(
                await File('${home.path}/request-recovery-required').exists(),
                true,
              );
            }
            expect(controls.where((c) => c['action'] == 'detach'), isEmpty);
            expectIndependentCleanup();
          },
        );
      }

      test(
        'initialized preferences await cannot write after new attachment',
        () async {
          final initialized = preferences.sharedPreferencesCompleter;
          expect(initialized.isCompleted, true);
          expect(await preferences.isInit, true);
          final replacing = Completer<void>();
          final observed = _ObservedCompleter(initialized);
          observed.onRead = () {
            observed.onRead = null;
            scheduleMicrotask(() {
              replaceAttachment().then(
                (_) => replacing.complete(),
                onError: replacing.completeError,
              );
            });
          };
          preferences.sharedPreferencesCompleter = observed;
          final result = await finishExit();
          await replacing.future;
          expect(result.error, isA<RequestUnavailable>());
          expect(client.isAttached, true);
          expect(client.hasNativeClient, true);
          final now = await bridge.call('requestKeyStats');
          expect(now['clientReady'], true);
          expect(now['writers'], 0);
          expect(controls.where((c) => c['action'] == 'detach'), isEmpty);
          expectIndependentCleanup();
          expect(
            storage.writes,
            0,
            reason: 'the initialized Future must not leave a pre-storage gap',
          );
          expect(storage.getString(configKey), isNull);
        },
      );

      test('queued save reads config after storage preparation', () async {
        final gate = Completer<void>();
        final prepared = Completer<void>();
        final blocker = dataMutations.run(() => gate.future);
        final observed = _ObservedCompleter(
          preferences.sharedPreferencesCompleter,
        );
        observed.onRead = () {
          observed.onRead = null;
          prepared.complete();
        };
        preferences.sharedPreferencesCompleter = observed;
        final exiting = finishExit();
        await prepared.future;
        await Future<void>.delayed(Duration.zero);
        final current = container.read(windowSettingProvider);
        final latest = current.copyWith(width: 1371);
        container.read(windowSettingProvider.notifier).value = latest;
        gate.complete();
        await blocker;
        expect((await exiting).error, isNull);
        expect((await preferences.getConfig())?.windowProps, latest);
        expect(storage.writes, 1);
        expectIndependentCleanup();
      });

      test(
        'missing preferences reports failed saving and still detaches',
        () async {
          preferences.sharedPreferencesCompleter =
              Completer<SharedPreferences?>()..complete(null);
          final result = await finishExit();
          expect(
            result.error,
            isA<RequestUnavailable>().having(
              (error) => error.code,
              'code',
              'preferences_save_failed',
            ),
          );
          expect(storage.writes, 0);
          expect(
            controls.map((c) => c['action']),
            containsAllInOrder(['lock', 'beginCommit', 'complete', 'detach']),
          );
          expectIndependentCleanup();
        },
      );

      test('started storage keeps its receipt after new attachment', () async {
        final entered = Completer<void>();
        final gate = Completer<void>();
        storage = FailingPreferences(
          storage.actual,
          [],
          beforeWrite: (_) async {
            entered.complete();
            await gate.future;
          },
        );
        preferences.sharedPreferencesCompleter = Completer<SharedPreferences?>()
          ..complete(storage);
        final exiting = finishExit();
        await entered.future;
        expect(storage.writes, 1);
        final oldClient = (await bridge.call('requestKeyStats'))['client'];
        await replaceAttachment();
        final newer = await bridge.call('requestKeyStats');
        expect(newer['client'], isNot(oldClient));
        expect(newer['writers'], 1);
        controls.clear();
        gate.complete();
        expect((await exiting).error, isA<RequestUnavailable>());
        expect(storage.writes, 1);
        expect(storage.getString(configKey), isNotNull);
        final completion = controls.singleWhere(
          (c) => c['action'] == 'complete',
        );
        expect(completion['client'], oldClient);
        expect(controls.where((c) => c['action'] == 'detach'), isEmpty);
        final now = await bridge.call('requestKeyStats');
        expect(now['client'], newer['client']);
        expect(now['clientReady'], true);
        expect(now['writers'], 0);
        expect(
          await File('${home.path}/request-recovery-required').exists(),
          true,
        );
        expectIndependentCleanup();
      });

      test('queued exit commit and final detach expire together', () async {
        final scope = client.quiesceForExit();
        final gate = Completer<void>();
        final blocker = dataMutations.run(() => gate.future);
        var writes = 0;
        final rejected = expectLater(
          scope.commit(() async {
            writes++;
          }),
          throwsA(isA<RequestUnavailable>()),
        );
        await replaceAttachment();
        gate.complete();
        await blocker;
        await rejected;
        await expectLater(scope.detach(), throwsA(isA<RequestUnavailable>()));
        expect(writes, 0);
        expect(client.isAttached, true);
        expect((await bridge.call('requestKeyStats'))['clientReady'], true);
      });

      for (final situation in ['detached', 'attach-failed', 'never-attached']) {
        test(
          '$situation cannot downgrade Android exit save to no receipt',
          () async {
            if (situation == 'detached') {
              await client.detach();
              await client.detach();
            } else if (situation == 'attach-failed') {
              faults['attach'] = StateError('attach-down');
              final other = ProviderContainer();
              extraContainers.add(other);
              client.attach(other);
              await expectLater(client.ready(), throwsStateError);
            } else {
              await client.detach();
              client = Request.scoped(native: native, isAndroid: true);
              action = _ExitAction(client, native, action.startupGuard);
              container.dispose();
              container = ProviderContainer(
                overrides: [systemActionProvider.overrideWith(() => action)],
              );
              globalState.container = container;
              container.read(systemActionProvider.notifier);
            }
            expect((await finishExit()).error, isA<RequestUnavailable>());
            expect(storage.writes, 0);
            expectIndependentCleanup();
          },
        );
      }

      for (final state in ['absent', 'fault']) {
        test(
          'save opt-out does not require qualification for $state',
          () async {
            if (state == 'absent') {
              await client.detach();
            } else {
              await bridge.call('exitFault');
            }
            controls.clear();
            expect((await finishExit(false)).error, isNull);
            expect(storage.writes, 0);
            expect(controls.where((c) => c['action'] == 'lock'), isEmpty);
            expectIndependentCleanup();
          },
        );
      }

      test('concurrent and later exits never repeat save or detach', () async {
        final first = action.handleExit();
        final second = action.handleExit(false);
        expect(identical(first, second), true);
        await Future.wait([first, second]);
        await action.handleExit();
        expect(storage.writes, 1);
        expect(controls.where((c) => c['action'] == 'detach'), hasLength(1));
        expectIndependentCleanup();
      });

      for (final held in ['prepare', 'save']) {
        test(
          'watchdog exits once while $held hangs and cleanup resumes',
          () async {
            action.watchdog = const Duration(milliseconds: 5);
            final gate = Completer<void>();
            final entered = Completer<void>();
            if (held == 'prepare') {
              prepareGate = gate;
              prepareEntered = entered;
            } else {
              storage = FailingPreferences(
                storage.actual,
                [],
                beforeWrite: (_) async {
                  entered.complete();
                  await gate.future;
                },
              );
              preferences.sharedPreferencesCompleter =
                  Completer<SharedPreferences?>()..complete(storage);
            }
            final exiting = finishExit();
            await entered.future;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(action.calls.where((c) => c == 'exit'), hasLength(1));
            for (final name in ['tray', 'dns', 'proxy']) {
              expect(action.calls.where((c) => c == name), hasLength(1));
            }
            expect(controls.where((c) => c['action'] == 'detach'), isEmpty);
            gate.complete();
            expect((await exiting).error, isNull);
            expect(storage.writes, 1);
            expectIndependentCleanup();
          },
        );
      }
    },
    skip: executable == null
        ? 'build the real Go bridge and set FLCLASH_EXIT_CORE_BRIDGE'
        : false,
  );
}
