import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

void main() {
  setUpAll(() {
    registerFallbackValue(const ServiceCheckParams(timeout: 0));
    registerFallbackValue(const OutboundIpParams(timeout: 0));
  });

  late _MockCore core;
  late CoreController controller;

  setUp(() {
    core = _MockCore();
    controller = CoreController.scoped(core);
  });

  group('ServiceProbeStatus', () {
    test('maps every status the Core can report', () {
      for (final status in ServiceProbeStatus.values) {
        expect(ServiceProbeStatus.byId(status.id), status);
      }
    });

    test('an unknown status reads as a failure rather than throwing', () {
      expect(ServiceProbeStatus.byId('brand-new'), ServiceProbeStatus.failed);
    });
  });

  group('ServiceTarget', () {
    test('ids are unique', () {
      final ids = ServiceTarget.values.map((target) => target.id).toSet();
      expect(ids, hasLength(ServiceTarget.values.length));
    });

    test('resolves an id back to its target', () {
      expect(ServiceTarget.byId('disney-plus'), ServiceTarget.disneyPlus);
      expect(ServiceTarget.byId('nope'), isNull);
    });
  });

  group('orderServiceTargets', () {
    test('an empty order keeps the declared one', () {
      expect(orderServiceTargets(const []), ServiceTarget.values);
    });

    test('drops unknown and repeated ids and appends the missing', () {
      final ordered = orderServiceTargets(const [
        'netflix',
        'retired',
        'google',
        'netflix',
      ]);

      expect(ordered.take(2), [ServiceTarget.netflix, ServiceTarget.google]);
      expect(ordered.skip(2), [
        for (final target in ServiceTarget.values)
          if (target != ServiceTarget.netflix && target != ServiceTarget.google)
            target,
      ]);
    });
  });

  group('ServiceCheck.of', () {
    test('carries the region, node and check time across', () {
      final check = ServiceCheck.of(
        const ServiceCheckItem(
          name: 'netflix',
          status: 'originals-only',
          region: 'JP',
          delay: 87,
          chains: ['JP-02', 'auto'],
          checkedAt: 1700000000000,
          coreEpoch: 7,
          picksVersion: 42,
        ),
      );

      expect(check.status, ServiceProbeStatus.originalsOnly);
      expect(check.region, 'JP');
      expect(check.delay, 87);
      expect(check.node, 'JP-02');
      expect(check.chains, ['JP-02', 'auto']);
      expect(check.coreEpoch, 7);
      expect(check.picksVersion, 42);
      expect(
        check.checkedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('drops the placeholders the Core sends for absent values', () {
      final check = ServiceCheck.of(
        const ServiceCheckItem(name: 'google', status: 'failed'),
      );

      expect(check.status, ServiceProbeStatus.failed);
      expect(check.delay, isNull);
      expect(check.region, isNull);
      expect(check.node, isNull);
      expect(check.checkedAt, isNull);
    });
  });

  group('checkServices', () {
    test('keeps requested purposes and targets separate', () async {
      when(() => core.serviceCheck(any())).thenAnswer(
        (_) async => const [
          ServiceCheckItem(
            name: 'youtube',
            purpose: 'basic',
            status: 'available',
          ),
          ServiceCheckItem(
            name: 'spotify',
            purpose: 'advanced',
            status: 'observed',
          ),
          ServiceCheckItem(
            name: 'youtube',
            purpose: 'advanced',
            status: 'observed',
          ),
        ],
      );
      final checks = await checkServices(
        controller,
        purpose: ServiceProbePurpose.advanced,
        targets: const [ServiceTarget.youtube],
      );
      expect(checks.keys, [ServiceTarget.youtube]);
      expect(checks.values.single.purpose, ServiceProbePurpose.advanced);
      expect(checks.values.single.status, ServiceProbeStatus.observed);
      final params =
          verify(() => core.serviceCheck(captureAny())).captured.single
              as ServiceCheckParams;
      expect(params.toJson()['purpose'], 'advanced');
    });

    test('wire round trip retains safe step and route metadata only', () {
      const item = ServiceCheckItem(
        name: 'disney-plus',
        purpose: 'advanced',
        status: 'observed',
        elapsed: 120,
        region: 'JP',
        coreEpoch: 3,
        picksVersion: 7,
        steps: [
          ServiceCheckStep(
            endpoint: 'session',
            httpStatus: 200,
            delay: 20,
            chains: ['Node A'],
            outcome: 'complete',
            observation: 'observed',
            region: 'JP',
            coreEpoch: 3,
            picksVersion: 7,
          ),
        ],
      );
      final wire = jsonDecode(jsonEncode(item)) as Map<String, dynamic>;
      wire['body'] = 'synthetic-secret';
      wire['authorization'] = 'synthetic-token';
      final decoded = ServiceCheckItem.fromJson(wire);
      expect(decoded, item);
      final check = ServiceCheck.of(decoded);
      expect(check.elapsed, 120);
      expect(check.steps.single.chains, ['Node A']);
      expect(check.steps.single.observation, 'observed');
      expect(check.steps.single.region, 'JP');
      expect(check.node, isNull);
      expect(check.delay, isNull);
      expect(jsonEncode(decoded), isNot(contains('synthetic-secret')));
      expect(jsonEncode(decoded), isNot(contains('synthetic-token')));
    });

    test(
      'asks the Core for the named targets and keys the answers back',
      () async {
        late ServiceCheckParams sent;
        when(() => core.serviceCheck(any())).thenAnswer((invocation) async {
          sent = invocation.positionalArguments.single as ServiceCheckParams;
          return const [
            ServiceCheckItem(name: 'claude', status: 'available', delay: 40),
            ServiceCheckItem(name: 'gemini', status: 'unsupported-region'),
          ];
        });

        final checks = await checkServices(
          controller,
          proxyName: 'HK-01',
          targets: const [ServiceTarget.claude, ServiceTarget.gemini],
        );

        expect(sent.proxyName, 'HK-01');
        expect(sent.names, ['claude', 'gemini']);
        expect(sent.timeout, probeTimeoutDuration.inMilliseconds);
        expect(
          checks[ServiceTarget.claude]?.status,
          ServiceProbeStatus.available,
        );
        expect(
          checks[ServiceTarget.gemini]?.status,
          ServiceProbeStatus.unsupportedRegion,
        );
      },
    );

    test('an empty target list makes no request', () async {
      final checks = await checkServices(controller);
      expect(checks, isEmpty);
      verifyNever(() => core.serviceCheck(any()));
    });

    test('skips a name this build does not know', () async {
      when(() => core.serviceCheck(any())).thenAnswer(
        (_) async => const [
          ServiceCheckItem(name: 'someday-tv', status: 'available'),
          ServiceCheckItem(name: 'spotify', status: 'available'),
        ],
      );

      final checks = await checkServices(
        controller,
        targets: const [ServiceTarget.spotify],
      );

      expect(checks.keys, [ServiceTarget.spotify]);
    });
  });

  group('lookupOutboundIp', () {
    test('hands the Core only the Cloudflare source', () async {
      late OutboundIpParams sent;
      when(() => core.outboundIp(any())).thenAnswer((invocation) async {
        sent = invocation.positionalArguments.single as OutboundIpParams;
        return const OutboundIpResult(
          url: 'https://www.cloudflare.com/cdn-cgi/trace',
          body: 'fl=1\nip=1.1.1.1\nloc=US\n',
        );
      });

      final ipInfo = parseOutboundIp(
        await lookupOutboundIp(controller, 'HK-01'),
      );

      expect(sent.urls, ipInfoSources.keys.toList());
      expect(sent.proxyName, 'HK-01');
      expect(sent.timeout, outboundIpTimeoutDuration.inMilliseconds);
      expect(ipInfo?.ip, '1.1.1.1');
      expect(ipInfo?.countryCode, 'US');
      expect(ipInfo?.checkedAt, isNotNull);
    });

    test(
      'rejects an unselected source instead of accepting its answer',
      () async {
        when(() => core.outboundIp(any())).thenAnswer(
          (_) async => OutboundIpResult(
            url: 'https://api.country.is',
            body: jsonEncode({'ip': '198.51.100.4', 'country': 'DE'}),
          ),
        );

        final ipInfo = parseOutboundIp(
          await lookupOutboundIp(controller, 'DE-01'),
        );

        expect(ipInfo, isNull);
      },
    );

    test('gives up on an error, an empty body or an unparseable one', () async {
      final answers = <OutboundIpResult?>[
        const OutboundIpResult(error: 'timeout'),
        const OutboundIpResult(url: 'https://api.country.is'),
        const OutboundIpResult(url: 'https://api.country.is', body: 'garbage'),
        const OutboundIpResult(
          url: 'https://unknown.example',
          body: 'ip=1.2.3.4',
        ),
        null,
      ];
      when(
        () => core.outboundIp(any()),
      ).thenAnswer((_) async => answers.removeAt(0));

      for (var attempt = 0; attempt < 5; attempt++) {
        expect(
          parseOutboundIp(await lookupOutboundIp(controller, 'HK-01')),
          isNull,
        );
      }
    });
  });
}
