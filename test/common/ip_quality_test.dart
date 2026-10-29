import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/ip_quality.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/ip_lookup_request.dart';

void main() {
  const ip = '1.1.1.1';
  Matcher code(String value) =>
      isA<IpLookupException>().having((e) => e.code, 'code', value);
  Map<String, dynamic> payload({
    String address = ip,
    String status = 'ok',
    Map<String, Object?> network = const {},
    Map<String, Object?> detections = const {},
  }) => {
    'status': status,
    address: {'network': network, 'detections': detections},
  };
  Future<void> lookupFixture(
    String body, {
    int status = 200,
    String? failure,
  }) async {
    final adapter = IpTestAdapter(
      (_, _) async => ResponseBody.fromString(body, status),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final query = lookupIpQuality(dio, ip, cancelToken: CancelToken());
    if (failure != null) {
      await expectLater(query, throwsA(code(failure)));
    } else {
      await query;
    }
    expect(adapter.requests, hasLength(1));
  }

  test(
    'normalizes IPv6 and mapped IPv4 response keys before identity checks',
    () {
      expect(
        parseIpClassification(
          '2606:4700:4700::1111',
          payload(address: '2606:4700:4700:0000:0000:0000:0000:1111'),
        ).ip,
        '2606:4700:4700::1111',
      );
      expect(
        parseIpClassification(ip, payload(address: '::ffff:1.1.1.1')).ip,
        ip,
      );
    },
  );
  for (final body in [
    <String, dynamic>{'status': 'ok'},
    payload(address: '8.8.8.8'),
    payload(address: 'invalid'),
    payload(address: '192.168.1.1'),
    payload(address: '::ffff:10.0.0.1'),
    {'status': 'ok', ip: <String, Object?>{}, '8.8.8.8': <String, Object?>{}},
    {
      'status': 'ok',
      ip: <String, Object?>{},
      '::ffff:1.1.1.1': <String, Object?>{},
    },
  ]) {
    test(
      'rejects missing/wrong/conflicting identity ${jsonEncode(body)}',
      () => expect(
        () => parseIpClassification(ip, body),
        throwsA(code('ip-mismatch')),
      ),
    );
  }
  test('equivalent IPv6 keys cannot hide conflicting records', () {
    expect(
      () => parseIpClassification('2606:4700:4700::1111', {
        'status': 'ok',
        '2606:4700:4700::1111': <String, Object?>{},
        '2606:4700:4700:0:0:0:0:1111': {
          'network': {'type': 'Hosting'},
        },
      }),
      throwsA(code('ip-mismatch')),
    );
  });
  for (final bad in [
    '10.0.0.1',
    '100.64.0.1',
    '127.0.0.1',
    '169.254.0.1',
    '172.16.0.1',
    '192.168.1.1',
    '192.0.2.1',
    '198.18.0.1',
    '198.51.100.1',
    '203.0.113.1',
    '224.0.0.1',
    '240.0.0.1',
    '::',
    '::1',
    'fe80::1',
    'fc00::1',
    'ff02::1',
    '2001:db8::1',
    '3fff::1',
    '3fff:0fff:ffff::1',
    '::ffff:192.168.1.1',
    '2606:4700::1%en0',
    'https://1.1.1.1',
    ' 1.1.1.1',
  ]) {
    test(
      'rejects non-public literal $bad',
      () => expect(publicIp(bad), isNull),
    );
  }
  for (final pair in {
    'Residential': IpType.residential,
    'Business': IpType.business,
    'Wireless': IpType.wireless,
    'Hosting': IpType.hosting,
  }.entries) {
    test(
      'preserves network type ${pair.key}',
      () => expect(
        parseIpClassification(ip, payload(network: {'type': pair.key})).type,
        pair.value,
      ),
    );
  }
  test('Wireless remains distinct from a mobile-only claim', () {
    final value = parseIpClassification(
      ip,
      payload(network: {'type': 'Wireless'}),
    );
    expect(value.type, IpType.wireless);
  });
  test(
    'unknown allocation and malformed flags stay unknown, even with a hosting detection',
    () {
      final value = parseIpClassification(
        ip,
        payload(
          network: {'type': 'unexpected'},
          detections: {'proxy': 'false', 'hosting': true},
        ),
      );
      expect(value.type, isNull);
      expect(value.isProxy, isNull);
      expect(value.isHosting, isTrue);
      expect(value.isTor, isNull);
    },
  );
  test('organisation/ASN and each detection retain their own meaning', () {
    final value = parseIpClassification(
      ip,
      payload(
        network: {
          'type': 'Residential',
          'organisation': 'Fixture',
          'asn': 'AS64500',
        },
        detections: {
          'proxy': false,
          'vpn': true,
          'tor': false,
          'hosting': false,
          'compromised': true,
          'anonymous': true,
          'scraper': false,
        },
      ),
    );
    expect(value.organization, 'Fixture');
    expect(value.asn, 64500);
    expect(value.isProxy, isFalse);
    expect(value.isVpn, isTrue);
    expect(value.isCompromised, isTrue);
    expect(value.isAnonymous, isTrue);
    expect(value.isScraper, isFalse);
  });
  for (final status in ['denied', 'error', 'invalid']) {
    test(
      'HTTP200 API status $status cannot succeed',
      () => lookupFixture(
        jsonEncode(payload(status: status)),
        failure: status == 'denied'
            ? 'source-denied'
            : status == 'error'
            ? 'source-error'
            : 'invalid-response',
      ),
    );
  }
  for (final (label, raw, failure) in [
    (
      'identical address',
      r'{"status":"ok","1.1.1.1":{},"1.1.1.1":{"network":{"type":"Hosting"}}}',
      'ip-mismatch',
    ),
    (
      'escaped equivalent address',
      r'{"status":"ok","1.1.1.1":{},"\u0031.1.1.1":{}}',
      'ip-mismatch',
    ),
    (
      'API status',
      r'{"status":"denied","status":"ok","1.1.1.1":{}}',
      'invalid-response',
    ),
  ]) {
    test(
      'JSON cannot overwrite duplicate $label keys',
      () => lookupFixture(raw, failure: failure),
    );
  }
  test('warning requires a matching entry and remains visible metadata', () {
    expect(
      parseIpClassification(ip, payload(status: 'warning')).warning,
      isTrue,
    );
    expect(
      () => parseIpClassification(ip, {
        'status': 'warning',
        'message': 'quota warning',
      }),
      throwsA(code('ip-mismatch')),
    );
  });
  test(
    'one HTTPS source receives canonical path IP with only fixed tag=0; links do not execute',
    () async {
      final body = payload()
        ..['docs'] = 'https://ignored.invalid/'
        ..['extra'] = {'hostname': 'ignored.invalid'};
      final adapter = IpTestAdapter(
        (_, _) async => ResponseBody.fromString(jsonEncode(body), 200),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await lookupIpQuality(dio, '::ffff:1.1.1.1', cancelToken: CancelToken());
      expect(adapter.requests, hasLength(1));
      final options = adapter.requests.single;
      expect(options.uri.toString(), 'https://proxycheck.io/v3/1.1.1.1?tag=0');
      expect(options.uri.queryParameters, {'tag': '0'});
      expect(options.followRedirects, isFalse);
      expect(options.headers['Cookie'], isNull);
      expect(options.headers['Referer'], isNull);
    },
  );
  for (final status in [206, 301, 302, 303, 307, 308, 401, 403, 429, 500]) {
    test(
      'HTTP $status fails without another source or route',
      () => lookupFixture(
        '',
        status: status,
        failure: status == 429
            ? 'rate-limited'
            : [401, 403].contains(status)
            ? 'source-denied'
            : 'http-failed',
      ),
    );
  }
  for (final sample in [
    '{"status":"ok","1.1.1.1":{',
    '[]',
    'null',
    'x' * (64 * 1024 + 1),
  ]) {
    test(
      'rejects malformed/truncated/oversized body of ${sample.length} bytes',
      () => lookupFixture(
        sample,
        failure: sample.length > 65536 ? 'body-limit' : 'invalid-response',
      ),
    );
  }
  test('read error after valid JSON cannot accept a partial answer', () async {
    final stream =
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList(utf8.encode(jsonEncode(payload()))),
        ]).transform(
          StreamTransformer<Uint8List, Uint8List>.fromHandlers(
            handleDone: (sink) {
              sink.addError(StateError('synthetic truncated body'));
              sink.close();
            },
          ),
        );
    final adapter = IpTestAdapter((_, _) async => ResponseBody(stream, 200));
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    await expectLater(
      lookupIpQuality(dio, ip, cancelToken: CancelToken()),
      throwsA(code('read-error')),
    );
  });
  for (final entry in {
    '0': 30,
    '999999999999': 86400,
    'invalid': 300,
  }.entries) {
    test('bounds Retry-After ${entry.key}', () async {
      final adapter = IpTestAdapter(
        (_, _) async => ResponseBody.fromString(
          '',
          429,
          headers: {
            'retry-after': [entry.key],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      await expectLater(
        lookupIpQuality(dio, ip, cancelToken: CancelToken()),
        throwsA(
          isA<IpLookupException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            Duration(seconds: entry.value),
          ),
        ),
      );
    });
  }
  test(
    'HTTP200 denied honors bounded Retry-After and warning retains the advice',
    () async {
      for (final status in ['denied', 'warning']) {
        final adapter = IpTestAdapter(
          (_, _) async => ResponseBody.fromString(
            jsonEncode(payload(status: status)),
            200,
            headers: {
              'retry-after': ['120'],
            },
          ),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(dio.close);
        if (status == 'denied') {
          await expectLater(
            lookupIpQuality(dio, ip, cancelToken: CancelToken()),
            throwsA(
              isA<IpLookupException>().having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 120),
              ),
            ),
          );
        } else {
          final result = await lookupIpQuality(
            dio,
            ip,
            cancelToken: CancelToken(),
          );
          expect(result.warning, isTrue);
          expect(result.retryAfter, const Duration(seconds: 120));
        }
      }
    },
  );
}
