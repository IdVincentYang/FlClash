import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:setup_hooks/src/error.dart';

import 'package:setup_hooks/src/build_cache.dart';
import 'package:setup_hooks/src/fingerprint.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late BuildCache cache;
  late BuildNotice notice;
  late File output;
  late int buildCount;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'setup_build_cache_test_',
    );
    cache = BuildCache(rootDir: temporaryDirectory.path);
    notice = BuildNotice();
    output = File('${temporaryDirectory.path}/output/core');
    buildCount = 0;
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  Future<BuildExecution> runBuild({
    String fingerprint = 'fingerprint-a',
    Duration delay = Duration.zero,
  }) {
    return cache.run(
      key: 'macos-arm64-core',
      fingerprint: () async => Fingerprint(fingerprint),
      primaryOutput: output.path,
      outputs: [output.path],
      notice: notice,
      build: (staging) async {
        buildCount++;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        staging.file(output.path).writeAsStringSync('core-$buildCount');
      },
    );
  }

  test('skips build when fingerprint and outputs are unchanged', () async {
    final first = await runBuild();
    final second = await runBuild();

    expect(first.rebuilt, isTrue);
    expect(second.rebuilt, isFalse);
    expect(buildCount, 1);
  });

  test('rebuilds when fingerprint changes', () async {
    await runBuild();
    final result = await runBuild(fingerprint: 'fingerprint-b');

    expect(result.rebuilt, isTrue);
    expect(buildCount, 2);
  });

  test('rebuilds when an output is missing or modified', () async {
    await runBuild();
    output.deleteSync();
    expect((await runBuild()).rebuilt, isTrue);

    output.writeAsStringSync('externally modified output');
    expect((await runBuild()).rebuilt, isTrue);
    expect(buildCount, 3);
  });

  test('does not write a successful record after a failed build', () async {
    final failingBuild = cache.run(
      key: 'macos-arm64-core',
      fingerprint: () async => const Fingerprint('fingerprint-a'),
      primaryOutput: output.path,
      outputs: [output.path],
      notice: notice,
      build: (staging) async {
        buildCount++;
        throw StateError('build failed');
      },
    );

    await expectLater(failingBuild, throwsStateError);
    expect((await runBuild()).rebuilt, isTrue);
    expect(buildCount, 2);
  });

  test('serializes concurrent checks and rebuilds only once', () async {
    final results = await Future.wait([
      runBuild(delay: const Duration(milliseconds: 50)),
      runBuild(delay: const Duration(milliseconds: 50)),
    ]);

    expect(results.where((result) => result.rebuilt), hasLength(1));
    expect(buildCount, 1);
  });
  test('same-size and mtime corruption is not a hit', () async {
    await runBuild();
    final modified = output.lastModifiedSync();
    output.writeAsStringSync('EVIL!!');
    output.setLastModifiedSync(modified);
    expect((await runBuild()).rebuilt, isTrue);
    expect(output.readAsStringSync(), 'core-2');
  });

  test('candidate record cannot choose read paths', () async {
    await runBuild();
    final record = Directory(
      cache.cacheDir,
    ).listSync().whereType<File>().single;
    final data = jsonDecode(record.readAsStringSync()) as Map<String, dynamic>;
    data['outputs'] = [
      {'path': '/outside/never-read', 'size': 6, 'sha256': 'fake'},
    ];
    record.writeAsStringSync(jsonEncode(data));
    expect((await runBuild()).rebuilt, isTrue);
  });

  test(
    'different keys sharing an output serialize before fingerprint',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final order = <String>[];
      Future<BuildExecution> produce(String key) => cache.run(
        key: key,
        fingerprint: () async {
          order.add('fingerprint-$key');
          return Fingerprint(key);
        },
        primaryOutput: output.path,
        outputs: [output.path],
        notice: notice,
        build: (staging) async {
          if (key == 'A' && !entered.isCompleted) {
            entered.complete();
            await release.future;
          }
          staging
              .file(output.path)
              .writeAsStringSync(key == 'A' ? 'AAAA' : 'BBBB');
          order.add('build-$key');
        },
      );
      final a = produce('A');
      await entered.future;
      final b = produce('B');
      await Future<void>.delayed(Duration.zero);
      expect(order, ['fingerprint-A']);
      release.complete();
      await Future.wait([a, b]);
      expect(order, [
        'fingerprint-A',
        'build-A',
        'fingerprint-A',
        'fingerprint-B',
        'build-B',
        'fingerprint-B',
      ]);
      expect(output.readAsStringSync(), 'BBBB');
      expect((await produce('A')).rebuilt, isTrue);
      expect(output.readAsStringSync(), 'AAAA');
    },
  );

  test('outer Helper failure restores Core, manifest and records', () async {
    final manifest = File('${temporaryDirectory.path}/output/manifest.json');
    await runBuild();
    await cache.transaction((scope) async {
      scope.writeFile(manifest.path, 'old-manifest');
    });
    final record = Directory(
      cache.cacheDir,
    ).listSync().whereType<File>().single;
    final originalRecord = record.readAsStringSync();
    await expectLater(
      cache.transaction((scope) async {
        await scope.run(
          key: 'macos-arm64-core',
          fingerprint: () async => const Fingerprint('new'),
          primaryOutput: output.path,
          outputs: [output.path],
          notice: notice,
          build: (staging) async {
            staging.file(output.path).writeAsStringSync('new-core');
          },
        );
        scope.writeFile(manifest.path, 'new-manifest');
        throw StateError('Helper failed');
      }),
      throwsStateError,
    );
    expect(output.readAsStringSync(), 'core-1');
    expect(manifest.readAsStringSync(), 'old-manifest');
    expect(record.readAsStringSync(), originalRecord);
    expect((await runBuild()).rebuilt, isFalse);
  });

  test('second install error rolls back first output', () async {
    await runBuild();
    final second = Directory('${temporaryDirectory.path}/output/z-blocked')
      ..createSync();
    await expectLater(
      cache.run(
        key: 'two',
        fingerprint: () async => const Fingerprint('two'),
        primaryOutput: output.path,
        outputs: [output.path, second.path],
        notice: notice,
        build: (staging) async {
          staging.file(output.path).writeAsStringSync('new-core');
          staging.file(second.path).writeAsStringSync('other');
        },
      ),
      throwsA(isA<BuildException>()),
    );
    expect(output.readAsStringSync(), 'core-1');
    expect(second.existsSync(), isTrue);
    expect((await runBuild()).rebuilt, isFalse);
  });

  test('ended owner cannot overwrite a later generation', () async {
    late BuildCache ended;
    await cache.transaction((scope) async {
      ended = scope;
    });
    await runBuild();
    expect(() => ended.writeFile(output.path, 'old-owner'), throwsStateError);
    await expectLater(ended.transaction((_) async {}), throwsStateError);
    expect(output.readAsStringSync(), 'core-1');
  });

  test('missing staged output and changed inputs preserve old bytes', () async {
    await runBuild();
    await expectLater(
      cache.run(
        key: 'bad',
        fingerprint: () async => const Fingerprint('bad'),
        primaryOutput: output.path,
        outputs: [output.path],
        notice: notice,
        build: (_) async {},
      ),
      throwsA(isA<BuildException>()),
    );
    var input = 'before';
    await expectLater(
      cache.run(
        key: 'changed',
        fingerprint: () async => Fingerprint(input),
        primaryOutput: output.path,
        outputs: [output.path],
        notice: notice,
        build: (staging) async {
          staging.file(output.path).writeAsStringSync('new');
          input = 'after';
        },
      ),
      throwsA(isA<BuildException>()),
    );
    expect(output.readAsStringSync(), 'core-1');
  });

  test('symlink and undeclared staged outputs are rejected', () async {
    await runBuild();
    await expectLater(
      cache.run(
        key: 'link',
        fingerprint: () async => const Fingerprint('link'),
        primaryOutput: output.path,
        outputs: [output.path],
        notice: notice,
        build: (staging) async {
          Link(staging.file(output.path).path).createSync(output.path);
        },
      ),
      throwsA(isA<BuildException>()),
    );
    await expectLater(
      cache.run(
        key: 'extra',
        fingerprint: () async => const Fingerprint('extra'),
        primaryOutput: output.path,
        outputs: [output.path],
        notice: notice,
        build: (staging) async {
          final file = staging.file(output.path)..writeAsStringSync('new');
          File('${file.path}.extra').writeAsStringSync('unexpected');
        },
      ),
      throwsA(isA<BuildException>()),
    );
    expect(output.readAsStringSync(), 'core-1');
  });
  test(
    'two Dart processes serialize rollback and reject late ownership',
    () async {
      await runBuild();
      Future<void> waitFor(String name) async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!File('${temporaryDirectory.path}/$name').existsSync()) {
          if (DateTime.now().isAfter(deadline)) fail('Missing barrier: $name');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      Future<Process> worker(String key) => Process.start(
        Platform.resolvedExecutable,
        [
          '--packages=.dart_tool/package_config.json',
          'test/fixtures/cache_worker.dart',
          temporaryDirectory.path,
          key,
        ],
        workingDirectory: Directory.current.path,
        environment: {'DART_SUPPRESS_ANALYTICS': 'true'},
      );
      final a = await worker('A');
      final aOut = a.stdout.transform(systemEncoding.decoder).join();
      final aErr = a.stderr.transform(systemEncoding.decoder).join();
      await waitFor('A-installed');
      final b = await worker('B');
      final bOut = b.stdout.transform(systemEncoding.decoder).join();
      final bErr = b.stderr.transform(systemEncoding.decoder).join();
      await waitFor('B-requested');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        File('${temporaryDirectory.path}/B-observed').existsSync(),
        isFalse,
      );
      File('${temporaryDirectory.path}/release-A').writeAsStringSync('release');
      expect(
        await b.exitCode.timeout(const Duration(seconds: 10)),
        0,
        reason: await bOut + await bErr,
      );
      expect(
        await a.exitCode.timeout(const Duration(seconds: 10)),
        0,
        reason: await aOut + await aErr,
      );
      expect(
        File('${temporaryDirectory.path}/B-observed').readAsStringSync(),
        'core-1',
      );
      expect(
        File('${temporaryDirectory.path}/A-cleanup-rejected').existsSync(),
        isTrue,
      );
      expect(output.readAsStringSync(), 'BBBB');
    },
  );

  test('nonoverlapping output plans preserve each other', () async {
    final other = File('${temporaryDirectory.path}/other/result');
    await Future.wait([
      runBuild(),
      cache.run(
        key: 'other',
        fingerprint: () async => const Fingerprint('other'),
        primaryOutput: other.path,
        outputs: [other.path],
        notice: notice,
        build: (staging) async {
          staging.file(other.path).writeAsStringSync('other');
        },
      ),
    ]);
    expect(output.readAsStringSync(), 'core-1');
    expect(other.readAsStringSync(), 'other');
    expect((await runBuild()).rebuilt, isFalse);
  });

  test(
    'different roots can progress while another owner holds its lock',
    () async {
      final otherRoot = Directory('${temporaryDirectory.path}/other-root')
        ..createSync();
      final other = BuildCache(rootDir: otherRoot.path);
      final entered = Completer<void>();
      final release = Completer<void>();
      final first = cache.transaction((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      await other.transaction((_) async {}).timeout(const Duration(seconds: 1));
      release.complete();
      await first;
    },
  );

  test('owned directory replacement removes extra cache members', () async {
    final directory = '${temporaryDirectory.path}/headers';
    final header = '$directory/core.h';
    var count = 0;
    Future<BuildExecution> produce() => cache.run(
      key: 'headers',
      fingerprint: () async => const Fingerprint('headers'),
      primaryOutput: header,
      outputs: [header],
      outputDirectories: [directory],
      notice: notice,
      build: (staging) async {
        count++;
        staging.file(header).writeAsStringSync('accepted');
      },
    );
    await produce();
    File('$directory/extra.h').writeAsStringSync('unexpected');
    expect((await produce()).rebuilt, isTrue);
    expect(Directory(directory).listSync().map((f) => f.path), [header]);
    expect((await produce()).rebuilt, isFalse);
    expect(count, 2);
  });
  test(
    'a caught inner install failure cannot commit half a producer group',
    () async {
      await runBuild();
      final blocked = Directory('${temporaryDirectory.path}/output/z-blocked')
        ..createSync();
      final manifest = '${temporaryDirectory.path}/output/manifest.json';
      await cache.transaction((scope) async {
        try {
          await scope.run(
            key: 'inner',
            fingerprint: () async => const Fingerprint('inner'),
            primaryOutput: output.path,
            outputs: [output.path, blocked.path],
            notice: notice,
            build: (staging) async {
              staging.file(output.path).writeAsStringSync('bad-new-core');
              staging.file(blocked.path).writeAsStringSync('blocked');
            },
          );
        } on BuildException {
          scope.writeFile(manifest, 'independent-valid-output');
        }
      });
      expect(output.readAsStringSync(), 'core-1');
      expect(File(manifest).readAsStringSync(), 'independent-valid-output');
      expect((await runBuild()).rebuilt, isFalse);
    },
  );

  test(
    'failed restoration retains backup and rejects workspace reuse',
    () async {
      await runBuild();
      final parent = output.parent;
      final moved = '${parent.path}-moved';
      await expectLater(
        cache.transaction((scope) async {
          await scope.run(
            key: 'replacement',
            fingerprint: () async => const Fingerprint('replacement'),
            primaryOutput: output.path,
            outputs: [output.path],
            notice: notice,
            build: (staging) async {
              staging.file(output.path).writeAsStringSync('new-core');
            },
          );
          parent.renameSync(moved);
          File(parent.path).writeAsStringSync('synthetic disk obstruction');
          throw StateError('later producer failed');
        }),
        throwsA(isA<BuildException>()),
      );
      final retained =
          Directory('${temporaryDirectory.path}/.dart_tool/setup_build_cache')
              .listSync()
              .whereType<Directory>()
              .where((entry) => entry.path.contains('generation-'));
      expect(retained, hasLength(1));
      expect(
        retained.single
            .listSync(recursive: true)
            .whereType<File>()
            .any((file) => file.readAsStringSync() == 'core-1'),
        isTrue,
      );
      File(parent.path).deleteSync();
      Directory(moved).renameSync(parent.path);
      await expectLater(runBuild(), throwsA(isA<BuildException>()));
      expect(output.readAsStringSync(), 'new-core');
    },
  );

  test(
    'ended producer cannot reuse staging even inside its transaction',
    () async {
      late BuildStaging ended;
      await cache.transaction((scope) async {
        await scope.run(
          key: 'producer',
          fingerprint: () async => const Fingerprint('producer'),
          primaryOutput: output.path,
          outputs: [output.path],
          notice: notice,
          build: (staging) async {
            ended = staging;
            staging.file(output.path).writeAsStringSync('accepted');
          },
        );
        expect(() => ended.file(output.path), throwsStateError);
        expect(() => ended.work, throwsStateError);
      });
      expect(output.readAsStringSync(), 'accepted');
    },
  );
}
