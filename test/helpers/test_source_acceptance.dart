import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaml/yaml.dart';

void stubAcceptedSourceFixtures(
  CoreHandlerInterface core, {
  Future<Map<String, dynamic>> Function(String key)? project,
  Future<Map<String, dynamic>> Function(Map input)? adoptInline,
}) {
  when(() => core.sourceAcceptance(any())).thenAnswer((invocation) async {
    final input = invocation.positionalArguments.single as Map;
    if (input['action'] == 'adoptInline' && adoptInline != null) {
      return adoptInline(input);
    }
    final key = input['key'] as String;
    switch (input['action']) {
      case 'reuseCachedProviders':
        return {'status': 'missing'};
      case 'inspect':
        return {'status': 'inspected'};
      case 'reset':
        return {'status': 'reset'};
      case 'withdraw':
        return {'status': 'withdrawn'};
      case 'discard':
        return {'status': 'discarded'};
      case 'checkCode':
        return {'status': 'accepted'};
      case 'project':
        return {
          'status': 'accepted',
          'document': project != null
              ? await project(key)
              : jsonDecode(jsonEncode(loadYaml(input['body'] as String))),
        };
      case 'review':
        final body = input['bodyBase64'] is String
            ? base64Decode(input['bodyBase64'] as String)
            : utf8.encode(input['body'] as String);
        final digest = sha256.convert(body).toString();
        return {
          'status': 'accepted',
          'routing': input['routing'] ?? 'source',
          'materialHash': digest,
          'use': {
            'key': key,
            'kind': input['kind'],
            'incarnation': sha256
                .convert(utf8.encode(key))
                .toString()
                .substring(0, 48),
            'epoch': 1,
            'purposeEpoch': 1,
            'digest': digest,
          },
        };
      default:
        throw StateError('Unexpected synthetic source operation');
    }
  });
}

Future<void> writeProfileSourceFixture(Profile profile) async {
  final file = File(await appPath.getProfilePath(profile.id.toString()));
  await file.parent.create(recursive: true);
  await file.writeAsString('{}\n');
}
