import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import '../../../tool/android_hook_environment.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final context = await enterManagedAndroidHook(
      arguments: args,
      hook: 'rust_api',
      packageRoot: input.packageRoot,
      selection: input.userDefines['flclash_android_environment'],
    );
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoBuildArgs:
          Platform.environment.containsKey('FLCLASH_ANDROID_PROFILE')
          ? const ['--locked']
          : const [],
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
    if (context != null) {
      output.metadata['flclash_android_environment_sha256'] = context.digest;
      output.metadata['flclash_android_hook_input_sha256'] =
          context.inputDigest;
      output.dependencies.addAll(
        managedAndroidHookDependencies(
          Directory.fromUri(input.packageRoot).parent.parent.parent.path,
        ),
      );
    }
  });
}

// rquickjs runs bindgen on Android, which must load the NDK's libclang; Linux
// NDKs before r26 keep it under lib64, later ones and every macOS NDK under lib.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    if (Platform.environment.containsKey('FLCLASH_ANDROID_PROFILE')) {
      throw StateError('Flutter passed no managed Android C compiler');
    }
    return const {};
  }
  if (Platform.environment.containsKey('FLCLASH_ANDROID_PROFILE')) {
    final ndk = Platform.environment['FLCLASH_ANDROID_NDK'];
    if (Platform.environment['FLCLASH_ANDROID_PROFILE'] !=
            'macos_arm64_android_arm64_dev' ||
        ndk == null ||
        !ndk.startsWith('/') ||
        input.config.code.targetArchitecture != Architecture.arm64 ||
        input.config.code.android.targetNdkApi != 24) {
      throw StateError('Unsupported managed Android NDK selection');
    }
    final llvm = '$ndk/toolchains/llvm/prebuilt/darwin-x86_64';
    final archiver = input.config.code.cCompiler!.archiver;
    final linker = input.config.code.cCompiler!.linker;
    if (![
          '$llvm/bin/clang',
          '$llvm/bin/aarch64-linux-android24-clang',
        ].contains(compiler.toFilePath()) ||
        archiver.toFilePath() != '$llvm/bin/llvm-ar' ||
        linker.toFilePath() != '$llvm/bin/ld.lld' ||
        !File.fromUri(
          compiler,
        ).resolveSymbolicLinksSync().startsWith('$ndk/') ||
        !File.fromUri(
          archiver,
        ).resolveSymbolicLinksSync().startsWith('$ndk/') ||
        !File.fromUri(linker).resolveSymbolicLinksSync().startsWith('$ndk/') ||
        !File(
          '$llvm/lib/libclang.dylib',
        ).resolveSymbolicLinksSync().startsWith('$ndk/')) {
      throw StateError('Flutter passed an unaccepted Android C toolchain');
    }
    return {'LIBCLANG_PATH': '$llvm/lib'};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path};
    }
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64); the NDK Flutter '
    'passed cannot run bindgen for rquickjs',
  );
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}
