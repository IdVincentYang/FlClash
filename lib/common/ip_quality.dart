import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

import 'ip_lookup.dart';

Future<IpQuality> lookupIpQuality(
  Dio dio,
  String ip, {
  required CancelToken cancelToken,
}) async {
  final address = publicIp(ip);
  if (address == null) throw const IpLookupException('invalid-ip');
  final body = await readIpBody(
    dio,
    classificationUri(address.address).toString(),
    cancelToken,
    64 * 1024,
  );
  try {
    final identityKeys = <String>{};
    final json = jsonDecode(
      utf8.decode(body.bytes),
      reviver: (key, value) {
        if (key is String &&
            (key == 'status' || InternetAddress.tryParse(key) != null) &&
            !identityKeys.add(key)) {
          throw IpLookupException(
            key == 'status' ? 'invalid-response' : 'ip-mismatch',
          );
        }
        return value;
      },
    );
    if (json is! Map<String, dynamic>) {
      throw const IpLookupException('invalid-response');
    }
    try {
      return parseIpClassification(
        address.address,
        json,
      ).copyWith(retryAfter: body.retryAfter);
    } on IpLookupException catch (error) {
      if (error.code == 'source-denied' || error.code == 'source-error') {
        throw IpLookupException(
          error.code,
          retryAfter: body.retryAfter ?? const Duration(minutes: 5),
        );
      }
      rethrow;
    }
  } on FormatException {
    throw const IpLookupException('invalid-response');
  }
}

IpQuality parseIpClassification(String ip, Map<String, dynamic> json) {
  final status = json['status'];
  if (status == 'denied') throw const IpLookupException('source-denied');
  if (status == 'error') throw const IpLookupException('source-error');
  if (status != 'ok' && status != 'warning') {
    throw const IpLookupException('invalid-response');
  }
  final input = publicIp(ip);
  if (input == null) throw const IpLookupException('invalid-ip');
  Map<String, dynamic>? record;
  for (final entry in json.entries) {
    if (InternetAddress.tryParse(entry.key) == null) continue;
    final response = publicIp(entry.key);
    if (record != null ||
        response == null ||
        !listEquals(input.rawAddress, response.rawAddress) ||
        entry.value is! Map<String, dynamic>) {
      throw const IpLookupException('ip-mismatch');
    }
    record = entry.value as Map<String, dynamic>;
  }
  if (record == null) throw const IpLookupException('ip-mismatch');
  final network = record['network'] is Map
      ? record['network'] as Map
      : const {};
  final detections = record['detections'] is Map
      ? record['detections'] as Map
      : const {};
  return IpQuality(
    ip: input.address,
    source: IpQualitySource.proxyCheck,
    type: switch (network['type']) {
      'Residential' => IpType.residential,
      'Business' => IpType.business,
      'Wireless' => IpType.wireless,
      'Hosting' => IpType.hosting,
      _ => null,
    },
    organization: _text(network['organisation']),
    asn: _asn(network['asn']),
    isProxy: _flag(detections['proxy']),
    isVpn: _flag(detections['vpn']),
    isTor: _flag(detections['tor']),
    isCompromised: _flag(detections['compromised']),
    isHosting: _flag(detections['hosting']),
    isAnonymous: _flag(detections['anonymous']),
    isScraper: _flag(detections['scraper']),
    warning: status == 'warning',
    checkedAt: DateTime.now(),
  );
}

bool? _flag(Object? value) => value is bool ? value : null;
String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
int? _asn(Object? value) {
  if (value is int) return value > 0 && value <= 0xffffffff ? value : null;
  if (value is! String) return null;
  final match = RegExp(r'^(?:AS)?([0-9]+)$').firstMatch(value);
  final result = int.tryParse(match?[1] ?? '');
  return result != null && result > 0 && result <= 0xffffffff ? result : null;
}
