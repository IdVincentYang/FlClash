import 'package:fl_clash/common/managed_material.dart';
import 'package:fl_clash/models/models.dart';

import 'test_policy_drafts.dart';

String testMaterialIdentity([int profileId = 1]) => profileMaterialIdentity(
  profileId: profileId,
  type: 'url',
  url: 'http://127.0.0.1/source',
  overwrite: 'standard',
  scriptId: null,
);

PolicyDraftDocument materialDraft({String? identity}) {
  final draft = completePolicyDraft();
  draft.useMaterialSource(1, identity ?? testMaterialIdentity());
  draft.policy['proxies']['nodeA'] = {'source': 'source-a'};
  draft.policy['groups']['b'] = {'source': 'source-select'};
  draft.policy['collections'] = {
    'domains': {'source': 'source-domains', 'kind': 'domain'},
    'addresses': {'source': 'source-addresses', 'kind': 'ip'},
  };
  draft.policy['domainRules'][0] = {
    'id': 'wide',
    'collection': 'domains',
    'target': {'kind': 'proxy', 'group': 'a'},
    'dnsService': 'dnsA',
  };
  draft.policy['ipRules'][0] = {
    'id': 'loopback',
    'collection': 'addresses',
    'target': {'kind': 'direct'},
  };
  return draft;
}

Map<String, dynamic> testMaterial({bool updated = false}) => {
  'proxies': [
    {
      'name': 'source-a',
      'type': 'socks5',
      'server': '127.0.0.1',
      'port': updated ? 1083 : 1081,
      'udp': false,
      'username': updated ? 'user-b' : 'user-a',
      'password': updated ? 'pass-b' : 'pass-a',
    },
    {
      'name': updated ? 'source-c' : 'source-b',
      'type': 'socks5',
      'server': '127.0.0.1',
      'port': updated ? 1084 : 1082,
      'udp': false,
    },
  ],
  'proxy-groups': [
    {
      'name': 'source-select',
      'type': 'select',
      'proxies': [updated ? 'source-c' : 'source-b'],
    },
  ],
  'rule-providers': {
    'source-domains': {
      'type': 'inline',
      'behavior': 'classical',
      'payload': [
        'DOMAIN-SUFFIX,${updated ? 'updated' : 'example'}.test',
        'DOMAIN,ordered.test',
      ],
    },
    'source-addresses': {
      'type': 'inline',
      'behavior': 'ipcidr',
      'payload': ['127.0.0.0/8', '::1/128'],
    },
  },
};
