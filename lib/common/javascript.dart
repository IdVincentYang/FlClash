import 'dart:convert';

import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_api/rust_api.dart';

typedef ScriptEvaluator =
    Future<String> Function({required String script, required String config});

@visibleForTesting
ScriptEvaluator scriptEvaluator = evaluateScript;

Future<Map<String, dynamic>> handleEvaluate(
  String scriptContent,
  Map<String, dynamic> config, {
  int? maxBytes,
}) => _evaluate(scriptContent, config, maxBytes: maxBytes);

Future<Map<String, dynamic>> handleAcceptedEvaluate(
  String scriptContent,
  Map<String, dynamic> config, {
  required ScriptExecutionPermit? permit,
  int? maxBytes,
}) async {
  if (permit == null) {
    throw MessageException(currentAppLocalizations.sourceReviewRequired);
  }
  await permit.verify(scriptContent);
  return _evaluate(
    scriptContent,
    config,
    maxBytes: maxBytes,
    afterEvaluation: () => permit.verify(scriptContent),
  );
}

Future<Map<String, dynamic>> _evaluate(
  String scriptContent,
  Map<String, dynamic> config, {
  int? maxBytes,
  Future<void> Function()? afterEvaluation,
}) async {
  if (config['proxy-providers'] == null) {
    config['proxy-providers'] = {};
  }
  final String result;
  try {
    result = await scriptEvaluator(
      script: scriptContent,
      config: json.encode(config),
    );
  } catch (e) {
    throw MessageException(e.toString());
  }
  if (maxBytes != null &&
      (result.length > maxBytes || utf8.encode(result).length > maxBytes)) {
    throw const MessageException('script material exceeds byte budget');
  }
  await afterEvaluation?.call();
  final decoded = json.decode(result);
  if (decoded is! Map<String, dynamic>) {
    throw const MessageException(
      'script did not return a configuration object',
    );
  }
  return decoded;
}
