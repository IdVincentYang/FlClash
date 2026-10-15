import 'dart:io';

import 'package:fl_clash/common/common.dart';

class RequestFile {
  RequestFile._(this.directory, this.staged);
  final Directory directory;
  final File staged;
  bool _retain = false;

  static Future<RequestFile> stage(List<int> bytes) async {
    final directory = await Directory(
      await appPath.tempPath,
    ).createTemp('request-');
    final staged = File('${directory.path}/incoming');
    await staged.writeAsBytes(bytes, flush: true);
    return RequestFile._(directory, staged);
  }

  Future<T> replace<T>(String path, Future<T> Function() persist) async {
    final target = File(path);
    final backup = File('${directory.path}/previous');
    final incoming = File('$path.request-$uniqueId');
    final existed = await target.exists();
    if (existed) await target.copy(backup.path);
    await target.parent.create(recursive: true);
    var installed = false;
    try {
      await staged.copy(incoming.path);
      await incoming.rename(path);
      installed = true;
      return await persist();
    } catch (error, stack) {
      if (installed) {
        try {
          if (existed) {
            await backup.copy(incoming.path);
            await incoming.rename(path);
          } else {
            await target.delete();
          }
        } catch (_) {
          _retain = true;
          await (RequestSession.current?.owner ?? request).markPartialCommit();
          throw const RequestUnavailable('request_partial_commit');
        }
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (await incoming.exists()) await incoming.delete();
    }
  }

  Future<void> close() async {
    if (!_retain) await directory.safeDelete(recursive: true);
  }
}
