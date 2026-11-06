import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'android_hook_binding.dart';

const _childArgument = '--flclash-android-hook-child';

Future<({String digest, String inputDigest})?> enterManagedAndroidHook({
  required List<String> arguments,
  required String hook,
  required Uri packageRoot,
  required Object? selection,
}) async {
  const root = androidHookWorkspace;
  const digest = androidHookContextDigest;
  if (root == null || digest == null) {
    if (root != null ||
        digest != null ||
        selection != null ||
        arguments.contains(_childArgument) ||
        Platform.environment.containsKey('FLCLASH_ANDROID_PROFILE')) {
      throw StateError(
        'Managed Android hook has no compiled workspace binding',
      );
    }
    return null;
  }
  if (!const ['setup', 'rust_api'].contains(hook) ||
      !Platform.isMacOS ||
      packageRoot.toFilePath().replaceFirst(RegExp(r'/$'), '') !=
          '$root/source/plugins/$hook' ||
      Directory(root).resolveSymbolicLinksSync() != root ||
      Platform.resolvedExecutable !=
          '$root/flutter/bin/cache/dart-sdk/bin/dart') {
    throw StateError('Managed Android hook belongs to another workspace or VM');
  }
  const configPath = '$root/hook-environment.json';
  if (selection != configPath) {
    throw StateError('Missing or wrong managed Android hook selection');
  }
  final config = _ownedFile(root, configPath);
  if (config.lengthSync() > 4 * 1024 * 1024) {
    throw StateError('Excessive managed Android hook configuration');
  }
  final bytes = config.readAsBytesSync();
  if (sha256.convert(bytes).toString() != digest) {
    throw StateError('Managed Android hook configuration changed');
  }
  final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  if (data.keys.toSet().difference(const {
        'schema',
        'profile',
        'workspace',
        'source',
        'environment',
        'archives',
        'material_roots',
        'files',
      }).isNotEmpty ||
      data.length != 8 ||
      data['schema'] != 1 ||
      data['profile'] != 'macos_arm64_android_arm64_dev' ||
      data['workspace'] != root ||
      data['source'] != '$root/source') {
    throw StateError('Unsupported or stale managed Android hook context');
  }
  final environment = Map<String, String>.from(data['environment'] as Map);
  final files = Map<String, dynamic>.from(data['files'] as Map);
  for (final entry in files.entries) {
    final expected = Map<String, dynamic>.from(entry.value as Map);
    final file = _ownedFile(root, '$root/${entry.key}');
    if (file.lengthSync() != expected['size'] ||
        (await sha256.bind(file.openRead()).first).toString() !=
            expected['sha256']) {
      throw StateError('Managed Android hook source or configuration changed');
    }
  }
  final childCount = arguments.where((arg) => arg == _childArgument).length;
  final nativeArguments = arguments
      .where((arg) => arg != _childArgument)
      .toList();
  final inputDigest = _checkArguments(root, hook, nativeArguments, environment);
  if (childCount > 1) throw StateError('Repeated managed hook reentry');
  if (childCount == 0) {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--disable-dart-dev',
        '--packages=$root/source/.dart_tool/package_config.json',
        '$root/source/plugins/$hook/hook/build.dart',
        ...nativeArguments,
        _childArgument,
      ],
      workingDirectory: '$root/source/plugins/$hook',
      environment: environment,
      includeParentEnvironment: false,
    );
    final streams = Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    final result = await process.exitCode;
    await streams;
    await Future.wait([stdout.flush(), stderr.flush()]);
    exit(result);
  }
  final actualEnvironment = {...Platform.environment}
    ..remove('__CF_USER_TEXT_ENCODING');
  if (actualEnvironment.length != environment.length ||
      environment.entries.any(
        (entry) => actualEnvironment[entry.key] != entry.value,
      )) {
    throw StateError(
      'Managed hook reentry environment differs from current selection',
    );
  }
  final python = environment['FLCLASH_ANDROID_PYTHON'];
  if (python == null || !python.startsWith('/')) {
    throw StateError('Missing fixed bootstrap Python selection');
  }
  final checked = await Process.run(
    python,
    [
      '$root/source/tool/verify_android_inputs.py',
      '--check-hook-context',
      configPath,
      '--context-sha256',
      digest,
      '--hook',
      hook,
    ],
    workingDirectory: '$root/source',
    environment: environment,
    includeParentEnvironment: false,
  );
  if (checked.exitCode != 0) {
    stderr.write(checked.stdout);
    stderr.write(checked.stderr);
    throw StateError('Managed Android hook material recheck failed');
  }
  stdout.writeln('Managed Android $hook context=$digest inputs rechecked');
  return (digest: digest, inputDigest: inputDigest);
}

File _ownedFile(String root, String path) {
  if (!path.startsWith('$root/')) {
    throw StateError('Managed hook path is outside its workspace');
  }
  final parts = path.substring(root.length + 1).split('/');
  var current = root;
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty || part == '.' || part == '..' || part.contains(r'\')) {
      throw StateError('Noncanonical managed hook path');
    }
    current = '$current/$part';
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type !=
        (i == parts.length - 1
            ? FileSystemEntityType.file
            : FileSystemEntityType.directory)) {
      throw StateError('Managed hook input is missing or contains a link');
    }
  }
  return File(path);
}

String _checkArguments(
  String root,
  String hook,
  List<String> arguments,
  Map<String, String> environment,
) {
  if (arguments.isEmpty ||
      arguments.length > 2 ||
      !arguments.first.startsWith('--config=')) {
    throw StateError('Unexpected managed hook arguments');
  }
  final path = arguments.first.substring('--config='.length);
  final file = _ownedFile(root, path);
  final runner = '$root/source/.dart_tool/hooks_runner/$hook/';
  if (!path.startsWith(runner) ||
      path.substring(runner.length).split('/').length != 2 ||
      file.uri.pathSegments.last != 'input.json') {
    throw StateError(
      'Managed hook config belongs to another runner invocation',
    );
  }
  final inputBytes = file.readAsBytesSync();
  final input = jsonDecode(utf8.decode(inputBytes)) as Map<String, dynamic>;
  final config = input['config'] as Map<String, dynamic>;
  final code =
      (config['extensions'] as Map<String, dynamic>)['code_assets']
          as Map<String, dynamic>;
  final compiler = code['c_compiler'] as Map<String, dynamic>;
  final llvm =
      '${environment['FLCLASH_ANDROID_NDK']}/toolchains/llvm/prebuilt/darwin-x86_64';
  final defines =
      (input['user_defines'] as Map<String, dynamic>)['workspace_pubspec']
          as Map<String, dynamic>;
  final values = defines['defines'] as Map<String, dynamic>;
  if (config['build_asset_types'] is! List ||
      (config['build_asset_types'] as List).length != 1 ||
      (config['build_asset_types'] as List).single != 'code_assets/code' ||
      config['linking_enabled'] != true ||
      code['target_os'] != 'android' ||
      code['target_architecture'] != 'arm64' ||
      (code['android'] as Map)['target_ndk_api'] != 24 ||
      code['link_mode_preference'] != 'dynamic' ||
      compiler.length != 3 ||
      ![
        '$llvm/bin/clang',
        '$llvm/bin/aarch64-linux-android24-clang',
      ].contains(compiler['cc']) ||
      compiler['ar'] != '$llvm/bin/llvm-ar' ||
      compiler['ld'] != '$llvm/bin/ld.lld' ||
      defines['base_path'] != '$root/source/pubspec.yaml' ||
      values.length != 2 ||
      values['build_assets'] != true ||
      values['flclash_android_environment'] != '$root/hook-environment.json') {
    throw StateError(
      'Managed hook input changed target, compiler or enabled build',
    );
  }
  if (input['out_file'] != '${file.parent.path}/output.json' ||
      input['out_dir_shared'] is! String ||
      (input['out_dir_shared'] as String).replaceFirst(RegExp(r'/$'), '') !=
          '$root/source/.dart_tool/hooks_runner/shared/$hook/build') {
    throw StateError('Managed hook output belongs to another invocation');
  }
  if (arguments.length == 2 &&
      _ownedFile(root, arguments.last).parent.path != file.parent.path) {
    throw StateError('Managed hook resources belong to another invocation');
  }
  return sha256.convert(inputBytes).toString();
}

List<Uri> managedAndroidHookDependencies(String workspace) => [
  File('$workspace/hook-environment.json').uri,
  File('$workspace/source/tool/android_hook_binding.dart').uri,
  for (final entity in Directory('$workspace/source/tool').listSync())
    if (entity is File &&
        (entity.path.endsWith('/verify_android_inputs.py') ||
            RegExp(r'/android_[^/]+\.py$').hasMatch(entity.path)))
      entity.uri,
];
