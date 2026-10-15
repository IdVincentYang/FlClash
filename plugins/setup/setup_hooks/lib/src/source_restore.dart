import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'error.dart';
import 'util.dart';

List<String> requestCoreSourceInputs(String rootDir) {
  if (!File(p.join(rootDir, '.gitmodules')).existsSync() &&
      !Directory(p.join(rootDir, 'core', 'Clash.Meta')).existsSync()) {
    return const [];
  }
  final script = p.join(rootDir, 'tool', 'restore_l1_t03_core.py');
  if (!File(script).existsSync()) {
    throw BuildException('Missing L1-T03 core source restoration script');
  }
  final result = runCommand(Platform.isWindows ? 'python' : 'python3', [
    script,
    '--check',
    '--root',
    rootDir,
  ], workingDirectory: rootDir);
  final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return (data['inputs'] as List).cast<String>();
}
