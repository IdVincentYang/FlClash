import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:setup_hooks/setup_hooks.dart';

import '../../../tool/android_hook_environment.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final context = await enterManagedAndroidHook(
      arguments: args,
      hook: 'setup',
      packageRoot: input.packageRoot,
      selection: input.userDefines['flclash_android_environment'],
    );
    await CoreBuilder(
      onBuild: (report) async {
        if (context != null) {
          output.metadata['flclash_android_generated_outputs'] =
              await managedAndroidOutputIdentity(report.outputs);
        }
      },
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
