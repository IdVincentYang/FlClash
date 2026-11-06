import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/geo_seed.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
  @override
  Future<String> getTemporaryPath() async => path;
  @override
  Future<String> getApplicationCachePath() async => path;
}

class _Assets extends CachingAssetBundle {
  _Assets(this.data);
  final Map<String, ByteData> data;
  final loaded = <String>[];
  Future<void> Function(String)? onLoad;
  StateError? failure;

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    await onLoad?.call(key);
    if (failure != null) throw failure!;
    return data[key] ?? (throw StateError('Unexpected asset: $key'));
  }
}

const _names = [MMDB, GEOIP, GEOSITE, ASN];

ByteData _view(List<int> bytes, {bool padded = false}) {
  final storage = Uint8List.fromList(padded ? [91, 92, ...bytes, 93] : bytes);
  return ByteData.view(storage.buffer, padded ? 2 : 0, bytes.length);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory suite;
  late Directory home;
  late _Core core;
  late List<int> manifest;
  late Map<String, List<int>> payloads;
  late PathProviderPlatform originalPaths;
  late ProcessRunner originalRunner;

  setUpAll(() async {
    registerFallbackValue(const InitParams(homeDir: '.', version: 1));
    suite = await Directory.systemTemp.createTemp('flclash-geo-seed-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(suite.path);
    originalRunner = system.runProcess;
    system.runProcess = (_, _) async => ProcessResult(0, 0, '', '');
    manifest = await File(GeoSeedReference.manifestAsset).readAsBytes();
    payloads = {
      for (final name in _names)
        name: await File('assets/data/$name').readAsBytes(),
    };
  });

  setUp(() async {
    home = await suite.createTemp('case-');
    core = _Core();
    when(() => core.init(any())).thenAnswer((_) async => true);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await home.delete(recursive: true);
  });

  tearDownAll(() async {
    system.runProcess = originalRunner;
    PathProviderPlatform.instance = originalPaths;
    await suite.delete(recursive: true);
  });

  _Assets validAssets({bool padded = false}) => _Assets({
    GeoSeedReference.manifestAsset: _view(manifest, padded: padded),
    for (final name in _names)
      'assets/data/$name': _view(payloads[name]!, padded: padded),
  });

  CoreController controller(_Assets assets, {bool android = true}) =>
      CoreController.forSeedTesting(
        core,
        homePath: home.path,
        assets: assets,
        isAndroid: android,
      );

  Future<void> existingExcept(String? missing) async {
    for (final name in _names.where((name) => name != missing)) {
      await File('${home.path}/$name').writeAsString('existing-$name');
    }
  }

  test('compiled anchor matches the accepted repository manifest', () {
    expect(
      sha256.convert(manifest).toString(),
      GeoSeedReference.acceptedManifestDigest,
    );
  });

  for (final padded in [false, true]) {
    test(
      'controller writes four validated seeds before Core init; padded=$padded',
      () async {
        final assets = validAssets(padded: padded);
        when(() => core.init(any())).thenAnswer((call) async {
          final params = call.positionalArguments.single as InitParams;
          expect(params.homeDir, home.path);
          expect(params.version, 34);
          for (final name in _names) {
            expect(
              await File('${home.path}/$name').readAsBytes(),
              payloads[name],
            );
            expect(await File('${home.path}/$name.seed').exists(), isFalse);
          }
          return true;
        });
        expect(await controller(assets).init(34), isTrue);
        expect(
          assets.loaded.where((name) => name == GeoSeedReference.manifestAsset),
          hasLength(1),
        );
        verify(() => core.init(any())).called(1);
      },
    );
  }

  test(
    'self-consistent altered manifest and payload fail the production anchor',
    () async {
      final altered = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
      final resources = altered['resources'] as List;
      final body = <int>[1, 2, 3];
      for (final entry in resources.cast<Map<String, dynamic>>()) {
        entry['size'] = body.length;
        entry['sha256'] = sha256.convert(body).toString();
      }
      final changed = utf8.encode(jsonEncode(altered));
      final structural = GeoSeedReference.parseForTesting(changed);
      expect(structural.verifiedBytes(MMDB, _view(body)), body);
      final assets = _Assets({
        GeoSeedReference.manifestAsset: _view(changed),
        for (final name in _names) 'assets/data/$name': _view(body),
      });
      await expectLater(
        controller(assets).init(34),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('baseline'),
          ),
        ),
      );
      expect(await home.list().toList(), isEmpty);
      verifyNever(() => core.init(any()));
    },
  );

  test(
    'bad payload fails before its target while earlier valid seed remains',
    () async {
      final assets = validAssets();
      final bad = List<int>.of(payloads[GEOIP]!);
      bad[0] ^= 1;
      assets.data['assets/data/$GEOIP'] = _view(bad);
      await expectLater(
        controller(assets).init(34),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('digest'),
          ),
        ),
      );
      expect(await File('${home.path}/$MMDB').readAsBytes(), payloads[MMDB]);
      expect(await File('${home.path}/$GEOIP').exists(), isFalse);
      expect(await File('${home.path}/$GEOIP.seed').exists(), isFalse);
      verifyNever(() => core.init(any()));
    },
  );

  test('wrong payload length fails before writing', () async {
    final assets = validAssets();
    assets.data['assets/data/$MMDB'] = _view([1, 2, 3]);
    await expectLater(
      controller(assets).init(34),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'reason',
          contains('length'),
        ),
      ),
    );
    expect(await home.list().toList(), isEmpty);
    verifyNever(() => core.init(any()));
  });

  test(
    'all existing targets skip even unavailable assets and manifest',
    () async {
      await existingExcept(null);
      final assets = _Assets({})..failure = StateError('unused bundle');
      expect(await controller(assets).init(34), isTrue);
      expect(assets.loaded, isEmpty);
      for (final name in _names) {
        expect(
          await File('${home.path}/$name').readAsString(),
          'existing-$name',
        );
      }
    },
  );

  test(
    'existing targets stay unchanged while one missing role is verified',
    () async {
      await existingExcept(ASN);
      final assets = validAssets();
      expect(await controller(assets).init(34), isTrue);
      for (final name in _names.where((name) => name != ASN)) {
        expect(
          await File('${home.path}/$name').readAsString(),
          'existing-$name',
        );
      }
      expect(await File('${home.path}/$ASN').readAsBytes(), payloads[ASN]);
      expect(assets.loaded.toSet(), {
        GeoSeedReference.manifestAsset,
        'assets/data/$ASN',
      });
    },
  );

  test('mutation guard rechecks a target created by preceding work', () async {
    await existingExcept(MMDB);
    final entered = Completer<void>();
    final release = Completer<void>();
    Future<void>? preceding;
    final assets = _Assets({
      'assets/data/$MMDB': _view([1]),
    });
    assets.onLoad = (_) async {
      preceding = dataMutations.run(() async {
        entered.complete();
        await release.future;
        await File('${home.path}/$MMDB').writeAsString('arrived while waiting');
      });
      await entered.future;
    };
    final init = controller(assets).init(34);
    await entered.future;
    release.complete();
    await preceding;
    expect(await init, isTrue);
    expect(
      await File('${home.path}/$MMDB').readAsString(),
      'arrived while waiting',
    );
    expect(assets.loaded, ['assets/data/$MMDB']);
  });

  test(
    'real rename failure cleans its stage and preserves the I/O error',
    () async {
      await existingExcept(MMDB);
      await Directory('${home.path}/$MMDB').create();
      await expectLater(
        controller(validAssets()).init(34),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.osError,
            'original OS error',
            isNotNull,
          ),
        ),
      );
      expect(await Directory('${home.path}/$MMDB').exists(), isTrue);
      expect(await File('${home.path}/$MMDB.seed').exists(), isFalse);
      verifyNever(() => core.init(any()));
    },
  );

  test('asset loading error is propagated without calling Core', () async {
    final failure = StateError('asset loading failed');
    final assets = _Assets({})..failure = failure;
    await expectLater(controller(assets).init(34), throwsA(same(failure)));
    expect(await home.list().toList(), isEmpty);
    verifyNever(() => core.init(any()));
  });

  test('non-Android fixture keeps the original unverified seed path', () async {
    final assets = _Assets({
      for (final name in _names) 'assets/data/$name': _view([1, 2]),
    });
    expect(await controller(assets, android: false).init(34), isTrue);
    expect(assets.loaded, isNot(contains(GeoSeedReference.manifestAsset)));
    expect(await File('${home.path}/$MMDB').readAsBytes(), [1, 2]);
  });

  test(
    'Flutter target override cannot enable the production Android gate',
    () async {
      expect(Platform.isAndroid, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final assets = _Assets({
        for (final name in _names) 'assets/data/$name': _view([4, 5]),
      });
      final previous = appPath.dataDir;
      await previous.future;
      appPath.dataDir = Completer<Directory>()..complete(home);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final key = utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            );
            return assets.load(key);
          });
      try {
        expect(await CoreController.scoped(core).init(34), isTrue);
        expect(assets.loaded, isNot(contains(GeoSeedReference.manifestAsset)));
        expect(await File('${home.path}/$MMDB').readAsBytes(), [4, 5]);
      } finally {
        appPath.dataDir = previous;
      }
    },
  );

  group('structural parser branches use an explicit untrusted test entry', () {
    for (final change in <String, void Function(Map<String, dynamic>)>{
      'version': (m) => m['version'] = 2,
      'unknown root key': (m) => m['unknown'] = true,
      'missing role': (m) => (m['resources'] as List).removeLast(),
      'duplicate filename': (m) =>
          (m['resources'] as List)[1] = (m['resources'] as List)[0],
      'role': (m) => (m['resources'] as List)[0]['role'] = 'ASN',
      'filename': (m) => (m['resources'] as List)[0]['filename'] = '../outside',
      'asset': (m) => (m['resources'] as List)[0]['asset_name'] = 'other',
      'format': (m) => (m['resources'] as List)[0]['format'] = 'maxmind-asn',
      'size type': (m) => (m['resources'] as List)[0]['size'] = 1.0,
      'size zero': (m) => (m['resources'] as List)[0]['size'] = 0,
      'digest': (m) => (m['resources'] as List)[0]['sha256'] = 'invalid',
      'unknown resource key': (m) =>
          (m['resources'] as List)[0]['unknown'] = true,
    }.entries) {
      test(change.key, () {
        final value = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
        change.value(value);
        expect(
          () =>
              GeoSeedReference.parseForTesting(utf8.encode(jsonEncode(value))),
          throwsFormatException,
        );
      });
    }
    test('invalid JSON does not expose its source text', () {
      expect(
        () => GeoSeedReference.parseForTesting(
          utf8.encode('private-material-content'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('private-material-content')),
          ),
        ),
      );
    });
    test('validated payload is an owned copy', () {
      final reference = GeoSeedReference.fromAsset(_view(manifest));
      final source = Uint8List.fromList(payloads[MMDB]!);
      final result = reference.verifiedBytes(
        MMDB,
        ByteData.sublistView(source),
      );
      source[0] ^= 1;
      expect(result, payloads[MMDB]);
    });
  });
}
