import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/preview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';

class _ActualCore extends Mock implements CoreHandlerInterface {}

class _StubSetupAction extends SetupAction {
  static String yaml = '';
  static final requested = <int>[];

  @override
  Future<String> getProfileWithId(int profileId) async {
    requested.add(profileId);
    return yaml;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    _StubSetupAction.yaml = 'mixed-port: 7890';
    _StubSetupAction.requested.clear();
    container = ProviderContainer(
      overrides: [setupActionProvider.overrideWith(_StubSetupAction.new)],
    );
    addTearDown(container.dispose);
    globalState.container = container;
  });

  // The editor blinks its caret forever, so `pumpAndSettle` never returns.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpPreview(WidgetTester tester, Profile profile) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          includeNavigatorKey: false,
          child: PreviewProfileView(profile: profile),
        ),
      ),
    );
    await settle(tester);
  }

  EditorPage editor(WidgetTester tester) {
    return tester.widget<EditorPage>(find.byType(EditorPage));
  }

  String? loaded(WidgetTester tester) {
    return tester.widget<EditorView>(find.byType(EditorView)).content;
  }

  testWidgets(
    'actual preview masks secrets and confirms each frozen full copy',
    (tester) async {
      final core = _ActualCore();
      when(core.getConfigState).thenAnswer(
        (_) async => const ConfigFact(
          runtimeEpoch: 'fixture',
          version: 1,
          owner: 1,
          token: 1,
          inputId: 'accepted',
          profileId: 7,
          profileName: 'Accepted fixture',
          phase: 'ready',
        ),
      );
      when(
        () => core.invokeMethod<Map<String, dynamic>>(
          method: CoreMethod.getAppliedInput,
        ),
      ).thenAnswer(
        (_) async => {
          'authentication': ['synthetic-user:synthetic-secret'],
          'rule': ['MATCH,REJECT'],
        },
      );
      final scoped = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ],
      );
      addTearDown(scoped.dispose);
      globalState.container = scoped;
      scoped.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final copies = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scoped,
          child: const TestApp(
            child: PreviewProfileView(
              actual: true,
              profile: Profile(
                id: 7,
                label: 'Desired label',
                autoUpdateDuration: Duration.zero,
              ),
            ),
          ),
        ),
      );
      for (var attempt = 0; loaded(tester) == null && attempt < 20; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        editor(tester).title,
        'Actual accepted configuration · Accepted fixture',
      );
      expect(editor(tester).readOnly, isTrue);
      expect(loaded(tester), isNot(contains('synthetic-secret')));
      for (final confirm in [false, true, true]) {
        final copying = editor(tester).onCopyFull!();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('including any usernames and passwords'),
          findsOneWidget,
        );
        await tester.tap(find.text(confirm ? 'Confirm' : 'Cancel').last);
        await tester.pumpAndSettle();
        await copying;
      }
      expect(copies, hasLength(2));
      expect(copies.first, contains('synthetic-user:synthetic-secret'));
      expect(copies.last, copies.first);
      verify(
        () => core.invokeMethod<Map<String, dynamic>>(
          method: CoreMethod.getAppliedInput,
        ),
      ).called(1);
    },
  );

  testWidgets('asks for the profile it was given and shows its yaml', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      const Profile(id: 7, label: 'home', autoUpdateDuration: Duration.zero),
    );

    expect(_StubSetupAction.requested, [7]);
    expect(editor(tester).title, 'Generated final configuration · home');
    expect(loaded(tester), 'mixed-port: 7890\n');
  });

  testWidgets('renders the editor before the content arrives', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          includeNavigatorKey: false,
          child: PreviewProfileView(
            profile: Profile(
              id: 7,
              label: 'home',
              autoUpdateDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );

    expect(loaded(tester), isNull);

    await settle(tester);

    expect(loaded(tester), isNotNull);
  });

  testWidgets('an unlabelled profile falls back to its id', (tester) async {
    await pumpPreview(
      tester,
      const Profile(id: 42, autoUpdateDuration: Duration.zero),
    );

    expect(editor(tester).title, 'Generated final configuration · 42');
  });

  testWidgets('a profile that resolves after disposal is dropped', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          includeNavigatorKey: false,
          child: PreviewProfileView(
            profile: Profile(
              id: 7,
              label: 'home',
              autoUpdateDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          includeNavigatorKey: false,
          child: SizedBox.shrink(),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
