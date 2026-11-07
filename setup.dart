import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb,appimage,rpm',
  'macos': 'dmg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'windows': 'windows',
};

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host && platform != 'android') {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final candidate = results['android-release-candidate'] as bool;
  validateReleaseCandidate(
    platform: platform,
    applicationEnvironment: env,
    candidate: candidate,
    managedProfile: Platform.environment['FLCLASH_ANDROID_PROFILE'],
  );
  final rootDir = Directory.current.path;
  final skipped = packagesNotBuildingAssets(
    File(p.join(rootDir, 'pubspec.yaml')).readAsStringSync(),
  );
  if (skipped.isNotEmpty) {
    stderr.writeln(
      'pubspec.yaml sets hooks.user_defines.<package>.build_assets: false '
      'for ${skipped.join(', ')}; a package built this way would ship '
      'whatever is left in libclash/ and no Rust library. '
      'Restore "build_assets: true".',
    );
    exit(1);
  }
  final arch = _detectArch();
  final targets = createPackageTargets(platform, results['targets']);
  final androidArch = results['arch'] as String?;
  final verbose = results['verbose'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    androidReleaseCandidate: candidate,
    verbose: verbose,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'pre',
      allowed: ['dev', 'pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,dmg,apk,...',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help: 'Target architecture (Android only)',
    )
    ..addFlag(
      'android-release-candidate',
      negatable: false,
      help:
          'Build a developer-signed Android pre/stable candidate for isolated CI signing',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    );
}

List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
  bool managedAndroid = false,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
    if (managedAndroid) flutterBuildArgs.add('no-pub');
  }
  return flutterBuildArgs;
}

Map<String, String> createBuildEnvironment(
  String env, {
  bool androidReleaseCandidate = false,
}) {
  return {
    'APP_ENV': env,
    if (androidReleaseCandidate) 'ANDROID_RELEASE_CANDIDATE': 'true',
  };
}

void validateReleaseCandidate({
  required String platform,
  required String applicationEnvironment,
  required bool candidate,
  String? managedProfile,
}) {
  if (candidate &&
      (platform != 'android' ||
          applicationEnvironment == 'dev' ||
          managedProfile != null)) {
    throw StateError(
      'Release candidates require Android pre/stable outside the dev profile',
    );
  }
}

void validatePackageConfiguration(String text) {
  final config = loadYaml(text);
  if (config is! Map ||
      config.length != 2 ||
      config['app_name'] != 'FlClash' ||
      config['output'] != 'dist/') {
    throw StateError(
      'Local package refuses publisher, hook or additional distributor configuration',
    );
  }
}

Map<String, String> packageProcessEnvironment(Map<String, String> parent) {
  const excluded = {
    'GH_TOKEN',
    'GITHUB_TOKEN',
    'ACTIONS_RUNTIME_TOKEN',
    'KEYSTORE',
    'KEY_ALIAS',
    'KEY_PASSWORD',
    'STORE_PASSWORD',
    'SSH_DEPLOY_KEY',
    'HOMEBREW_SSH_DEPLOY_KEY',
  };
  return {
    for (final entry in parent.entries)
      if (!excluded.contains(entry.key.toUpperCase()) &&
          !entry.key.toUpperCase().startsWith('TELEGRAM_'))
        entry.key: entry.value,
  };
}

/// Packages whose build hook `pubspec.yaml` turns into a no-op.
List<String> packagesNotBuildingAssets(String pubspec) {
  final document = loadYaml(pubspec);
  if (document is! Map) return const [];
  final defines = (document['hooks'] as Map?)?['user_defines'];
  if (defines is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in defines.entries)
      if (value is Map && value['build_assets'] == false) key.toString(),
  ]..sort();
}

String createPackageTargets(String platform, String? customTargets) {
  return customTargets ?? _allTargets[platform]!;
}

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln('Platform: current host platform (default) or android');
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  required bool verbose,
  bool androidReleaseCandidate = false,
}) async {
  validatePackageConfiguration(
    File(p.join(rootDir, 'distribute_options.yaml')).readAsStringSync(),
  );
  final packageEnvironment = packageProcessEnvironment(Platform.environment);
  final managedAndroid =
      platform == 'android' &&
      Platform.environment.containsKey('FLCLASH_ANDROID_PROFILE');
  final managedCommand = managedAndroid
      ? managedAndroidPackageCommand(
          rootDir: rootDir,
          environment: Platform.environment,
          resolvedExecutable: Platform.resolvedExecutable,
          host: Platform.operatingSystem,
          arch: androidArch,
          applicationEnvironment: env,
          targets: targets,
        )
      : null;
  final file = File(p.join(rootDir, 'env.json'));
  await file.writeAsString(
    jsonEncode(
      createBuildEnvironment(
        env,
        androidReleaseCandidate: androidReleaseCandidate,
      ),
    ),
  );

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
    managedAndroid: managedAndroid,
  );
  final descriptionArgs = <String>[];
  if (platform != 'android') {
    descriptionArgs.addAll(['--description', arch]);
  }

  final depExit = await _ensureDependencies(platform);
  if (depExit != 0) return depExit;

  if (!managedAndroid) {
    final consumer =
        loadYaml(
              File(
                p.join(
                  rootDir,
                  'tool/android_bootstrap/distributor.pubspec.yaml',
                ),
              ).readAsStringSync(),
            )
            as Map;
    final git =
        (consumer['dependencies'] as Map)['flutter_distributor']['git'] as Map;
    final activateResult = await Process.run(
      'dart',
      [
        'pub',
        'global',
        'activate',
        '-s',
        'git',
        git['url'] as String,
        '--git-ref',
        git['ref'] as String,
        '--git-path',
        git['path'] as String,
      ],
      environment: packageEnvironment,
      includeParentEnvironment: false,
    );
    if (activateResult.exitCode != 0) {
      stderr.write(activateResult.stderr);
      return activateResult.exitCode;
    }
  }

  final process = await Process.start(
    managedCommand?.first ?? 'flutter_distributor',
    [
      ...?managedCommand?.skip(1),
      'package',
      '--skip-clean',
      '--platform',
      platform,
      '--targets',
      targets,
      if (androidArch != null)
        '--build-target-platform=${_androidFlutterTarget[androidArch]!}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: false,
    environment: packageEnvironment,
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  return exitCode;
}

List<String> managedAndroidPackageCommand({
  required String rootDir,
  required Map<String, String> environment,
  required String resolvedExecutable,
  required String host,
  required String? arch,
  required String applicationEnvironment,
  required String targets,
}) {
  if (environment['FLCLASH_ANDROID_PROFILE'] !=
          'macos_arm64_android_arm64_dev' ||
      host != 'macos' ||
      arch != 'arm64' ||
      applicationEnvironment != 'dev' ||
      targets != 'apk') {
    throw StateError('Unsupported managed Android build profile');
  }
  String selected(String name) {
    final value = environment[name];
    if (value == null || !p.isAbsolute(value)) {
      throw StateError('Managed Android selection missing: $name');
    }
    return p.normalize(value);
  }

  final dart = selected('FLCLASH_ANDROID_DART');
  if (File(resolvedExecutable).resolveSymbolicLinksSync() !=
      File(dart).resolveSymbolicLinksSync()) {
    throw StateError('Setup is running under a different Dart executable');
  }
  final sdk = selected('FLCLASH_ANDROID_FLUTTER_ROOT');
  if (environment['FLUTTER_ROOT'] != sdk) {
    throw StateError('Packager would select a different Flutter SDK');
  }
  final jdk = selected('JAVA_HOME');
  final androidSdk = selected('ANDROID_HOME');
  final ndk = selected('FLCLASH_ANDROID_NDK');
  if (environment['ANDROID_SDK_ROOT'] != androidSdk ||
      environment['ANDROID_NDK_HOME'] != ndk ||
      environment['ANDROID_NDK_ROOT'] != ndk) {
    throw StateError('Android environment changes a selected SDK or NDK');
  }
  final config = jsonDecode(
    File(p.join(selected('XDG_CONFIG_HOME'), 'settings')).readAsStringSync(),
  );
  if (config is! Map ||
      config['jdk-dir'] != jdk ||
      config['android-sdk'] != androidSdk) {
    throw StateError('Flutter settings change the selected JDK or Android SDK');
  }
  final properties = <String, String>{};
  for (final line in File(
    p.join(rootDir, 'android/local.properties'),
  ).readAsLinesSync()) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final split = line.indexOf('=');
    if (split <= 0 || properties.containsKey(line.substring(0, split))) {
      throw StateError('Ambiguous managed Android local.properties');
    }
    properties[line.substring(0, split)] = line.substring(split + 1);
  }
  if (properties['flutter.sdk'] != sdk ||
      properties['sdk.dir'] != androidSdk ||
      properties['cmake.dir'] != selected('FLCLASH_ANDROID_CMAKE') ||
      properties.keys.any(
        (key) => key != 'flutter.sdk' && key != 'sdk.dir' && key != 'cmake.dir',
      )) {
    throw StateError('Android local.properties changes a selected tool root');
  }
  if (File(
    p.join(rootDir, 'android/gradle/gradle-daemon-jvm.properties'),
  ).existsSync()) {
    throw StateError('Gradle daemon JVM criteria are outside this profile');
  }
  final options = loadYaml(
    File(p.join(rootDir, 'distribute_options.yaml')).readAsStringSync(),
  );
  if (options is! Map ||
      options.keys.any((key) => key != 'app_name' && key != 'output') ||
      options['app_name'] != 'FlClash' ||
      options['output'] != 'dist/') {
    throw StateError('Managed packaging does not accept additional overrides');
  }
  final packageConfig = selected('FLCLASH_ANDROID_PACKAGER_CONFIG');
  final entry = selected('FLCLASH_ANDROID_PACKAGER_MAIN');
  if (!File(packageConfig).existsSync() || !File(entry).existsSync()) {
    throw StateError('The accepted packager source graph is not prepared');
  }
  return [
    resolvedExecutable,
    '--disable-dart-dev',
    '--packages=$packageConfig',
    entry,
  ];
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(which, args);
  return result.exitCode == 0;
}

Future<int> _ensureDependencies(String platform) async {
  switch (platform) {
    case 'macos':
      return _ensureMacosDependencies();
    case 'linux':
      return _ensureLinuxDependencies();
    default:
      return 0;
  }
}

Future<int> _ensureMacosDependencies() async {
  if (await _hasCommand('appdmg')) {
    stdout.writeln('appdmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing appdmg (DMG creator)...');
  final result = await Process.run('npm', ['install', '-g', 'appdmg']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<int> _ensureLinuxDependencies() async {
  const pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libsecret-1-dev'],
    ['locate'],
    ['rpm', 'patchelf'],
    ['libfuse2'],
  ];

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) return installExit;
    }
  }

  const appimagetool = '/usr/local/bin/appimagetool';
  if (File(appimagetool).existsSync()) {
    stdout.writeln('appimagetool already installed, skipping.');
    return 0;
  }
  stdout.writeln('Downloading appimagetool...');
  final downloadName =
      'appimagetool-${appImageToolArch(_detectArch())}.AppImage';
  final dlResult = await Process.run('wget', [
    '-O',
    appimagetool,
    'https://github.com/AppImage/AppImageKit/releases/download/continuous/$downloadName',
  ]);
  if (dlResult.exitCode != 0) {
    stderr.write(dlResult.stderr);
    return dlResult.exitCode;
  }
  await Process.run('chmod', ['+x', appimagetool]);
  return 0;
}

String appImageToolArch(String arch) {
  return arch == 'arm64' ? 'aarch64' : 'x86_64';
}

/// Ubuntu 24.04 ships libfuse2 under its time64 name, which `dpkg -s libfuse2` cannot see.
const _debianPackageAliases = <String, List<String>>{
  'libfuse2': ['libfuse2t64'],
};

Future<bool> _isDebianPackageInstalled(String pkg) async {
  for (final name in [pkg, ...?_debianPackageAliases[pkg]]) {
    final result = await Process.run('dpkg', ['-s', name]);
    if (result.exitCode == 0 &&
        (result.stdout as String).contains('Status: install ok installed')) {
      return true;
    }
  }
  return false;
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}
