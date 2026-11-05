import 'dart:convert';
import 'dart:ui';

import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/javascript.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _SourceCore extends Mock implements CoreHandlerInterface {}

class _SourceNative extends Mock implements Service {}

void main() {
  late List<({String script, String config})> calls;
  final engine = scriptEvaluator;
  late ScriptExecutionPermit permit;
  late _SourceCore core;
  late Request requests;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() async {
    calls = [];
    requests = Request.scoped(native: _SourceNative(), isAndroid: false);
    core = _SourceCore();
    when(() => core.sourceAcceptance(any())).thenAnswer((invocation) async {
      final input = invocation.positionalArguments.single as Map;
      return {
        'status': 'accepted',
        'routing': 'source',
        if (input['action'] == 'review')
          'use': {
            'key': 'script:1',
            'incarnation': 'fixture',
            'epoch': 1,
            'digest': SourceAcceptance.fingerprint('fixture'),
          },
      };
    });
    final accepted =
        await SourceAcceptance(
          core: CoreController.scoped(core),
          requests: requests,
          confirm: (_) async => throw StateError('unexpected confirmation'),
        ).review(
          source: await requests.captureSource('script:1'),
          identity: SourceAcceptance.fingerprint('fixture'),
          settings: const {},
          body: 'main',
          label: 'fixture',
          location: '',
          kind: 'script',
        );
    permit = accepted.scriptPermit!;
  });

  tearDown(() async {
    scriptEvaluator = engine;
    await requests.detach();
  });

  void answerWith(String result) {
    scriptEvaluator = ({required String script, required String config}) async {
      calls.add((script: script, config: config));
      return result;
    };
  }

  test(
    'passes the profile as JSON and returns what the script produced',
    () async {
      answerWith(json.encode({'mode': 'global'}));

      final result = await handleAcceptedEvaluate('main', {
        'mode': 'rule',
      }, permit: permit);

      expect(result, {'mode': 'global'});
      expect(json.decode(calls.single.config)['mode'], 'rule');
      expect(calls.single.script, 'main');
    },
  );

  test('gives the script an empty proxy-providers map to work with', () async {
    answerWith(json.encode({'mode': 'rule'}));

    await handleAcceptedEvaluate('main', {'mode': 'rule'}, permit: permit);

    expect(json.decode(calls.single.config)['proxy-providers'], isEmpty);
  });

  test('reports what the engine threw', () async {
    scriptEvaluator = ({required String script, required String config}) async {
      throw Exception('ReferenceError: proxies is not defined');
    };

    await expectLater(
      handleAcceptedEvaluate('main', {}, permit: permit),
      throwsA(
        isA<MessageException>().having(
          (error) => error.message,
          'message',
          contains('ReferenceError'),
        ),
      ),
    );
  });

  test('material output budget rejects before JSON decoding', () async {
    answerWith('x' * 100);
    await expectLater(
      handleAcceptedEvaluate('main', {}, permit: permit, maxBytes: 10),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'budget',
          contains('byte budget'),
        ),
      ),
    );
  });

  test('rejects a result that is not a configuration object', () async {
    answerWith(json.encode([1, 2, 3]));

    await expectLater(
      handleAcceptedEvaluate('main', {}, permit: permit),
      throwsA(isA<MessageException>()),
    );
  });

  test('unaccepted code never reaches the evaluator', () async {
    answerWith('{}');
    await expectLater(
      handleAcceptedEvaluate('main', {}, permit: null),
      throwsA(isA<MessageException>()),
    );
    expect(calls, isEmpty);
  });

  test('a code permit cannot execute different bytes', () async {
    answerWith('{}');
    await expectLater(
      handleAcceptedEvaluate('changed main', {}, permit: permit),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(calls, isEmpty);
  });

  test(
    'legacy evaluation preserves the existing non-Android contract',
    () async {
      answerWith('{"mode":"global"}');
      expect(await handleEvaluate('legacy', {}), {'mode': 'global'});
      expect(calls.single.script, 'legacy');
    },
  );
}
