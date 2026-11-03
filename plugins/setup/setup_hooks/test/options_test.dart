import 'dart:io';

import 'package:setup_hooks/src/options.dart';
import 'package:setup_hooks/src/target.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('setup_options_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('all Android ABIs require disabled ZeroTier with default tags', () {
    final config = BuildConfig.load(rootDir: root.path);
    for (final target in Target.forPlatform('android')) {
      expect(config.tagsFor(target), 'with_gvisor,no_zerotier');
    }
    for (final target in Target.all.where(
      (target) => target.goos != 'android',
    )) {
      expect(config.tagsFor(target), 'with_gvisor');
    }
  });

  test('Android preserves custom tags and deduplicates both separators', () {
    File(
      '${root.path}/build_config.yaml',
    ).writeAsStringSync('tags: "with_gvisor,custom no_zerotier,custom"\n');
    final config = BuildConfig.load(rootDir: root.path);
    expect(
      config.tagsFor(Target.androidArm64),
      'with_gvisor,custom,no_zerotier',
    );
    expect(
      config.tagsFor(Target.linuxAmd64),
      'with_gvisor,custom no_zerotier,custom',
    );
    expect(
      config.toFingerprintMap()['tags'],
      'with_gvisor,custom no_zerotier,custom',
    );
  });
}
