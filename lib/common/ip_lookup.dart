import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'constant.dart';
import 'request.dart';

const outboundIpUrl = 'https://www.cloudflare.com/cdn-cgi/trace';
const ipClassificationUrl = 'https://proxycheck.io';

Uri classificationUri(String ip) => Uri.parse(
  ipClassificationUrl,
).replace(path: '/v3/$ip', queryParameters: {'tag': '0'});

class IpLookupException implements Exception {
  const IpLookupException(this.code, {this.retryAfter});
  final String code;
  final Duration? retryAfter;

  @override
  String toString() => 'IP lookup: $code';
}

/// Normalization precedes range checks so mapped IPv4 cannot hide private IPs.
InternetAddress? publicIp(String text) {
  if (text != text.trim() || text.contains('%')) return null;
  final parsed = InternetAddress.tryParse(text);
  if (parsed == null) return null;
  var bytes = parsed.rawAddress;
  if (bytes.length == 16 &&
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 255 &&
      bytes[11] == 255) {
    bytes = bytes.sublist(12);
  }
  if (bytes.length == 4) {
    final a = bytes[0], b = bytes[1], c = bytes[2];
    if (a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        a == 100 && b >= 64 && b <= 127 ||
        a == 169 && b == 254 ||
        a == 172 && b >= 16 && b <= 31 ||
        a == 192 &&
            (b == 168 || b == 0 && (c == 0 || c == 2) || b == 88 && c == 99) ||
        a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) ||
        a == 203 && b == 0 && c == 113) {
      return null;
    }
  } else {
    if ((bytes[0] & 0xe0) != 0x20 ||
        bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            (bytes[2] < 2 || bytes[2] == 0x0d && bytes[3] == 0xb8) ||
        bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] < 0x10) {
      return null;
    }
  }
  return InternetAddress.fromRawAddress(bytes);
}

Future<T> withIpSession<T>({
  required Request client,
  required String key,
  required String url,
  required Duration timeout,
  required bool Function() current,
  required Future<T> Function(RequestSession session, Duration remaining)
  action,
  bool automatic = false,
  String? explicitTarget,
}) async {
  final clock = Stopwatch()..start();
  var expired = false;
  var finished = false;
  bool timedOut() => expired || clock.elapsed >= timeout;
  bool eligible() => !timedOut() && !finished && current();
  final timer = Timer(timeout, () {
    expired = true;
    client.cancelKey(key);
  });
  try {
    return await client
        .withSession(
          key: key,
          url: url,
          automatic: automatic,
          explicitTarget: explicitTarget,
          diagnostic: true,
          sourceIsCurrent: () async => eligible(),
          action: (session) async {
            if (!eligible()) throw const IpLookupException('cancelled');
            await session.check();
            if (!eligible()) throw const IpLookupException('cancelled');
            final left = timeout - clock.elapsed;
            if (left <= Duration.zero) throw const IpLookupException('timeout');
            final value = await action(session, left);
            await session.check();
            if (!eligible()) throw const IpLookupException('cancelled');
            return value;
          },
        )
        .timeout(
          timeout,
          onTimeout: () {
            expired = true;
            client.cancelKey(key);
            throw const IpLookupException('timeout');
          },
        );
  } catch (error) {
    if (timedOut()) throw const IpLookupException('timeout');
    if (error is IpLookupException) rethrow;
    if (error is DioException &&
        (error.type == DioExceptionType.badCertificate ||
            error.error is TlsException)) {
      throw const IpLookupException('tls-failed');
    }
    if (error is RequestUnavailable) {
      throw IpLookupException(
        error.code == 'request_cancelled' ? 'cancelled' : 'route-unavailable',
      );
    }
    if (error is DioException &&
        error.type == DioExceptionType.cancel &&
        error.error is! Error) {
      throw const IpLookupException('cancelled');
    }
    throw IpLookupException(current() ? 'failed' : 'cancelled');
  } finally {
    finished = true;
    timer.cancel();
    clock.stop();
  }
}

Future<({List<int> bytes, Duration? retryAfter})> readIpBody(
  Dio dio,
  String url,
  CancelToken token,
  int limit,
) async {
  final response = await dio.get<ResponseBody>(
    url,
    cancelToken: token,
    options: Options(
      responseType: ResponseType.stream,
      followRedirects: false,
      validateStatus: (_) => true,
      headers: {'User-Agent': browserUa, 'Cookie': null, 'Referer': null},
    ),
  );
  final retryAfter = ipRetryAfter(response.headers);
  if (response.statusCode != HttpStatus.ok) {
    token.cancel();
    if ([401, 403, 429].contains(response.statusCode)) {
      throw IpLookupException(
        response.statusCode == 429 ? 'rate-limited' : 'source-denied',
        retryAfter: retryAfter ?? const Duration(minutes: 5),
      );
    }
    throw const IpLookupException('http-failed');
  }
  final body = response.data;
  if (body == null) throw const IpLookupException('invalid-response');
  final bytes = <int>[];
  try {
    await for (final chunk in body.stream) {
      if (token.isCancelled) throw const IpLookupException('cancelled');
      if (bytes.length + chunk.length > limit) {
        token.cancel();
        throw const IpLookupException('body-limit');
      }
      bytes.addAll(chunk);
    }
    if (token.isCancelled) throw const IpLookupException('cancelled');
  } catch (error) {
    token.cancel();
    if (error is IpLookupException) rethrow;
    throw const IpLookupException('read-error');
  }
  return (bytes: bytes, retryAfter: retryAfter);
}

Duration? ipRetryAfter(Headers headers) {
  final values = headers[HttpHeaders.retryAfterHeader];
  if (values == null) return null;
  final raw = values.length == 1 ? values.single : '';
  var seconds = int.tryParse(raw);
  if (seconds == null) {
    try {
      seconds = HttpDate.parse(
        raw,
      ).difference(DateTime.now().toUtc()).inSeconds;
    } on HttpException {
      seconds = null;
    } on FormatException {
      seconds = null;
    }
  }
  return Duration(seconds: (seconds ?? 300).clamp(30, 86400));
}
