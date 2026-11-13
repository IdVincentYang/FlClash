import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/connection_exits.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final exitCacheDatabaseProvider = Provider<ExitCacheDatabase>((ref) {
  final database = ExitCacheDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

Future<void> cleanExitCache(ExitCacheDatabase database) async {
  try {
    await database.cleanExpired(DateTime.now().toUtc());
  } catch (_) {
    commonPrint.log('Exit cache cleanup failed');
  }
}
