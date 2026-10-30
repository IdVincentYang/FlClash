import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/crash_reports.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Broken {
  @override
  String toString() => throw StateError('synthetic formatter failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterExceptionHandler? previous;
  setUp(() => previous = FlutterError.onError);
  tearDown(() {
    FlutterError.onError = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('$packageName/app'),
          null,
        );
  });

  test(
    'framework error crosses the App channel once and preserves its delegate',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('$packageName/app'), (
            call,
          ) async {
            calls.add(call);
            return {'status': 'stored'};
          });
      var presented = 0;
      final reports = ErrorReports(
        supported: true,
        save: App().captureErrorReport,
      );
      reports.install((_) => presented++);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('synthetic private token'),
          stack: StackTrace.current,
        ),
      );
      expect(presented, 1);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'captureErrorReport');
      expect(calls.single.arguments['source'], 'flutter');
      expect(
        calls.single.arguments['raw'],
        contains('synthetic private token'),
      );
      expect(
        (calls.single.arguments as Map).keys,
        unorderedEquals(['source', 'raw', 'truncated']),
      );
    },
  );

  test(
    'real guarded zone transfers one record through framework dispatch',
    () async {
      final sources = <String>[];
      final delegated = Completer<void>();
      final reports = ErrorReports(
        supported: true,
        save: (value) async {
          sources.add(value['source']! as String);
          return {'status': 'stored'};
        },
      );
      reports.install((_) => delegated.complete());
      runZonedGuarded<void>(() {
        scheduleMicrotask(() => throw StateError('synthetic zone error'));
      }, reports.reportZone);
      await delegated.future;
      expect(sources, ['zone']);
    },
  );

  test(
    'startup presentation does not wait for a blocked or failed recorder',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final sources = <String>[];
      final reports = ErrorReports(
        supported: true,
        save: (value) {
          sources.add(value['source']! as String);
          return pending.future;
        },
      );
      var presented = false;
      try {
        throw StateError('synthetic startup failure');
      } catch (error, stack) {
        reports.startupError(error, stack, () => presented = true);
      }
      expect(presented, true);
      expect(sources, ['startup']);
      pending.completeError(StateError('synthetic IO failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'recorder and formatter failures cannot recurse or suppress framework delegate',
    () async {
      var writes = 0, presentations = 0;
      final reports = ErrorReports(
        supported: true,
        save: (_) async {
          writes++;
          throw StateError('synthetic IO secret');
        },
      );
      reports.install((_) => presentations++);
      FlutterError.reportError(FlutterErrorDetails(exception: _Broken()));
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('synthetic')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(presentations, 2);
      expect(writes, 1);
    },
  );

  test(
    'UTF8 truncation obeys byte cap and marks incomplete material',
    () async {
      Map<String, Object?>? input;
      final reports = ErrorReports(
        supported: true,
        save: (value) async {
          input = value;
          return {'status': 'stored'};
        },
      );
      expect(
        await reports.capture('startup', '密' * 100000, StackTrace.current),
        'stored',
      );
      expect(
        utf8.encode(input!['raw']! as String).length,
        lessThanOrEqualTo(65536),
      );
      expect(input!['truncated'], true);
    },
  );

  test(
    'four pending calls bound backlog and timeout is not a commit acknowledgement',
    () async {
      final pending = Completer<Map<String, Object?>>();
      var writes = 0;
      final reports = ErrorReports(
        supported: true,
        timeout: const Duration(milliseconds: 5),
        save: (_) {
          writes++;
          return pending.future;
        },
      );
      final work = List.generate(
        4,
        (_) => reports.capture('zone', 'synthetic', null),
      );
      expect(await reports.capture('zone', 'synthetic', null), 'busy');
      expect(writes, 4);
      expect(await Future.wait(work), everyElement('deadline'));
      pending.complete({'status': 'stored'});
    },
  );

  test('non Android paths perform no report IO', () async {
    final reports = ErrorReports(
      supported: false,
      save: (_) async => throw StateError('must not write'),
    );
    expect(
      await reports.capture('flutter', StateError('synthetic'), null),
      'unsupported',
    );
  });
}
