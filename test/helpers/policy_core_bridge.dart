import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class PolicyCoreBridge {
  PolicyCoreBridge(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          const prefix = 'application-input-bridge:';
          if (!line.startsWith(prefix)) return;
          final response = jsonDecode(line.substring(prefix.length)) as Map;
          _pending
              .remove(response['id'])!
              .complete(Map<String, Object?>.from(response['result'] as Map));
        });
    process.stderr.drain<void>();
  }
  final Process process;
  int _next = 0;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  Future<Map<String, Object?>> call(String method, [Object? arguments]) {
    final id = ++_next;
    final reply = Completer<Map<String, Object?>>();
    _pending[id] = reply;
    process.stdin.writeln(
      jsonEncode({'id': id, 'method': method, 'arguments': arguments}),
    );
    return reply.future.timeout(const Duration(seconds: 10));
  }

  Future<void> close() async {
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
  }
}
