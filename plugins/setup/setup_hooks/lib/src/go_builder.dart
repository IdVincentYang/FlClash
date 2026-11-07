import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'build.dart';
import 'build_cache.dart';
import 'error.dart';
import 'fingerprint.dart';
import 'options.dart';
import 'source_restore.dart';
import 'target.dart';
import 'util.dart';

class GoBuilder {
  GoBuilder({
    required this.rootDir,
    required this.config,
    required this.cache,
    required this.notice,
    this.harnessInputs = const [],
    this.androidToolchain,
  });

  final String rootDir;
  final BuildConfig config;
  final BuildCache cache;
  final BuildNotice notice;
  final List<String> harnessInputs;
  final AndroidToolchain? androidToolchain;

  String get _corePath => p.join(rootDir, config.coreDir);
  String get _outputPath => p.join(rootDir, config.outputDir);

  String _resolveCc(Target target) {
    final toolchain = androidToolchain;
    if (toolchain == null) {
      throw BuildException('Android target $target needs an NDK toolchain');
    }
    final cc = toolchain.clangFor(target);
    if (!File(cc).existsSync()) {
      throw BuildException(
        'NDK compiler not found: $cc (API ${toolchain.apiLevel} from the '
        'app minSdk; the NDK Flutter selected may be too old)',
      );
    }
    return cc;
  }

  Future<BuildExecution> build(Target target) async {
    final sourceInputs = requestCoreSourceInputs(rootDir);
    final outDir = target.isLib
        ? p.join(_outputPath, target.platformDir, target.abi!)
        : p.join(_outputPath, target.platformDir);

    final fileName = target.isLib
        ? '${config.libName}.so'
        : '${config.coreName}${target.executableExtension}';
    final outFile = p.join(outDir, fileName);

    final includesPath = p.join(
      _outputPath,
      target.platformDir,
      'includes',
      target.abi ?? '',
    );
    final mainPath = p.join(rootDir, 'android/core/src/main');
    final cppIncludesPath = p.join(mainPath, 'cpp/includes', target.abi ?? '');
    final jniOutput = p.join(mainPath, 'jniLibs', target.abi ?? '', fileName);
    final staticHeaders = target.isLib
        ? Directory(_corePath)
              .listSync(followLinks: false)
              .where((file) => file.path.endsWith('.h'))
              .map((file) => file.path)
              .toList()
        : <String>[];
    final generatedHeader = '${p.basenameWithoutExtension(fileName)}.h';
    final headerNames = [generatedHeader, ...staticHeaders.map(p.basename)];
    if (target.isLib && headerNames.toSet().length != headerNames.length) {
      throw BuildException('Conflicting generated and source header names');
    }
    final outputs = <String>[
      outFile,
      if (target.isLib) ...[
        jniOutput,
        for (final name in headerNames) ...[
          p.join(includesPath, name),
          p.join(cppIncludesPath, name),
        ],
      ],
    ];
    return cache.run(
      key: '${target.platformDir}-${target.goarch}-core',
      fingerprint: () => _calculateFingerprint(target, sourceInputs),
      primaryOutput: outFile,
      outputs: outputs,
      outputDirectories: target.isLib ? [includesPath, cppIncludesPath] : [],
      notice: notice,
      build: (staging) async {
        final staged = p.join(staging.work.path, fileName);
        await runCommandStream(
          'go',
          _buildArguments(target, outFile: staged),
          workingDirectory: _corePath,
          environment: _buildEnvironment(target),
        );
        _stageCopy(staged, staging.file(outFile));
        if (target.isLib) {
          _stageCopy(staged, staging.file(jniOutput));
          for (final source in [
            p.join(p.dirname(staged), generatedHeader),
            ...staticHeaders,
          ]) {
            for (final directory in [includesPath, cppIncludesPath]) {
              _stageCopy(
                source,
                staging.file(p.join(directory, p.basename(source))),
              );
            }
          }
        }
      },
    );
  }

  void _stageCopy(String source, File destination) {
    if (FileSystemEntity.typeSync(source, followLinks: false) !=
        FileSystemEntityType.file) {
      throw BuildException('Expected a regular generated output: $source');
    }
    File(source).copySync(destination.path);
  }

  Map<String, String> _buildEnvironment(Target target) {
    final env = <String, String>{'GOOS': target.goos, 'GOARCH': target.goarch};
    if (target.isLib) {
      env
        ..['CGO_ENABLED'] = '1'
        ..['CC'] = _resolveCc(target)
        ..['CFLAGS'] = '-O3 -Werror';
    } else {
      env['CGO_ENABLED'] = '0';
    }
    return env;
  }

  // Android keeps local crash-debugging symbols; AGP strips the packaged copy.
  String _ldflags(Target target) => target.isLib
      ? config.goLdflags
            .split(' ')
            .where((flag) => flag != '-s' && flag != '-w')
            .join(' ')
      : config.goLdflags;

  List<String> _buildArguments(Target target, {String? outFile}) => [
    'build',
    '-ldflags=${_ldflags(target)}',
    '-tags=${config.tagsFor(target)}',
    if (target.isLib) '-buildmode=c-shared',
    if (outFile != null) ...['-o', outFile],
  ];

  Future<Fingerprint> _calculateFingerprint(
    Target target,
    List<String> sourceInputs,
  ) async {
    final env = _buildEnvironment(target);
    final builder = FingerprintBuilder(rootDir: rootDir)
      ..addValue('cache_schema', BuildCache.schemaVersion)
      ..addValue('kind', 'go-core')
      ..addValue('target', {
        'goos': target.goos,
        'goarch': target.goarch,
        'abi': target.abi,
      })
      ..addValue('config', config.toFingerprintMap())
      ..addValue('environment', env)
      ..addValue('arguments', _buildArguments(target));

    final goEnvResult = runCommand(
      'go',
      [
        'env',
        '-json',
        'GOVERSION',
        'GOTOOLCHAIN',
        'GOFLAGS',
        'GOEXPERIMENT',
        'GOAMD64',
        'GOARM',
        'GO386',
        'GOMIPS',
        'GOMIPS64',
        'CGO_CFLAGS',
        'CGO_CPPFLAGS',
        'CGO_CXXFLAGS',
        'CGO_LDFLAGS',
        'GOWORK',
        'GOENV',
      ],
      workingDirectory: _corePath,
      environment: env,
    );
    final goEnv = jsonDecode((goEnvResult.stdout as String).trim());
    builder.addValue('go_env', goEnv);

    final inputs = _resolveGoInputs(target, env);
    final configuration = p.join(rootDir, 'build_config.yaml');
    builder.addOptionalFile(configuration);
    final goWork = (goEnv as Map<String, dynamic>)['GOWORK'];
    if (goWork is String && goWork.isNotEmpty && goWork != 'off') {
      inputs.add(goWork);
      final goWorkSum = p.join(p.dirname(goWork), 'go.work.sum');
      if (File(goWorkSum).existsSync()) inputs.add(goWorkSum);
    }
    inputs.addAll(harnessInputs);
    inputs.addAll(sourceInputs);

    if (target.isLib) {
      final compilerVersion = runCommand(env['CC']!, ['--version']);
      builder.addValue(
        'android_compiler',
        '${(compilerVersion.stdout as String).trim()}\n'
            '${(compilerVersion.stderr as String).trim()}',
      );
    }

    builder.addFiles([...inputs, resolveToolExecutable('go')]);
    return builder.finishWithInputs();
  }

  Set<String> _resolveGoInputs(Target target, Map<String, String> environment) {
    const template =
        r'''{{range .GoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CgoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CXXFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .MFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .HFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .FFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SwigFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SwigCXXFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SysoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .EmbedFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{with .Module}}{{if .GoMod}}{{.GoMod}}{{"\n"}}{{end}}{{end}}''';
    final result = runCommand(
      'go',
      ['list', '-deps', '-tags=${config.tagsFor(target)}', '-f', template, '.'],
      workingDirectory: _corePath,
      environment: environment,
    );
    final inputs = <String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final filePath = p.normalize(
        p.absolute(p.isAbsolute(value) ? value : p.join(_corePath, value)),
      );
      inputs.add(filePath);
      if (p.basename(filePath) == 'go.mod') {
        final goSum = p.join(p.dirname(filePath), 'go.sum');
        if (File(goSum).existsSync()) inputs.add(goSum);
      }
    }

    for (final name in const ['go.mod', 'go.sum']) {
      final filePath = p.join(_corePath, name);
      if (File(filePath).existsSync()) inputs.add(filePath);
    }
    return inputs;
  }
}
