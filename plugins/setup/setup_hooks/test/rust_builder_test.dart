import 'dart:io';

import 'package:setup_hooks/src/build_cache.dart';
import 'package:setup_hooks/src/options.dart';
import 'package:setup_hooks/src/rust_builder.dart';
import 'package:setup_hooks/src/target.dart';
import 'package:test/test.dart';

class _HostFixtureTarget extends Target {
  const _HostFixtureTarget(this.hostTriple)
    : super(goos: 'darwin', goarch: 'arm64');

  final String hostTriple;

  @override
  String get rustTriple => hostTriple;
}

void main() {
  test(
    'real Cargo writes only its private target and a repeat uses BuildCache',
    () async {
      final root = Directory.systemTemp.createTempSync('helper-cargo-fixture-');
      addTearDown(() => root.deleteSync(recursive: true));
      final crate = Directory('${root.path}/services/helper')
        ..createSync(recursive: true);
      File('${crate.path}/Cargo.toml').writeAsStringSync(
        '[package]\nname = "helper"\nversion = "0.1.0"\nedition = "2021"\n',
      );
      Directory('${crate.path}/src').createSync();
      File('${crate.path}/src/main.rs').writeAsStringSync(
        'fn main() { println!("{}", env!("CORE_SHA256")); }\n',
      );
      final lock = Process.runSync('cargo', [
        'generate-lockfile',
        '--offline',
      ], workingDirectory: crate.path);
      expect(lock.exitCode, 0, reason: lock.stderr as String);
      final version = Process.runSync('rustc', ['-Vv']);
      expect(version.exitCode, 0);
      final triple = RegExp(
        r'^host: (.+)$',
        multiLine: true,
      ).firstMatch(version.stdout as String)!.group(1)!;
      final builder = RustBuilder(
        rootDir: root.path,
        config: BuildConfig.load(rootDir: root.path),
        cache: BuildCache(rootDir: root.path),
        notice: BuildNotice(),
      );
      final target = _HostFixtureTarget(triple);
      final first = await builder.build(target, 'synthetic-core-sha');
      expect(first.rebuilt, isTrue);
      expect(Directory('${crate.path}/target').existsSync(), isFalse);
      final overridden = Platform.environment['CARGO_TARGET_DIR'];
      expect(overridden, isNotNull);
      expect(Directory(overridden!).existsSync(), isFalse);
      final executed = await Process.run(first.primaryOutput, []);
      expect(executed.exitCode, 0);
      expect(executed.stdout, 'synthetic-core-sha\n');
      expect(
        (await builder.build(target, 'synthetic-core-sha')).rebuilt,
        isFalse,
      );
      final cache = Directory('${root.path}/.dart_tool/setup_build_cache');
      expect(
        cache.listSync().where((item) => item.path.contains('generation-')),
        isEmpty,
      );
    },
    skip:
        !Platform.isMacOS ||
        Platform.environment['FLCLASH_HELPER_CARGO_FIXTURE'] != '1',
  );
}
