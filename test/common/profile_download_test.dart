import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Native extends Mock implements Service {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late ProviderContainer container;
  late Request client;
  final finished = <String>[];

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('bounded-profile-');
    AppPath.temporaryDirectory = () async => root;
    AppPath.supportDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
    globalState.packageInfo = PackageInfo(
      appName: 'fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
    );
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    finished.clear();
    server.listen((request) async {
      try {
        if (request.uri.path == '/headers') {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        } else if (request.uri.path == '/drip') {
          for (var i = 0; i < 20; i++) {
            request.response.add([1]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        } else if (request.uri.path == '/gzip') {
          final encoded = gzip.encode(List.filled(4096, 1));
          request.response.headers.set(
            HttpHeaders.contentEncodingHeader,
            'gzip',
          );
          request.response.contentLength = encoded.length;
          request.response.add(encoded);
        } else if (request.uri.path == '/declared') {
          request.response.contentLength = 4096;
          request.response.add(List.filled(4096, 1));
        } else if (request.uri.path == '/broken') {
          request.response.contentLength = 4096;
          request.response.add([1, 2, 3]);
          await request.response.flush();
          (await request.response.detachSocket()).destroy();
        } else {
          request.response.add(List.filled(4096, 1));
        }
        await request.response.close();
      } catch (_) {
      } finally {
        finished.add(request.uri.path);
      }
    });
    container = ProviderContainer();
    client = Request.scoped(native: _Native(), isAndroid: false);
    client.attach(container);
    await client.ready();
  });
  tearDown(() async {
    await client.detach();
    container.dispose();
    await server.close(force: true);
    await for (final entry in root.list()) {
      await entry.delete(recursive: true);
    }
  });

  Future<void> download(
    String name, {
    int limit = 1024,
    Duration deadline = const Duration(seconds: 1),
  }) async {
    final url = 'http://127.0.0.1:${server.port}/$name';
    final session = await client.begin(key: 'profile:fixture', url: url);
    try {
      final response = await session.run(
        () =>
            client.downloadFileForUrl(url, maxBytes: limit, deadline: deadline),
      );
      await response.file.close();
    } finally {
      session.close();
    }
  }

  for (final name in ['chunked', 'gzip', 'declared']) {
    test(
      '$name enforces actual decompressed written byte limit and removes temporary files',
      () async {
        await expectLater(
          download(name),
          throwsA(
            isA<RequestUnavailable>().having(
              (e) => e.code,
              'code',
              'profile_download_too_large',
            ),
          ),
        );
        expect(
          await root
              .list(recursive: true)
              .where((entry) => entry is File)
              .toList(),
          isEmpty,
        );
      },
    );
  }
  for (final name in ['headers', 'drip']) {
    test('$name is canceled at the whole HTTP deadline', () async {
      final watch = Stopwatch()..start();
      await expectLater(
        download(name, deadline: const Duration(milliseconds: 120)),
        throwsA(
          isA<RequestUnavailable>().having(
            (e) => e.code,
            'code',
            'profile_download_timeout',
          ),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty,
      );
    });
  }
  test('interrupted body fails without keeping a partial file', () async {
    await expectLater(
      download('broken', limit: 8192),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(
      await root.list(recursive: true).where((entry) => entry is File).toList(),
      isEmpty,
    );
  });
  test(
    'successful streaming download and legacy bytes consumer both use the bounded primitive',
    () async {
      await download('chunked', limit: 8192);
      final url = 'http://127.0.0.1:${server.port}/chunked';
      final session = await client.begin(key: 'profile:legacy', url: url);
      try {
        expect(
          (await session.run(
            () => client.getFileResponseForUrl(url),
          )).data?.length,
          4096,
        );
      } finally {
        session.close();
      }
      expect(
        await root
            .list(recursive: true)
            .where((entry) => entry is File)
            .toList(),
        isEmpty,
      );
    },
  );
}
