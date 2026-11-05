import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Native extends Mock implements Service {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Core core;
  late Request requests;
  late List<Map<String, Object?>> calls;
  String? materialLease;
  setUp(() {
    core = _Core();
    requests = Request.scoped(native: _Native(), isAndroid: false);
    calls = [];
    materialLease = null;
    when(() => core.sourceAcceptance(any())).thenAnswer((invocation) async {
      final input = Map<String, Object?>.from(
        invocation.positionalArguments.single as Map,
      );
      calls.add(input);
      return switch (input['action']) {
        'inspect' => {
          'status': 'inspected',
          'grant': {
            'incarnation': 'a' * 48,
            'revision': 3,
            'purposes': {
              'profile': {
                'automatic': true,
                'accepted': ['b' * 64],
              },
              'provider-proxy': {
                'automatic': false,
                'accepted': ['c' * 64],
              },
            },
          },
        },
        'withdraw' => {'status': 'withdrawn'},
        'accept' => {
          'status': 'accepted',
          'materialLease': ?materialLease,
          'routing': 'source',
          'use': {
            'key': input['key'],
            'kind': input['kind'],
            'incarnation': 'a' * 48,
            'epoch': 1,
            'purposeEpoch': 1,
            'digest': 'b' * 64,
          },
        },
        _ => {
          'status': 'reviewRequired',
          'candidate': 'fixture-candidate',
          'routing': 'source',
        },
      };
    });
  });
  tearDown(() => requests.detach());

  test('accepted material lease is released once by its consumer', () async {
    materialLease = 'd' * 48;
    final service = SourceAcceptance(
      core: CoreController.scoped(core),
      requests: requests,
      confirm: (_) async =>
          const SourceReviewDecision(automatic: false, routing: 'source'),
    );
    final accepted = await service.review(
      source: await requests.captureSource('profile:7'),
      identity: 'a' * 64,
      settings: const {},
      body: 'rules: [MATCH,REJECT]',
      label: 'fixture',
      location: '',
      kind: 'profile',
    );
    expect(calls.where((call) => call['action'] == 'releaseMaterial'), isEmpty);
    await accepted.release();
    await accepted.release();
    final released = calls
        .where((call) => call['action'] == 'releaseMaterial')
        .single;
    expect(released['materialLease'], materialLease);
  });

  test(
    'late qualification releases an already received material lease',
    () async {
      var current = true;
      when(() => core.sourceAcceptance(any())).thenAnswer((invocation) async {
        final input = Map<String, Object?>.from(
          invocation.positionalArguments.single as Map,
        );
        calls.add(input);
        if (input['action'] == 'review') {
          current = false;
          return {
            'status': 'accepted',
            'materialLease': 'd' * 48,
            'use': <String, Object?>{},
          };
        }
        return {'status': 'released'};
      });
      final service = SourceAcceptance(
        core: CoreController.scoped(core),
        requests: requests,
      );
      await expectLater(
        service.review(
          source: await requests.captureSource('profile:7'),
          identity: 'a' * 64,
          settings: const {},
          body: 'rules: [MATCH,REJECT]',
          label: 'fixture',
          location: '',
          kind: 'profile',
          isCurrent: () async => current,
        ),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(calls.map((call) => call['action']), [
        'review',
        'releaseMaterial',
      ]);
    },
  );

  test('automatic review never opens a permission prompt', () async {
    final service = SourceAcceptance(
      core: CoreController.scoped(core),
      requests: requests,
      confirm: (_) async => throw StateError('automatic prompt opened'),
    );
    await expectLater(
      service.review(
        source: await requests.captureSource('profile:7'),
        identity: 'a' * 64,
        settings: const {},
        body: 'rules: [MATCH,REJECT]',
        label: 'fixture',
        location: '',
        kind: 'profile',
        automatic: true,
      ),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(calls.map((call) => call['action']), ['review']);
  });

  test(
    'final composition carries the same accepted ancestors into its decision',
    () async {
      final uses = [
        <String, Object?>{
          'key': 'profile:7',
          'kind': 'profile',
          'incarnation': 'a' * 48,
          'epoch': 1,
          'purposeEpoch': 1,
          'digest': 'c' * 64,
        },
      ];
      final service = SourceAcceptance(
        core: CoreController.scoped(core),
        requests: requests,
        confirm: (review) async {
          expect(review.origin, 'https://example.invalid');
          return const SourceReviewDecision(
            automatic: false,
            routing: 'source',
          );
        },
      );
      final result = await service.review(
        source: await requests.captureSource('application-config'),
        entityKey: 'config:7',
        identity: 'a' * 64,
        settings: const {},
        body: 'rules: [MATCH,REJECT]',
        label: 'fixture',
        location:
            'https://user:password@example.invalid/private?token=synthetic',
        kind: 'config',
        uses: uses,
      );
      expect(result.use['key'], 'config:7');
      expect(calls.map((call) => call['action']), ['review', 'accept']);
      for (final call in calls) {
        expect(call['uses'], uses);
      }
      expect(calls.last['candidate'], 'fixture-candidate');
    },
  );

  test('a superseded visible decision cannot accept its candidate', () async {
    var current = true;
    final service = SourceAcceptance(
      core: CoreController.scoped(core),
      requests: requests,
      confirm: (_) async {
        current = false;
        return const SourceReviewDecision(automatic: true, routing: 'source');
      },
    );
    await expectLater(
      service.review(
        source: await requests.captureSource('profile:7'),
        identity: 'a' * 64,
        settings: const {},
        body: 'rules: [MATCH,REJECT]',
        label: 'fixture',
        location: '',
        kind: 'profile',
        isCurrent: () async => current,
      ),
      throwsA(isA<RequestUnavailable>()),
    );
    expect(calls.map((call) => call['action']), ['review']);
  });

  test(
    'withdrawal binds the displayed purpose and rejects a stale source',
    () async {
      final service = SourceAcceptance(
        core: CoreController.scoped(core),
        requests: requests,
        confirm: (_) async => null,
      );
      final permissions = await service.permissions(
        source: await requests.captureSource('profile:7'),
        kind: 'profile',
      );
      final nodes = permissions.singleWhere(
        (item) => item.kind == 'provider-proxy',
      );
      await service.withdraw(nodes, stopUse: true);
      expect(calls.last, containsPair('kind', 'provider-proxy'));
      expect(calls.last, containsPair('incarnation', 'a' * 48));
      expect(calls.last, containsPair('revision', 3));
      expect(calls.last, containsPair('stopUse', true));
      await requests.invalidate('profile:7');
      final count = calls.length;
      await expectLater(
        service.withdraw(nodes, stopUse: true),
        throwsA(isA<RequestUnavailable>()),
      );
      expect(calls, hasLength(count));
    },
  );
}
