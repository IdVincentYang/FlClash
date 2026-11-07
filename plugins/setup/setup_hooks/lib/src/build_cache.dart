import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'error.dart';
import 'fingerprint.dart';

final _log = Logger('build_cache');

class BuildExecution {
  const BuildExecution({
    required this.primaryOutput,
    required this.rebuilt,
    this.inputs = const [],
    this.outputs = const [],
  });

  final String primaryOutput;
  final bool rebuilt;
  final List<String> inputs;
  final List<String> outputs;
}

class BuildNotice {
  void show({required String key, required String reason}) {
    _log.warning('Rebuilding $key: $reason');
  }
}

class BuildStaging {
  BuildStaging._(this._cache, this._directory, this._outputs);

  final BuildCache _cache;
  final Directory _directory;
  final Set<String> _outputs;
  bool _active = true;

  void _ensureActive() {
    if (!_active || !_cache._scope!.active) {
      throw StateError('Output producer has ended');
    }
  }

  Directory get work {
    _ensureActive();
    return Directory(p.join(_directory.path, 'work'))..createSync();
  }

  File file(String destination) {
    _ensureActive();
    final relative = _cache._outputPath(destination);
    if (!_outputs.contains(relative)) {
      throw BuildException('Undeclared staged output: $relative');
    }
    final result = File(p.join(_directory.path, 'outputs', relative));
    result.parent.createSync(recursive: true);
    return result;
  }
}

class BuildCache {
  BuildCache({required String rootDir})
    : rootDir = Directory(rootDir).resolveSymbolicLinksSync(),
      _requestedRoot = p.normalize(p.absolute(rootDir)),
      _scope = null;

  BuildCache._scoped(this.rootDir, this._requestedRoot, this._scope);

  static const int schemaVersion = 2;
  static final Map<String, _AsyncLock> _processLocks = {};

  final String rootDir;
  final String _requestedRoot;
  final _OutputScope? _scope;

  String get _namespace => p.join(rootDir, '.dart_tool', 'setup_build_cache');
  String get cacheDir => p.join(_namespace, 'v$schemaVersion');

  /// The scoped cache retains backups until the complete producer group succeeds.
  Future<T> transaction<T>(Future<T> Function(BuildCache cache) action) async {
    if (_scope != null) {
      if (!_scope.active || _scope.recoveryFailed) {
        throw StateError('Output transaction has ended');
      }
      return action(this);
    }
    _directory(_namespace);
    return _processLocks.putIfAbsent(rootDir, _AsyncLock.new).synchronized(
      () async {
        final lockPath = p.join(_namespace, 'outputs.lock');
        _checkAncestors(lockPath);
        _requireType(lockPath, FileSystemEntityType.file, missing: true);
        final lock = await File(lockPath).open(mode: FileMode.append);
        try {
          await lock.lock(FileLock.blockingExclusive);
          try {
            if (Directory(_namespace).listSync().any(
              (entry) => p.basename(entry.path).startsWith('generation-'),
            )) {
              throw BuildException(
                'Unfinished output generation retained; use a fresh owned workspace',
              );
            }
            final directory = Directory(
              _namespace,
            ).createTempSync('generation-');
            final scope = _OutputScope(directory);
            try {
              final result = await action(
                BuildCache._scoped(rootDir, _requestedRoot, scope),
              );
              if (scope.recoveryFailed) {
                throw StateError('Output transaction requires recovery');
              }
              scope.committed = true;
              return result;
            } catch (error, stack) {
              try {
                scope.rollback();
              } catch (_) {
                scope.recoveryFailed = true;
                throw BuildException(
                  'Output rollback failed; retain ${directory.path}',
                );
              }
              Error.throwWithStackTrace(error, stack);
            } finally {
              scope.active = false;
              if (!scope.recoveryFailed) {
                try {
                  directory.deleteSync(recursive: true);
                } on FileSystemException {
                  _log.warning('Retained output generation: ${directory.path}');
                }
              }
            }
          } finally {
            await lock.unlock();
          }
        } finally {
          await lock.close();
        }
      },
    );
  }

  Future<BuildExecution> run({
    required String key,
    required Future<Fingerprint> Function() fingerprint,
    required String primaryOutput,
    required List<String> outputs,
    List<String> outputDirectories = const [],
    required Future<void> Function(BuildStaging staging) build,
    required BuildNotice notice,
  }) => transaction((cache) async {
    final scope = cache._scope!;
    final start = scope.undo.length;
    try {
      return await cache._run(
        key: key,
        fingerprint: fingerprint,
        primaryOutput: primaryOutput,
        outputs: outputs,
        outputDirectories: outputDirectories,
        build: build,
        notice: notice,
      );
    } catch (error, stack) {
      try {
        scope.rollback(start);
      } catch (_) {
        scope.recoveryFailed = true;
        throw BuildException(
          'Output recovery failed; retain ${scope.directory.path}',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  });

  Future<BuildExecution> _run({
    required String key,
    required Future<Fingerprint> Function() fingerprint,
    required String primaryOutput,
    required List<String> outputs,
    required List<String> outputDirectories,
    required Future<void> Function(BuildStaging staging) build,
    required BuildNotice notice,
  }) async {
    final expected = outputs.map(_outputPath).toList()..sort();
    final directories = outputDirectories.map(_outputPath).toList()..sort();
    final primary = _outputPath(primaryOutput);
    if (expected.isEmpty ||
        expected.toSet().length != expected.length ||
        !expected.contains(primary) ||
        directories.toSet().length != directories.length) {
      throw BuildException('Invalid producer output plan');
    }
    for (final directory in directories) {
      if (directories.any(
            (other) => other != directory && p.isWithin(other, directory),
          ) ||
          expected.contains(directory) ||
          !expected.any((path) => p.isWithin(directory, path))) {
        throw BuildException('Invalid producer directory plan');
      }
    }
    final current = await fingerprint();
    _directory(cacheDir);
    final record = File(
      p.join(cacheDir, '${sha256.convert(utf8.encode(key))}.json'),
    );
    final miss = _missReason(record, key, current.hash, expected, directories);
    if (miss == null) {
      _log.info('Cache hit: $key');
      return BuildExecution(
        primaryOutput: primaryOutput,
        rebuilt: false,
        inputs: current.inputs,
        outputs: [for (final path in expected) p.join(rootDir, path)],
      );
    }
    notice.show(key: key, reason: miss);
    final stage = Directory(_scope!.directory.path).createTempSync('build-');
    final staging = BuildStaging._(this, stage, expected.toSet());
    try {
      await build(staging);
    } finally {
      staging._active = false;
    }
    final after = await fingerprint();
    if (after.hash != current.hash) {
      throw BuildException('Build inputs changed during production');
    }
    final outputRoot = p.join(stage.path, 'outputs');
    _checkSet(outputRoot, expected);
    final metadata = [for (final path in expected) _metadata(outputRoot, path)];
    final units = <String>[
      ...directories,
      ...expected.where(
        (path) => !directories.any((dir) => p.isWithin(dir, path)),
      ),
    ]..sort();
    for (final unit in units) {
      _install(
        p.join(outputRoot, unit),
        p.join(rootDir, unit),
        directory: directories.contains(unit),
      );
    }
    final candidate = File(p.join(stage.path, 'record.json'));
    candidate.writeAsStringSync(
      jsonEncode({
        'schema': schemaVersion,
        'key': key,
        'fingerprint': current.hash,
        'directories': directories,
        'outputs': metadata,
      }),
      flush: true,
    );
    _install(candidate.path, record.path);
    return BuildExecution(
      primaryOutput: primaryOutput,
      rebuilt: true,
      inputs: current.inputs,
      outputs: [for (final path in expected) p.join(rootDir, path)],
    );
  }

  void writeFile(String destination, String content) {
    destination = _absolutePath(destination);
    if (_scope == null || !_scope.active || _scope.recoveryFailed) {
      throw StateError('Output write needs an active transaction');
    }
    _outputPath(destination);
    _checkAncestors(destination);
    _requireType(destination, FileSystemEntityType.file, missing: true);
    if (File(destination).existsSync() &&
        File(destination).readAsStringSync() == content) {
      return;
    }
    final staged = File(
      p.join(_scope.directory.path, 'data-${_scope.undo.length}'),
    )..writeAsStringSync(content, flush: true);
    _install(staged.path, destination);
  }

  String? _missReason(
    File record,
    String key,
    String fingerprint,
    List<String> expected,
    List<String> directories,
  ) {
    try {
      _checkAncestors(record.path);
      _requireType(record.path, FileSystemEntityType.file);
      final data = jsonDecode(record.readAsStringSync());
      if (data is! Map ||
          data.length != 5 ||
          data['schema'] != schemaVersion ||
          data['key'] != key ||
          data['fingerprint'] != fingerprint ||
          jsonEncode(data['directories']) != jsonEncode(directories)) {
        return 'build identity changed';
      }
      final entries = data['outputs'];
      if (entries is! List || entries.length != expected.length) {
        return 'output plan changed';
      }
      for (var i = 0; i < expected.length; i++) {
        if (jsonEncode(entries[i]) !=
            jsonEncode(_metadata(rootDir, expected[i]))) {
          return 'output content changed';
        }
      }
      for (final dir in directories) {
        _checkSet(
          p.join(rootDir, dir),
          expected
              .where((path) => p.isWithin(dir, path))
              .map((path) => p.relative(path, from: dir))
              .toList(),
        );
      }
      return null;
    } on FormatException {
      return 'invalid cache record';
    } on FileSystemException {
      return 'cached output is unavailable';
    } on BuildException {
      return 'cached output identity is unavailable';
    }
  }

  Map<String, Object> _metadata(String root, String relative) {
    final path = p.join(root, relative);
    _checkAncestors(path);
    _requireType(path, FileSystemEntityType.file);
    final file = File(path);
    final size = file.lengthSync();
    if (size <= 0) throw BuildException('Empty output: $relative');
    return {
      'path': relative,
      'size': size,
      'sha256': sha256.convert(file.readAsBytesSync()).toString(),
    };
  }

  void _checkSet(String root, List<String> expected) {
    _checkAncestors(root);
    _requireType(root, FileSystemEntityType.directory);
    final actual = <String>[];
    for (final entry in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        actual.add(p.relative(entry.path, from: root));
      } else if (type != FileSystemEntityType.directory) {
        throw BuildException('Output contains a link or special file');
      } else if (!expected.any(
        (path) => p.isWithin(p.relative(entry.path, from: root), path),
      )) {
        throw BuildException('Unexpected output directory');
      }
    }
    actual.sort();
    final sorted = [...expected]..sort();
    if (jsonEncode(actual) != jsonEncode(sorted)) {
      throw BuildException('Output set differs from producer plan');
    }
  }

  void _install(String staged, String destination, {bool directory = false}) {
    _checkAncestors(destination);
    _directory(p.dirname(destination));
    final kind = directory
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    _requireType(destination, kind, missing: true);
    final scope = _scope!;
    final old = FileSystemEntity.typeSync(destination, followLinks: false);
    final backup = old == FileSystemEntityType.notFound
        ? null
        : p.join(scope.directory.path, 'backup-${scope.undo.length}');
    if (directory && old != FileSystemEntityType.notFound) {
      for (final entry in Directory(
        destination,
      ).listSync(recursive: true, followLinks: false)) {
        if (entry is! File && entry is! Directory) {
          throw BuildException('Owned output directory contains a link');
        }
      }
    }
    if (backup != null) _entity(destination, directory).renameSync(backup);
    scope.undo.add(_Undo(destination, backup, directory));
    _entity(staged, directory).renameSync(destination);
  }

  String _absolutePath(String path) {
    final absolute = p.normalize(p.absolute(path));
    if (p.equals(_requestedRoot, absolute)) return rootDir;
    if (p.isWithin(_requestedRoot, absolute)) {
      return p.join(rootDir, p.relative(absolute, from: _requestedRoot));
    }
    return absolute;
  }

  String _outputPath(String path) {
    if (p.split(path).contains('..')) {
      throw BuildException('Output path contains parent traversal');
    }
    final absolute = _absolutePath(path);
    if (!p.isWithin(rootDir, absolute) ||
        p.equals(absolute, _namespace) ||
        p.isWithin(_namespace, absolute)) {
      throw BuildException('Output is outside the producer namespace');
    }
    _checkAncestors(absolute);
    return p.relative(absolute, from: rootDir);
  }

  void _checkAncestors(String path) {
    if (p.equals(rootDir, path)) return;
    if (!p.isWithin(rootDir, p.normalize(p.absolute(path)))) {
      throw BuildException('Path leaves build root');
    }
    var current = rootDir;
    final parts = p.split(p.relative(path, from: rootDir));
    for (final part in parts.take(parts.length - 1)) {
      current = p.join(current, part);
      _requireType(current, FileSystemEntityType.directory, missing: true);
    }
  }

  void _directory(String path) {
    _checkAncestors(path);
    _requireType(path, FileSystemEntityType.directory, missing: true);
    Directory(path).createSync(recursive: true);
  }

  void _requireType(
    String path,
    FileSystemEntityType expected, {
    bool missing = false,
  }) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != expected &&
        !(missing && type == FileSystemEntityType.notFound)) {
      throw BuildException('Unexpected output path type: $path');
    }
  }
}

FileSystemEntity _entity(String path, bool directory) =>
    directory ? Directory(path) : File(path);

class _Undo {
  _Undo(this.destination, this.backup, this.directory);
  final String destination;
  final String? backup;
  final bool directory;
}

class _OutputScope {
  _OutputScope(this.directory);
  final Directory directory;
  final List<_Undo> undo = [];
  bool active = true;
  bool committed = false;
  bool recoveryFailed = false;

  void rollback([int start = 0]) {
    if (committed) return;
    while (undo.length > start) {
      final operation = undo.last;
      final target = _entity(operation.destination, operation.directory);
      if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        target.deleteSync(recursive: operation.directory);
      }
      if (operation.backup != null) {
        _entity(operation.backup!, operation.directory).renameSync(target.path);
      }
      undo.removeLast();
    }
  }
}

class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}
