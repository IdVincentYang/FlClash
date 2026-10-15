import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/ip_quality.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'request_state.dart';

part 'generated/ip_quality.g.dart';

Duration? _noRetry(int retryCount, Object error) => null;

@Riverpod(keepAlive: true)
Duration ipQualityFailureCooldown(Ref ref) => const Duration(minutes: 5);

@Riverpod(retry: _noRetry)
Future<IpQuality> ipQuality(Ref ref, String ip) async {
  if (system.isAndroid) ref.watch(nativeRequestStateProvider);
  final cancelToken = CancelToken();
  final session = await request.begin(
    key: 'ipQuality:$ip',
    url: 'https://ipwho.is/$ip',
    automatic: true,
  );
  if (!ref.mounted) {
    session.close();
    throw const RequestUnavailable('request_cancelled');
  }
  ref.onDispose(session.close);
  unawaited(session.cancelToken.whenCancel.then((_) => cancelToken.cancel()));
  ref.onDispose(cancelToken.cancel);
  try {
    final quality = await lookupIpQuality(
      session.dio,
      ip,
      cancelToken: cancelToken,
    );
    await session.check();
    ref.keepAlive();
    return quality;
  } on IpQualityLookupException catch (error) {
    if (!ref.mounted) {
      rethrow;
    }
    commonPrint.log(
      'ip quality lookup failed for $ip: '
      '${error.failures.map((f) => '${f.source.label} ${f.status.name}').join(', ')}',
      logLevel: LogLevel.warning,
    );
    await session.check();
    final link = ref.keepAlive();
    final timer = Timer(ref.read(ipQualityFailureCooldownProvider), link.close);
    ref.onDispose(timer.cancel);
    rethrow;
  } finally {
    session.close();
  }
}
