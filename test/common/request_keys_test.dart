import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/cache.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/request_versions.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Native implements Service {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void addListener(ServiceListener listener) {}
  @override
  void removeListener(ServiceListener listener) {}
}

class _Cache extends Mock implements CacheManager {}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
  });

  test(
    'completed sessions plateau and stale sources cannot regain identity',
    () async {
      final client = Request.scoped(native: _Native(), isAndroid: false);
      final source = await client.captureSource('retired');
      for (var i = 0; i < requestHistoryLimit * 2; i++) {
        final session = await client.begin(
          key: 'icon:$i',
          url: 'http://127.0.0.1/',
        );
        session.close();
        expect(
          client.retainedKeyCounts.total,
          lessThanOrEqualTo(requestHistoryLimit),
        );
      }
      expect(await client.sourceCurrent(source), isFalse);
      final reborn = await client.captureSource(source.key);
      expect(reborn.revision, greaterThan(source.revision + 1));
      expect(await client.sourceCurrent(source), isFalse);
      expect(await client.sourceCurrent(reborn), isTrue);
      await client.detach();
      expect(client.retainedKeyCounts.total, 0);
    },
  );

  test(
    'cancel during a begin precondition cannot become a new operation',
    () async {
      final client = Request.scoped(native: _Native(), isAndroid: false);
      final entered = Completer<void>();
      final gate = Completer<bool>();
      final pending = client.begin(
        key: 'waiting',
        url: 'http://127.0.0.1/',
        sourceIsCurrent: () {
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      );
      final rejected = expectLater(
        pending,
        throwsA(
          isA<RequestUnavailable>().having(
            (e) => e.code,
            'code',
            'request_cancelled',
          ),
        ),
      );
      await entered.future;
      client.cancelKey('waiting');
      gate.complete(true);
      await rejected;
      expect(client.retainedKeyCounts.total, client.retainedKeyCounts.cold);
    },
  );

  test('same-container reattachment revokes previous source tickets', () async {
    final client = Request.scoped(native: _Native(), isAndroid: false);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (var i = 0; i < 4; i++) {
      client.attach(container);
      final source = await client.captureSource('profile:1');
      await client.detach();
      client.attach(container);
      expect(await client.sourceCurrent(source), isFalse);
      await client.detach();
      expect(client.retainedKeyCounts.total, 0);
    }
  });

  test(
    'new begin replaces an older precondition wait without losing its pin',
    () async {
      final client = Request.scoped(native: _Native(), isAndroid: false);
      final entered = Completer<void>();
      final gate = Completer<bool>();
      final old = client.begin(
        key: 'overlap',
        url: 'http://127.0.0.1/',
        sourceIsCurrent: () {
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      );
      final rejected = expectLater(old, throwsA(isA<RequestUnavailable>()));
      await entered.future;
      final latest = client.begin(key: 'overlap', url: 'http://127.0.0.1/');
      gate.complete(true);
      await rejected;
      final session = await latest;
      expect(session.isActive, isTrue);
      await session.check();
      session.close();
      expect(client.retainedKeyCounts.total, client.retainedKeyCounts.cold);
    },
  );

  test(
    'cancellation remains effective at the final representable version',
    () async {
      final versions = RequestVersions(initialVersion: requestVersionLimit - 3);
      final client = Request.scoped(
        native: _Native(),
        isAndroid: false,
        versions: versions,
      );
      final session = await client.begin(key: 'last', url: 'http://127.0.0.1/');
      expect(session.cancellationGeneration, requestVersionLimit);
      client.cancelKey('last');
      expect(session.isActive, isFalse);
      expect(versions.exhausted, isTrue);
      await client.detach();
      expect(client.retainedKeyCounts.total, 0);
    },
  );

  test(
    'real icon consumer releases dynamic URL scopes and cancelled streams',
    () async {
      final root = await Directory.systemTemp.createTemp('request-icon-keys-');
      final paths = PathProviderPlatform.instance;
      final overrides = HttpOverrides.current;
      PathProviderPlatform.instance = _Paths(root.path);
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final slow = Completer<void>();
      var received = 0;
      server.listen((incoming) async {
        received++;
        try {
          incoming.response.add([1, 2, 3]);
          if (incoming.uri.path == '/slow') {
            await incoming.response.flush();
            slow.complete();
            await incoming.response.done;
          } else {
            await incoming.response.close();
          }
        } catch (_) {}
      });
      try {
        final cache = _Cache();
        final files = IOFileSystem('icons');
        final file = await files.createFile('observed-icon');
        when(() => cache.getFileFromCache(any())).thenAnswer((_) async => null);
        when(
          () => cache.putFile(
            any(),
            any(),
            key: any(named: 'key'),
            maxAge: any(named: 'maxAge'),
          ),
        ).thenAnswer((call) async {
          await file.writeAsBytes(call.positionalArguments[1] as Uint8List);
          return file;
        });
        for (var i = 0; i < requestHistoryLimit + 1; i++) {
          final events = await cache
              .getFileStreamV2('http://127.0.0.1:${server.port}/$i')
              .toList();
          expect(events.single.originalUrl, endsWith('/$i'));
          expect(
            request.retainedKeyCounts.total,
            lessThanOrEqualTo(requestHistoryLimit),
          );
        }
        final subscription = cache
            .getFileStreamV2('http://127.0.0.1:${server.port}/slow')
            .listen((_) {});
        await slow.future.timeout(const Duration(seconds: 5));
        await subscription.cancel();
        await pumpEventQueue();
        expect(request.retainedKeyCounts.total, request.retainedKeyCounts.cold);
        expect(received, requestHistoryLimit + 2);
      } finally {
        await server.close(force: true);
        PathProviderPlatform.instance = paths;
        HttpOverrides.global = overrides;
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
