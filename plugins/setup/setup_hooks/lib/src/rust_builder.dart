import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'build_cache.dart';
import 'fingerprint.dart';
import 'options.dart';
import 'target.dart';
import 'util.dart';

final _log = Logger('rust_builder');

class RustBuilder {
  RustBuilder({
    required this.rootDir,
    required this.config,
    required this.cache,
    required this.notice,
    this.harnessInputs = const [],
  });

  final String rootDir;
  final BuildConfig config;
  final BuildCache cache;
  final BuildNotice notice;
  final List<String> harnessInputs;

  String get _helperPath => p.join(rootDir, config.helperDir);
  String get _outputPath => p.join(rootDir, config.outputDir);

  Future<BuildExecution> build(Target target, String coreSha256) async {
    final triple = target.rustTriple;
    final args = [
      'build',
      '--target',
      triple,
      if (target.goos == 'windows') ...['--features', 'windows-service'],
      '--release',
    ];
    final env = {
      'CORE_SHA256': coreSha256,
      'CORE_NAME': '${config.coreName}${target.executableExtension}',
    };

    final destDir = p.join(_outputPath, target.platformDir);
    final destPath = p.join(
      destDir,
      '${config.helperName}${target.executableExtension}',
    );
    return cache.run(
      key: '${target.platformDir}-${target.goarch}-helper-release',
      fingerprint: () => _calculateFingerprint(
        target: target,
        coreSha256: coreSha256,
        args: args,
      ),
      primaryOutput: destPath,
      outputs: [destPath],
      notice: notice,
      build: (staging) async {
        _log.info('Building Rust helper: $target');
        final targetDirectory = p.join(staging.work.path, 'cargo-target');

        await runCommandStream(
          'cargo',
          [...args, '--target-dir', targetDirectory],
          workingDirectory: _helperPath,
          environment: env,
        );

        final srcPath = p.join(
          targetDirectory,
          triple,
          'release',
          'helper${target.executableExtension}',
        );
        if (FileSystemEntity.typeSync(srcPath, followLinks: false) !=
            FileSystemEntityType.file) {
          throw StateError('Expected regular Helper output');
        }
        File(srcPath).copySync(staging.file(destPath).path);

        _log.info('Built: $destPath');
      },
    );
  }

  Future<Fingerprint> _calculateFingerprint({
    required Target target,
    required String coreSha256,
    required List<String> args,
  }) async {
    final builder = FingerprintBuilder(rootDir: rootDir)
      ..addValue('cache_schema', BuildCache.schemaVersion)
      ..addValue('kind', 'helper')
      ..addValue('target', {'goos': target.goos, 'goarch': target.goarch})
      ..addValue('arguments', args)
      ..addValue('cargo_target_directory', 'private-generation')
      ..addValue('core_sha256', coreSha256)
      ..addValue('environment', _rustEnvironment())
      ..addValue('config', config.toFingerprintMap());

    final cargoVersion = runCommand('cargo', [
      '--version',
    ], workingDirectory: _helperPath);
    builder.addValue('cargo_version', (cargoVersion.stdout as String).trim());
    final rustVersion = runCommand('rustc', [
      '-Vv',
    ], workingDirectory: _helperPath);
    builder.addValue('rustc_version', (rustVersion.stdout as String).trim());

    final inputs = collectFiles(
      _helperPath,
      excludedDirectories: const {'target', '.git', '.idea'},
    )..addAll(harnessInputs);
    builder.addOptionalFile(p.join(rootDir, 'build_config.yaml'));
    builder.addFiles([
      ...inputs,
      resolveToolExecutable('cargo'),
      resolveToolExecutable('rustc'),
    ]);
    return builder.finishWithInputs();
  }

  Map<String, String> _rustEnvironment() {
    const exactKeys = {
      'CARGO_BUILD_TARGET',
      'CARGO_ENCODED_RUSTFLAGS',
      'RUSTFLAGS',
      'RUSTUP_TOOLCHAIN',
      'RUSTC_WRAPPER',
      'RUSTC_WORKSPACE_WRAPPER',
    };
    final values = <String, String>{};
    final entries = Platform.environment.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      if (exactKeys.contains(entry.key) ||
          entry.key.startsWith('CARGO_PROFILE_') ||
          entry.key.startsWith('CARGO_TARGET_')) {
        values[entry.key] = entry.value;
      }
    }
    return values;
  }
}
