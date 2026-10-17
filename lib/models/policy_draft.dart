import 'dart:convert';

final class ProfilePolicyDraft {
  final int profileId;
  final String rawContent;

  const ProfilePolicyDraft({required this.profileId, required this.rawContent});

  @override
  String toString() => 'ProfilePolicyDraft(profileId: $profileId, redacted)';
}

enum PolicyDraftWriteResult { saved, conflict, missingProfile, failed }

bool validPolicyDraftRelations(
  Iterable<ProfilePolicyDraft> drafts,
  Iterable<int> profileIds,
) {
  final profiles = profileIds.toSet();
  final seen = <int>{};
  return drafts.every(
    (item) => profiles.contains(item.profileId) && seen.add(item.profileId),
  );
}

final class PolicyDraftRestoreException implements Exception {
  const PolicyDraftRestoreException();

  @override
  String toString() => 'invalid_policy_draft_relations';
}

final class PolicyDraftDocument {
  final Map<String, dynamic>? _content;

  const PolicyDraftDocument._(this._content);

  factory PolicyDraftDocument.empty() {
    final content = <String, dynamic>{
      'draftVersion': 1,
      'policy': {
        'schemaVersion': 1,
        'domainRules': <dynamic>[],
        'ipRules': <dynamic>[],
        'domainDefault': null,
        'ipDefault': null,
        'dnsServices': <String, dynamic>{},
        'bootstrapDns': null,
        'proxies': <String, dynamic>{},
        'groups': <String, dynamic>{},
        'listeners': {'mixedPort': 7890, 'dnsPort': 1053},
      },
      'labels': <String, dynamic>{},
    };
    return PolicyDraftDocument._(content);
  }

  factory PolicyDraftDocument.decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (!_knownObject(value, {
            'draftVersion',
            'policy',
            'labels',
            'migration',
          }) ||
          value['draftVersion'] != 1 ||
          !_knownPolicy(value['policy']) ||
          (value['labels'] != null &&
              (value['labels'] is! Map ||
                  !(value['labels'] as Map).values.every(
                    (v) => v is String,
                  ))) ||
          (value['migration'] != null &&
              (value['migration'] is! Map ||
                  value['migration']['formatVersion'] != 1))) {
        return const PolicyDraftDocument._(null);
      }
      return PolicyDraftDocument._(Map<String, dynamic>.from(value));
    } catch (_) {
      return const PolicyDraftDocument._(null);
    }
  }

  bool get isReadOnly => _content == null;

  Map<String, dynamic> get policy => _content!['policy'];

  Map<String, dynamic>? get migration => _content?['migration'];

  String label(String id) => (_content?['labels']?[id] as String?) ?? id;

  void setLabel(String id, String value) {
    (_content!.putIfAbsent('labels', () => <String, dynamic>{}) as Map)[id] =
        value;
  }

  void removeLabel(String id) => (_content?['labels'] as Map?)?.remove(id);

  void setMigration(Map<String, dynamic> value) =>
      _content!['migration'] = value;

  List<dynamic> rows(String field) =>
      policy[field] as List<dynamic>? ?? <dynamic>[];

  Map<String, dynamic> resources(String field) =>
      policy[field] as Map<String, dynamic>? ?? <String, dynamic>{};

  String encode() => jsonEncode(_content);

  @override
  String toString() => 'PolicyDraftDocument(redacted)';

  static bool _knownObject(Object? value, Set<String> fields) =>
      value is Map<String, dynamic> && value.keys.every(fields.contains);

  static bool _optionalObject(Object? value, Set<String> fields) =>
      value == null || _knownObject(value, fields);

  static bool _knownPolicy(Object? value) {
    if (!_knownObject(value, {
          'schemaVersion',
          'domainRules',
          'ipRules',
          'domainDefault',
          'ipDefault',
          'dnsServices',
          'bootstrapDns',
          'proxies',
          'groups',
          'listeners',
        }) ||
        (value as Map)['schemaVersion'] != 1) {
      return false;
    }
    final policy = value as Map<String, dynamic>;
    bool text(Object? value) => value == null || value is String;
    bool number(Object? value) =>
        value == null || value is int || value is String;
    bool target(Object? value) =>
        _optionalObject(value, {'kind', 'group'}) &&
        (value == null ||
            (text((value as Map)['kind']) && text(value['group'])));
    bool route(Object? value) =>
        _optionalObject(value, {'target', 'dnsService'}) &&
        (value == null ||
            (target((value as Map)['target']) && text(value['dnsService'])));
    bool list(String field, Set<String> fields) {
      final items = policy[field];
      return items == null ||
          (items is List &&
              items.every(
                (v) =>
                    _knownObject(v, fields) &&
                    target((v as Map)['target']) &&
                    v.entries.every((e) => e.key == 'target' || text(e.value)),
              ));
    }

    bool objects(String field, Set<String> fields) {
      final items = policy[field];
      return items == null ||
          (items is Map<String, dynamic> &&
              items.values.every(
                (v) =>
                    _knownObject(v, fields) &&
                    (v as Map).entries.every(
                      (e) => switch (e.key) {
                        'port' => number(e.value),
                        'udp' => e.value == null || e.value is bool,
                        _ => text(e.value),
                      },
                    ),
              ));
    }

    const service = {'protocol', 'address', 'port'};
    final groups = policy['groups'];
    return list('domainRules', {
          'id',
          'type',
          'value',
          'target',
          'dnsService',
        }) &&
        list('ipRules', {'id', 'cidr', 'target'}) &&
        route(policy['domainDefault']) &&
        target(policy['ipDefault']) &&
        objects('dnsServices', service) &&
        _optionalObject(policy['bootstrapDns'], service) &&
        (policy['bootstrapDns'] == null ||
            (text(policy['bootstrapDns']['protocol']) &&
                text(policy['bootstrapDns']['address']) &&
                number(policy['bootstrapDns']['port']))) &&
        objects('proxies', {
          'type',
          'address',
          'port',
          'udp',
          'username',
          'password',
        }) &&
        (policy['proxies'] == null ||
            (policy['proxies'] as Map).values.every(
              (p) => p['type'] == null || p['type'] == 'socks5',
            )) &&
        _optionalObject(policy['listeners'], {'mixedPort', 'dnsPort'}) &&
        (policy['listeners'] == null ||
            (number(policy['listeners']['mixedPort']) &&
                number(policy['listeners']['dnsPort']))) &&
        (groups == null ||
            (groups is Map<String, dynamic> &&
                groups.values.every(
                  (v) => v is List && v.every((m) => m is String),
                )));
  }
}
