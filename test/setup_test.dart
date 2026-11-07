import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {'APP_ENV': 'dev'});
    });

    test(
      'release candidate is explicit and cannot mix with dev or another platform',
      () {
        final options = setup.createSetupArgParser().parse([
          'android',
          '--android-release-candidate',
        ]);
        expect(options['android-release-candidate'], isTrue);
        expect(
          setup.createBuildEnvironment('pre', androidReleaseCandidate: true),
          {'APP_ENV': 'pre', 'ANDROID_RELEASE_CANDIDATE': 'true'},
        );
        for (final platform in ['android', 'macos']) {
          expect(
            () => setup.validateReleaseCandidate(
              platform: platform,
              applicationEnvironment: 'dev',
              candidate: true,
            ),
            throwsStateError,
          );
        }
        expect(
          () => setup.validateReleaseCandidate(
            platform: 'android',
            applicationEnvironment: 'stable',
            candidate: true,
            managedProfile: 'dev',
          ),
          throwsStateError,
        );
        setup.validateReleaseCandidate(
          platform: 'android',
          applicationEnvironment: 'stable',
          candidate: true,
        );
      },
    );

    test(
      'local package rejects hooks and publisher configuration before execution',
      () {
        setup.validatePackageConfiguration(
          'app_name: FlClash\noutput: dist/\n',
        );
        for (final option in [
          'publishers: {}',
          'hooks: {}',
          'variables: {}',
          'releases: []',
        ]) {
          expect(
            () => setup.validatePackageConfiguration(
              'app_name: FlClash\noutput: dist/\n$option\n',
            ),
            throwsStateError,
          );
        }
      },
    );

    test('packager inherits tools but no known publication credentials', () {
      expect(
        setup.packageProcessEnvironment({
          'PATH': '/tools',
          'GITHUB_TOKEN': 'secret',
          'TELEGRAM_API_HASH': 'secret',
          'KEYSTORE': 'secret',
          'ANDROID_HOME': '/sdk',
        }),
        {'PATH': '/tools', 'ANDROID_HOME': '/sdk'},
      );
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    test('managed Android uses the prepared pub graph without another get', () {
      expect(
        setup.createFlutterBuildArgs(
          platform: 'android',
          verbose: false,
          managedAndroid: true,
        ),
        ['dart-define-from-file=env.json', 'split-per-abi', 'no-pub'],
      );
    });

    group('managed Android selectors', () {
      late Directory root;
      late Map<String, String> environment;

      setUp(() {
        root = Directory.systemTemp.createTempSync('android-selectors-');
        final android = Directory(p.join(root.path, 'android'))..createSync();
        final config = Directory(p.join(root.path, 'config'))..createSync();
        final dart = File(p.join(root.path, 'dart'))..writeAsStringSync('');
        final packageConfig = File(p.join(root.path, 'package_config.json'))
          ..writeAsStringSync('{}');
        final entry = File(p.join(root.path, 'main.dart'))
          ..writeAsStringSync('');
        environment = {
          'FLCLASH_ANDROID_PROFILE': 'macos_arm64_android_arm64_dev',
          'FLCLASH_ANDROID_DART': dart.path,
          'FLCLASH_ANDROID_FLUTTER_ROOT': p.join(root.path, 'flutter'),
          'FLUTTER_ROOT': p.join(root.path, 'flutter'),
          'JAVA_HOME': p.join(root.path, 'jdk'),
          'ANDROID_HOME': p.join(root.path, 'sdk'),
          'ANDROID_SDK_ROOT': p.join(root.path, 'sdk'),
          'ANDROID_NDK_HOME': p.join(root.path, 'ndk'),
          'ANDROID_NDK_ROOT': p.join(root.path, 'ndk'),
          'FLCLASH_ANDROID_NDK': p.join(root.path, 'ndk'),
          'FLCLASH_ANDROID_CMAKE': p.join(root.path, 'cmake'),
          'XDG_CONFIG_HOME': config.path,
          'FLCLASH_ANDROID_PACKAGER_CONFIG': packageConfig.path,
          'FLCLASH_ANDROID_PACKAGER_MAIN': entry.path,
        };
        File(p.join(config.path, 'settings')).writeAsStringSync(
          jsonEncode({
            'jdk-dir': environment['JAVA_HOME'],
            'android-sdk': environment['ANDROID_HOME'],
          }),
        );
        File(p.join(android.path, 'local.properties')).writeAsStringSync(
          'flutter.sdk=${environment['FLUTTER_ROOT']}\n'
          'sdk.dir=${environment['ANDROID_HOME']}\n'
          'cmake.dir=${environment['FLCLASH_ANDROID_CMAKE']}\n',
        );
        File(
          p.join(root.path, 'distribute_options.yaml'),
        ).writeAsStringSync("app_name: 'FlClash'\noutput: 'dist/'\n");
      });

      tearDown(() => root.deleteSync(recursive: true));

      List<String> command({String host = 'macos'}) =>
          setup.managedAndroidPackageCommand(
            rootDir: root.path,
            environment: environment,
            resolvedExecutable: environment['FLCLASH_ANDROID_DART']!,
            host: host,
            arch: 'arm64',
            applicationEnvironment: 'dev',
            targets: 'apk',
          );

      test('delegates through the same VM and explicit packager config', () {
        expect(command(), [
          environment['FLCLASH_ANDROID_DART'],
          '--disable-dart-dev',
          '--packages=${environment['FLCLASH_ANDROID_PACKAGER_CONFIG']}',
          environment['FLCLASH_ANDROID_PACKAGER_MAIN'],
        ]);
      });

      test('rejects higher priority Flutter JDK settings', () {
        File(
          p.join(environment['XDG_CONFIG_HOME']!, 'settings'),
        ).writeAsStringSync(
          jsonEncode({
            'jdk-dir': p.join(root.path, 'unaccepted-jdk'),
            'android-sdk': environment['ANDROID_HOME'],
          }),
        );
        expect(command, throwsStateError);
      });

      test('rejects local property overrides and packager variables', () {
        final properties = File(p.join(root.path, 'android/local.properties'));
        final original = properties.readAsStringSync();
        properties.writeAsStringSync('$original\nsdk.dir=/unaccepted/sdk\n');
        expect(command, throwsStateError);
        properties.writeAsStringSync(original);
        File(p.join(root.path, 'distribute_options.yaml')).writeAsStringSync(
          "app_name: 'FlClash'\noutput: 'dist/'\nvariables:\n  FLUTTER_ROOT: /unaccepted/sdk\n",
        );
        expect(command, throwsStateError);
      });

      test('rejects unsupported hosts and conflicting environment roots', () {
        expect(() => command(host: 'linux'), throwsStateError);
        environment['ANDROID_NDK_HOME'] = '/unaccepted/ndk';
        expect(command, throwsStateError);
      });
    });

    test('refuses to package while a native build hook is skipped', () {
      const pubspec = '''
hooks:
  user_defines:
    setup:
      build_assets: false
    rust_api:
      build_assets: true
''';

      expect(setup.packagesNotBuildingAssets(pubspec), ['setup']);
      expect(setup.packagesNotBuildingAssets('name: x\n'), isEmpty);
    });

    test('packages every Linux format on every architecture', () {
      expect(setup.createPackageTargets('linux', null), 'deb,appimage,rpm');
      expect(setup.createPackageTargets('linux', 'deb'), 'deb');
      expect(setup.createPackageTargets('macos', null), 'dmg');
    });

    test('downloads the appimagetool build matching the host', () {
      expect(setup.appImageToolArch('arm64'), 'aarch64');
      expect(setup.appImageToolArch('amd64'), 'x86_64');
    });
  });
}
