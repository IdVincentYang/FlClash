import 'dart:convert';

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
  for (final scenario in ['reuse', 'http', 'file']) {
    final reuse = scenario == 'reuse';
    final file = scenario == 'file';
    test(
      'provider completion uses offline material before session: $scenario',
      () async {
        final core = _Core();
        final native = _Native();
        final requests = Request.scoped(
          native: native,
          isAndroid: reuse || file,
        );
        final calls = <Map<String, Object?>>[];
        final nativeCalls = <Map<String, Object?>>[];
        when(() => native.requestControl(any())).thenAnswer((invocation) async {
          final input =
              invocation.positionalArguments.single as Map<String, Object?>;
          nativeCalls.add(input);
          return {
            'state': {
              'processEpoch': 'pre-start',
              'revision': 1,
              'intentRunning': true,
              'phase': 'preparing',
            },
            'owner': 1,
            'dataset': 1,
            'sourceRevision': 0,
            'operation': 0,
          };
        });
        const use = {
          'key': 'provider-proxy:accepted',
          'kind': 'provider-proxy',
          'digest': 'accepted',
        };
        const rootUse = {'key': 'config:7', 'kind': 'config', 'digest': 'root'};
        when(() => core.sourceAcceptance(any())).thenAnswer((invocation) async {
          final input = Map<String, Object?>.from(
            invocation.positionalArguments.single as Map,
          );
          calls.add(input);
          return switch (input['action']) {
            'reuseProvider' => {
              'status': 'reused',
              'bodyBase64': base64Encode(utf8.encode('proxies: []')),
              'materialLease': 'reuse-lease',
            },
            'fetchProvider' => {
              'status': 'downloaded',
              'bodyBase64': base64Encode(utf8.encode('proxies: []')),
            },
            'review' => {
              'status': 'accepted',
              'use': use,
              'materialHash': 'accepted-body',
              'materialLease': 'review-lease',
            },
            'bindProviders' => {
              'status': 'accepted',
              'use': rootUse,
              'uses': [use],
            },
            'releaseMaterial' => {'status': 'released'},
            _ => throw StateError('unexpected source action $input'),
          };
        });
        final acceptance = SourceAcceptance(
          core: CoreController.scoped(core),
          requests: requests,
        );
        final root = AcceptedSourceRevision(
          use: rootUse,
          routing: 'source',
          materialHash: 'root-body',
          providers: [
            {
              'key': 'provider-proxy:accepted',
              'name': 'A',
              'kind': 'provider-proxy',
              'parent': {'key': 'profile:7'},
              'declaration': 'same-declaration',
              'mapping': {
                'type': file ? 'file' : 'http',
                'path': '/synthetic/local.yaml',
                'url': 'http://127.0.0.1:1/never-fetch-on-reuse',
              },
            },
          ],
        );
        final bundle = await acceptance.completeProviders(
          root: root,
          dependencies: const [],
          source: await requests.captureSource('application-config'),
          automatic: false,
          reuseAccepted: reuse,
          isCurrent: () async => true,
        );
        expect(bundle.materials.single['use'], use);
        expect(
          calls.where((call) => call['action'] == 'reuseProvider'),
          hasLength(reuse ? 1 : 0),
        );
        expect(
          calls.where((call) => call['action'] == 'fetchProvider'),
          hasLength(reuse ? 0 : 1),
        );
        expect(nativeCalls.every((call) => call['action'] == 'inspect'), true);
        expect(
          calls
              .where((call) => call['action'] == 'releaseMaterial')
              .map((call) => call['materialLease']),
          reuse ? ['reuse-lease'] : isEmpty,
        );
        if (file) {
          final fetch = calls.singleWhere(
            (call) => call['action'] == 'fetchProvider',
          );
          expect(fetch.containsKey('session'), false);
          expect(
            nativeCalls.any(
              (call) => ['begin', 'permit'].contains(call['action']),
            ),
            false,
          );
        }
        await bundle.release();
        await bundle.release();
        expect(
          calls.where(
            (call) =>
                call['action'] == 'releaseMaterial' &&
                call['materialLease'] == 'review-lease',
          ),
          hasLength(1),
        );
      },
    );
  }
}
