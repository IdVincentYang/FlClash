import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Native extends Mock implements Service {}

class _FeedbackSetup extends SetupAction {
  _FeedbackSetup(Service native, Request requests)
    : super.scoped(isAndroid: true, native: native, requests: requests);
  final messages = <String>[];
  late void Function() failed;

  @override
  void build() {}

  @override
  Future<bool> applyProfile({
    bool rebuildVpn = false,
    bool silence = false,
    bool force = false,
    bool allowSourceReview = false,
    bool allowBootstrap = false,
    Map<String, Object?>? expectedRun,
    int? setupSequence,
  }) async {
    expect(allowSourceReview, isFalse);
    expect(allowBootstrap, isFalse);
    failed();
    return false;
  }

  @override
  Future<void> reportStartFailure(String message) async =>
      messages.add(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Native native;
  late Request requests;
  late _FeedbackSetup setup;
  late ProviderContainer container;
  late Map<String, Object?> state;
  late bool needInitStatus;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('en'));
    needInitStatus = globalState.needInitStatus;
    native = _Native();
    requests = Request.scoped(native: native, isAndroid: true);
    state = {
      'processEpoch': 'quick-action-process',
      'intentRevision': 44,
      'intentRunning': true,
      'phase': 'preparing',
    };
    when(native.getRequestState).thenAnswer((_) async => Map.of(state));
    setup = _FeedbackSetup(native, requests);
    container = ProviderContainer(
      overrides: [setupActionProvider.overrideWith(() => setup)],
    );
    container.read(setupActionProvider);
  });
  tearDown(() async {
    container.dispose();
    await requests.detach();
    globalState.needInitStatus = needInitStatus;
  });

  for (final outcome in ['failed', 'newIntent', 'newProcess', 'started']) {
    test(
      'quick action reports only its current failed result: $outcome',
      () async {
        setup.failed = () {
          state = {
            ...state,
            'phase': outcome == 'started' ? 'started' : 'failed',
            if (outcome == 'newIntent') 'intentRevision': 45,
            if (outcome == 'newProcess') 'processEpoch': 'replacement-process',
          };
        };
        expect(
          await setup.setRunning(
            true,
            initialize: true,
            preparedRequestId: 44,
            source: 'tile',
          ),
          isFalse,
        );
        expect(
          setup.messages,
          outcome == 'failed'
              ? [AppLocalizations.current.backgroundStartFailed]
              : isEmpty,
        );
      },
    );
  }

  test('automatic bootstrap failure has no quick action toast', () async {
    setup.failed = () => state = {...state, 'phase': 'failed'};
    expect(
      await setup.setRunning(
        true,
        initialize: true,
        preparedRequestId: 44,
        source: 'bootstrap',
      ),
      isFalse,
    );
    expect(setup.messages, isEmpty);
  });
}
