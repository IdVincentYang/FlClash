import 'dart:io';
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'app settings survive reopening and profile deletion prunes only its bindings',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'application-routing-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/state.sqlite');
      var store = Database(NativeDatabase(file));
      await store.profilesDao.setAll([
        const Profile(id: 1, autoUpdateDuration: Duration(hours: 1)),
      ]);
      await store.profilesDao.setAll([
        const Profile(id: 2, autoUpdateDuration: Duration(hours: 1)),
      ]);
      const target = ApplicationRouteTarget(
        name: 'Mine',
        kind: ApplicationTargetKind.globalGroup,
        groupId: 8,
      );
      const rule = ApplicationRouteRule(
        packageName: 'app',
        enabled: true,
        useSharedTarget: false,
        targets: {1: target, 2: target},
      );
      final saved = await store.writeApplicationRouting(
        const ApplicationRoutingSettings(
          rules: {'app': rule},
          sharedTargets: {1: target, 2: target},
        ),
      );
      expect(saved.revision, 1);
      await store.close();
      store = Database(NativeDatabase(file));
      addTearDown(store.close);
      expect(await store.readApplicationRouting(), saved);
      await store.deleteProfile(1);
      final retained = await store.readApplicationRouting();
      expect(retained.rules['app']?.enabled, true);
      expect(retained.rules['app']?.targets.keys, [2]);
      expect(retained.sharedTargets.keys, [2]);
      expect(await store.profilesDao.query().get(), hasLength(1));
    },
  );
}
