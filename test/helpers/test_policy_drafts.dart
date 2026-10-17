import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';

Profile draftTestProfile(int id) => Profile(
  id: id,
  label: 'Synthetic profile $id',
  autoUpdateDuration: Duration.zero,
);

PolicyDraftDocument completePolicyDraft({bool credentials = false}) {
  final policy = jsonDecode(
    File('test/fixtures/managed_profile/policy.json').readAsStringSync(),
  );
  if (credentials) {
    policy['proxies']['nodeA']['username'] = 'synthetic-user-测试';
    policy['proxies']['nodeA']['password'] = 'synthetic-password-🙂';
  }
  return PolicyDraftDocument.decode(
    jsonEncode({'draftVersion': 1, 'policy': policy}),
  );
}

Map<String, dynamic> migrationSnapshot(
  List<String> rules, {
  String mode = 'standard',
  List<Rule> added = const [],
  List<Rule> custom = const [],
  List<String>? origins,
  String? matchTarget,
}) => {
  'formatVersion': 1,
  'mode': mode,
  'profile': {'matchTarget': matchTarget},
  'sourceBytes': base64Encode(utf8.encode(jsonEncode({'rules': rules}))),
  'applicationSettings': {
    'patch': {'mode': 'rule'},
    'overrideDns': false,
  },
  'addedRules': added.map((r) => r.toJson()).toList(),
  'customRules': custom.map((r) => r.toJson()).toList(),
  'addedOrigins': origins ?? List.filled(added.length, 'profile'),
  'customGroups': [],
  'customProxies': [],
};
