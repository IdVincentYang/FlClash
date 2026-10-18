import 'dart:async';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Requests extends Request {
  Completer<void>? hold;
  Completer<void>? entered;

  @override
  Future<void> invalidate(String key) async {
    entered?.complete();
    await hold?.future;
    await super.invalidate(key);
  }
}

class _Inputs extends ApplicationInputAction {
  _Inputs(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late ProviderContainer container;
  late _Requests client;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    db = Database(NativeDatabase.memory());
    database = db;
    client = _Requests();
    container = ProviderContainer(
      overrides: [
        applicationInputActionProvider.overrideWith(() => _Inputs(client)),
      ],
    );
    container.listen(configProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'effective direct writes reject before publication; visual preference is allowed',
    () {
      final notifier = container.read(appSettingProvider.notifier);
      final previous = notifier.value;
      expect(
        () => notifier.value = previous.copyWith(testUrl: 'https://new.test'),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(notifier.value, previous);
      notifier.update(
        (value) => value.copyWith(showTrayTitle: !value.showTrayTitle),
      );
      expect(notifier.value.showTrayTitle, !previous.showTrayTitle);
      expect(
        () => container
            .read(networkSettingProvider.notifier)
            .update((value) => value.copyWith(systemProxy: !value.systemProxy)),
        throwsA(isA<RequestUnavailable>()),
      );
    },
  );

  test(
    'testUrl commits invalidate before publication and revoke a captured source without hot writes',
    () async {
      final original = container.read(appSettingProvider).testUrl;
      final source = await client.captureSource('application-config');
      client.hold = Completer<void>();
      client.entered = Completer<void>();
      final change = container
          .read(applicationInputActionProvider.notifier)
          .updateAppSetting(
            (value) => value.copyWith(testUrl: 'https://new.test'),
          );
      await client.entered!.future;
      expect(container.read(appSettingProvider).testUrl, original);
      client.hold!.complete();
      await change;
      expect(container.read(appSettingProvider).testUrl, 'https://new.test');
      expect(await client.configSourceCurrent(source), isFalse);
      expect(
        (await preferences.getConfig())!.appSettingProps.testUrl,
        'https://new.test',
      );
    },
  );

  test(
    'publication permission does not survive a listener microtask or receipt end',
    () async {
      final attempted = Completer<Object>();
      container.listen(appSettingProvider, (_, next) {
        if (next.testUrl != 'https://committed.test') return;
        scheduleMicrotask(() {
          try {
            container
                .read(networkSettingProvider.notifier)
                .update(
                  (value) => value.copyWith(systemProxy: !value.systemProxy),
                );
            attempted.complete(StateError('write escaped the scope'));
          } catch (error) {
            attempted.complete(error);
          }
        });
      });
      await container
          .read(applicationInputActionProvider.notifier)
          .updateAppSetting(
            (value) => value.copyWith(testUrl: 'https://committed.test'),
          );
      expect(await attempted.future, isA<RequestUnavailable>());
      expect(client.applicationInputsInvalidated, isFalse);
    },
  );
}
