import 'dart:io';

import 'package:setup_hooks/src/build_cache.dart';
import 'package:setup_hooks/src/fingerprint.dart';

Future<void> waitFor(String path) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!File(path).existsSync()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Barrier timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> main(List<String> arguments) async {
  final root = arguments[0];
  final key = arguments[1];
  final output = '$root/output/core';
  final cache = BuildCache(rootDir: root);
  File('$root/$key-requested').writeAsStringSync(key);
  Future<BuildExecution> build(BuildCache scoped) => scoped.run(
    key: key,
    fingerprint: () async {
      final seen = File('$root/$key-observed');
      if (!seen.existsSync()) {
        seen.writeAsStringSync(File(output).readAsStringSync());
      }
      return Fingerprint(key);
    },
    primaryOutput: output,
    outputs: [output],
    notice: BuildNotice(),
    build: (staging) async {
      staging.file(output).writeAsStringSync(key == 'A' ? 'AAAA' : 'BBBB');
    },
  );
  if (key == 'A') {
    late BuildCache ended;
    try {
      await cache.transaction((scope) async {
        ended = scope;
        await build(scope);
        File('$root/A-installed').writeAsStringSync('held');
        await waitFor('$root/release-A');
        throw StateError('Synthetic outer producer failure');
      });
    } on StateError {
      await waitFor('$root/B-finished');
      try {
        ended.writeFile(output, 'LATE');
        throw Exception('Ended owner wrote live output');
      } on StateError {
        File('$root/A-cleanup-rejected').writeAsStringSync('rejected');
      }
    }
  } else {
    await build(cache);
    File('$root/B-finished').writeAsStringSync('committed');
  }
}
