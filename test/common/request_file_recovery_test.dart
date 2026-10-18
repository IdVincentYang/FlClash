import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('request-file-recovery-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;
  });
  tearDownAll(() => root.delete(recursive: true));

  test(
    'failed compensation retains the previous material and requires recovery before networking',
    () async {
      final target = File('${root.path}/profile');
      await target.writeAsString('previous');
      final staged = await RequestFile.stage('candidate'.codeUnits);
      try {
        await expectLater(
          request.localCommit(
            () => staged.replace(target.path, () async {
              await target.delete();
              await Directory(target.path).create();
              await File(
                '${target.path}/blocked',
              ).writeAsString('synthetic filesystem failure');
              throw StateError('synthetic database failure');
            }),
          ),
          throwsA(
            isA<RequestUnavailable>().having(
              (e) => e.code,
              'code',
              'request_partial_commit',
            ),
          ),
        );
        await staged.close();
        expect(request.partialCommit, true);
        expect(
          await File('${root.path}/request-recovery-required').exists(),
          true,
        );
        expect(
          await File('${staged.directory.path}/previous').readAsString(),
          'previous',
        );
        expect(await staged.directory.exists(), true);
        await expectLater(
          request.begin(key: 'profile:blocked', url: 'http://127.0.0.1/'),
          throwsA(
            isA<RequestUnavailable>().having(
              (error) => error.code,
              'code',
              'request_partial_commit',
            ),
          ),
        );
      } finally {
        await request.clearPartialCommit();
      }
    },
  );
}
