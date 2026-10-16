import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/models/managed_policy.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', help: 'Local policy JSON file.')
    ..addOption('output', help: 'Local generated YAML file.')
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final args = parser.parse(arguments);
    if (args['help'] as bool) {
      stdout.writeln(parser.usage);
      return;
    }
    if (args.rest.isNotEmpty ||
        args['input'] == null ||
        args['output'] == null) {
      throw const FormatException(
        'arguments: --input and --output are required',
      );
    }
    final text = await File(args['input'] as String).readAsString();
    final Object? input;
    try {
      input = jsonDecode(text);
    } on FormatException {
      throw const FormatException('input: invalid UTF-8 JSON');
    }
    final yaml = compileManagedProfile(ManagedPolicy.fromJson(input));
    await writeManagedProfile(args['output'] as String, yaml);
    stdout.writeln('Configuration written.');
  } on FormatException catch (error) {
    stderr.writeln(
      error.source == null ? error.message : 'input: invalid format',
    );
    exitCode = 65;
  } on IOException {
    stderr.writeln('input/output: local file operation failed');
    exitCode = 74;
  }
}

Future<void> writeManagedProfile(String destination, String yaml) async {
  if (!Platform.isMacOS && !Platform.isLinux) {
    throw const FormatException(
      'output: this command requires a macOS or Linux host',
    );
  }
  final target = File(destination).absolute;
  final temporary = await target.parent.createTemp('.managed-profile-');
  try {
    await _restrictPermissions(temporary);
    final output = await File(
      '${temporary.path}/config.yaml',
    ).create(exclusive: true);
    await _restrictPermissions(output);
    await output.writeAsString(yaml, flush: true);
    await output.rename(target.path);
  } finally {
    try {
      await temporary.delete(recursive: true);
    } on FileSystemException {
      // Rename commits the output; later cleanup cannot make that a failed write.
    }
  }
}

Future<void> _restrictPermissions(FileSystemEntity entity) async {
  // Inherited macOS ACL entries can grant access beyond the BSD mode bits.
  if (Platform.isMacOS) {
    final acl = await Process.run('/bin/chmod', ['-N', entity.path]);
    if (acl.exitCode != 0) {
      throw const FileSystemException('private output ACL unavailable');
    }
  }
  final directory = entity is Directory;
  final permissions = await Process.run('/bin/chmod', [
    directory ? '700' : '600',
    entity.path,
  ]);
  if (permissions.exitCode != 0 ||
      (await entity.stat()).mode & 0x1ff != (directory ? 0x1c0 : 0x180)) {
    throw const FileSystemException('private output permissions unavailable');
  }
}
