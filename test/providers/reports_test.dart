import 'dart:async';

import 'package:fl_clash/providers/reports.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const report = <String, Object?>{
  'state': 'unverified',
  'source': 'startup',
  'savedAt': 1,
  'rawAvailable': true,
};

Map<String, Object?> inventory(String revision, {bool empty = false}) => {
  'status': 'ready',
  'revision': revision,
  'bytes': 30,
  'items': [
    if (!empty) {'token': revision, 'summary': report},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.follow.clash/app');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    container.listen(reportsProvider, (_, _) {});
  });
  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('late summary cannot resurrect a deleted selection', () async {
    final summary = Completer<Map<String, Object?>>();
    var deleted = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      return switch (args['action']) {
        'inventory' => inventory(deleted ? 'new' : 'old', empty: deleted),
        'summary' => summary.future,
        'delete' => () {
          expect(args['revision'], 'old');
          expect(args['token'], 'old');
          deleted = true;
          return {'status': 'deleted'};
        }(),
        _ => throw StateError('Unexpected operation'),
      };
    });
    final controller = container.read(reportsProvider.notifier);
    await controller.refresh();
    final selection = controller.select(
      container.read(reportsProvider).items.single,
    );
    await controller.remove('old', 'old');
    summary.complete({'status': 'ready', 'summary': report});
    await selection;
    expect(container.read(reportsProvider).selected, isNull);
    expect(container.read(reportsProvider).items, isEmpty);
    expect(container.read(reportsProvider).status, 'deleted');
  });

  test('cancelled export reply cannot replace a fresh inventory', () async {
    final output = Completer<Map<String, Object?>>();
    String? nonce;
    var cancelled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'cancelReportExport') {
        expect(args['nonce'], nonce);
        cancelled = true;
        return null;
      }
      if (call.method == 'exportReport') {
        expect(args['kind'], 'summary');
        expect(args.containsKey('path'), false);
        nonce = args['nonce'] as String;
        return output.future;
      }
      return args['action'] == 'summary'
          ? {'status': 'ready', 'summary': report}
          : inventory(cancelled ? 'fresh' : 'old');
    });
    final controller = container.read(reportsProvider.notifier);
    await controller.refresh();
    await controller.select(container.read(reportsProvider).items.single);
    final pending = controller.export(false);
    await Future<void>.delayed(Duration.zero);
    controller.cancel();
    await controller.refresh();
    output.complete({'status': 'exported'});
    await pending;
    expect(cancelled, true);
    expect(container.read(reportsProvider).revision, 'fresh');
    expect(container.read(reportsProvider).status, 'ready');
    expect(container.read(reportsProvider).busy, false);
  });

  test('channel error is fixed status and clears the busy state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'PRIVATE_PATH', message: 'SECRET');
    });
    await container.read(reportsProvider.notifier).refresh();
    final state = container.read(reportsProvider);
    expect(state.status, 'io');
    expect(state.items, isEmpty);
    expect(state.busy, false);
  });

  testWidgets('timeout does not apply a later inventory reply', (tester) async {
    final reply = Completer<Map<String, Object?>>();
    messenger.setMockMethodCallHandler(channel, (call) => reply.future);
    final pending = container.read(reportsProvider.notifier).refresh();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await pending;
    expect(container.read(reportsProvider).status, 'deadline');
    expect(container.read(reportsProvider).busy, false);
    reply.complete(inventory('late'));
    await tester.pump();
    expect(container.read(reportsProvider).items, isEmpty);
  });
}
