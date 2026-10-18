import 'package:fl_clash/common/request.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapAndCommit(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    await dataMutations.run(() async {});
  });
}
