import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:mocktail/mocktail.dart';

class _Native extends Mock implements Service {}

class IpTestAdapter implements HttpClientAdapter {
  IpTestAdapter(this.respond);
  final Future<ResponseBody> Function(
    RequestOptions options,
    Future<void>? cancel,
  )
  respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) {
    requests.add(options);
    return respond(options, cancel);
  }

  @override
  void close({bool force = false}) {}
}

class IpTestRequest extends Request {
  IpTestRequest(this.adapter)
    : super.scoped(native: _Native(), isAndroid: false);
  final HttpClientAdapter adapter;
  final triggers = <bool>[];
  @override
  Future<RequestSession> begin({
    required String key,
    required String url,
    RequestMode mode = RequestMode.auto,
    String? proxy,
    bool automatic = false,
    bool diagnostic = false,
    bool allowBootstrap = false,
    bool bootstrapIfUnconfigured = false,
    String? label,
    Future<bool> Function()? sourceIsCurrent,
    String? explicitTarget,
    RequestSource? expectedSource,
    RequestSource? queuedMaterialSource,
  }) async {
    triggers.add(automatic);
    final session = await super.begin(
      key: key,
      url: url,
      mode: mode,
      proxy: proxy,
      automatic: automatic,
      diagnostic: diagnostic,
      allowBootstrap: allowBootstrap,
      bootstrapIfUnconfigured: bootstrapIfUnconfigured,
      label: label,
      sourceIsCurrent: sourceIsCurrent,
      explicitTarget: explicitTarget,
      expectedSource: expectedSource,
      queuedMaterialSource: queuedMaterialSource,
    );
    session.dio.httpClientAdapter = adapter;
    return session;
  }
}
