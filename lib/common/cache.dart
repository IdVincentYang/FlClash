import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

extension CacheManagerExt on CacheManager {
  Stream<FileInfo> getFileStreamV2(
    String url, {
    String? key,
    Map<String, String>? headers,
    FutureOr<void> Function()? onRemoteNewLoaded,
  }) {
    final cacheKey = key ?? url;
    RequestSession? session;
    var cancelled = false;
    final controller = StreamController<FileInfo>(
      onCancel: () {
        cancelled = true;
        session?.close();
      },
    );
    Future<void> load() async {
      try {
        final cached = await getFileFromCache(cacheKey);
        if (cancelled) return;
        if (cached != null) controller.add(cached);
        if (cached != null && cached.validTill.isAfter(DateTime.now())) return;
        final current = await request.begin(
          key: 'icon:$cacheKey',
          url: url,
          automatic: true,
        );
        session = current;
        if (cancelled) {
          current.close();
          return;
        }
        final response = await current.dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes, headers: headers),
          cancelToken: current.cancelToken,
        );
        final file = await current.commit(() async {
          final file = await putFile(
            url,
            Uint8List.fromList(response.data ?? []),
            key: cacheKey,
            maxAge: const Duration(days: 7),
          );
          if (cached == null) await onRemoteNewLoaded?.call();
          return file;
        });
        if (!cancelled && await current.lifecycleCurrent()) {
          controller.add(
            FileInfo(
              file,
              FileSource.Online,
              DateTime.now().add(const Duration(days: 7)),
              url,
            ),
          );
        }
      } catch (_) {
        if (!cancelled && await getFileFromCache(cacheKey) == null) {
          controller.addError(const RequestUnavailable('request_blocked'));
        }
      } finally {
        session?.close();
        if (!controller.isClosed) await controller.close();
      }
    }

    unawaited(load());
    return controller.stream;
  }
}
