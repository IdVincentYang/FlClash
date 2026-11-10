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
  test(
    'cached bundle is validated once without retrieving provider bodies',
    () async {
      final core = _Core();
      final requests = Request.scoped(native: _Native(), isAndroid: false);
      final calls = <Map<String, Object?>>[];
      const rootUse = {'key': 'config:7', 'kind': 'config', 'digest': 'root'};
      const providerUse = {
        'key': 'provider-proxy:A',
        'kind': 'provider-proxy',
        'digest': 'nodes',
      };
      when(() => core.sourceAcceptance(any())).thenAnswer((invocation) async {
        final input = Map<String, Object?>.from(
          invocation.positionalArguments.single as Map,
        );
        calls.add(input);
        return switch (input['action']) {
          'reuseCachedProviders' => {
            'status': 'accepted',
            'use': rootUse,
            'uses': [providerUse],
            'providerMaterials': [
              {'name': 'A', 'use': providerUse},
            ],
            'materialLeases': ['nodes-lease'],
          },
          'releaseMaterial' => {'status': 'released'},
          _ => throw StateError('Unexpected per-provider call'),
        };
      });
      final bundle =
          await SourceAcceptance(
            core: CoreController.scoped(core),
            requests: requests,
          ).completeProviders(
            root: const AcceptedSourceRevision(
              use: rootUse,
              routing: 'source',
              materialHash: 'root-body',
              providers: [
                {'key': 'provider-proxy:A'},
              ],
            ),
            dependencies: const [],
            source: await requests.captureSource('application-config'),
            automatic: true,
            reuseAccepted: true,
            isCurrent: () async => true,
          );
      expect(bundle.materials.single['name'], 'A');
      expect(bundle.sources.single.key, 'provider-proxy:A');
      await bundle.release();
      await bundle.release();
      expect(calls.map((call) => call['action']), [
        'reuseCachedProviders',
        'releaseMaterial',
      ]);
    },
  );

  for (final scenario in ['reuse', 'http', 'file', 'http-failure']) {
    final reuse = scenario == 'reuse';
    final file = scenario == 'file';
    final failure = scenario == 'http-failure';
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
        final downloads = <bool>[];
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
          if (failure && input['action'] == 'fetchProvider') {
            throw StateError('controlled download failure');
          }
          return switch (input['action']) {
            'reuseCachedProviders' => {'status': 'missing'},
            'reuseCachedProvider' => {
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
        if (failure) {
          await expectLater(
            acceptance.completeProviders(
              root: root,
              dependencies: const [],
              source: await requests.captureSource('application-config'),
              automatic: false,
              onDownloading: downloads.add,
              isCurrent: () async => true,
            ),
            throwsA(isA<StateError>()),
          );
          expect(downloads, [true, false]);
          return;
        }
        final bundle = await acceptance.completeProviders(
          root: root,
          dependencies: const [],
          source: await requests.captureSource('application-config'),
          automatic: false,
          reuseAccepted: reuse,
          onDownloading: downloads.add,
          isCurrent: () async => true,
        );
        expect(bundle.materials.single['use'], use);
        expect(downloads, reuse || file ? isEmpty : [true, false]);
        expect(
          calls.where((call) => call['action'] == 'reuseCachedProvider'),
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
