import 'package:fl_clash/common/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/commit_tap.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _initial = AuthenticationProps(
  enable: true,
  username: 'user',
  password: 'pass',
);

Future<ProviderContainer> _openDialog(WidgetTester tester, Widget item) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(TestProfiles.new),
      networkSettingProvider.overrideWithBuild(
        (_, _) => const NetworkProps(authentication: _initial),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(configProvider, (_, _) {});
  globalState.container = container;
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1000, 900));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        child: Scaffold(body: ListView(children: [item])),
      ),
    ),
  );
  await tester.pump();

  await tapAndCommit(tester, find.byWidget(item));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextFormField), text);
  await tester.pumpAndSettle();
  await tapAndCommit(tester, find.text('Submit'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.isInit;
  });
  testWidgets('rejects an account that is empty once colons are stripped', (
    tester,
  ) async {
    final container = await _openDialog(
      tester,
      const AuthenticationAccountItem(),
    );

    await _submit(tester, ' :: ');

    expect(find.byType(TextFormField), findsOneWidget);
    expect(container.read(networkSettingProvider).authentication, _initial);
  });

  testWidgets('stores the account with surrounding space and colons removed', (
    tester,
  ) async {
    final container = await _openDialog(
      tester,
      const AuthenticationAccountItem(),
    );

    await _submit(tester, ' na:me ');

    expect(find.byType(TextFormField), findsNothing);
    expect(
      container.read(networkSettingProvider).authentication.username,
      'name',
    );
  });

  testWidgets('rejects a whitespace-only password', (tester) async {
    final container = await _openDialog(
      tester,
      const AuthenticationPasswordItem(),
    );

    await _submit(tester, '   ');

    expect(find.byType(TextFormField), findsOneWidget);
    expect(container.read(networkSettingProvider).authentication, _initial);
  });
}
