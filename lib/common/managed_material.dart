import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:fl_clash/models/managed_policy.dart';

import 'managed_profile.dart';

const managedMaterialMaxBytes = 16 * 1024 * 1024;
const managedMaterialMaxNodes = 1024;
const managedMaterialMaxBindings = 128;
const managedMaterialMaxRules = 10000;

String materialDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

String profileMaterialIdentity({
  required int profileId,
  required String type,
  required String url,
  required String overwrite,
  required int? scriptId,
}) => materialDigest([profileId, type, url, overwrite, scriptId]);

bool isMaterialTemplate(Object? value) =>
    value is Map && value['schemaVersion'] == 2;

Never _invalid(String location) =>
    throw FormatException('policy.$location: invalid or unavailable material');

Map<String, dynamic> _object(Object? value, String location) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _invalid(location);
  }
  return Map<String, dynamic>.from(value);
}

List<dynamic> _list(Object? value, String location) {
  if (value is! List) _invalid(location);
  return value;
}

bool _source(Object? value) =>
    value is Map && value.length == 1 && value.containsKey('source');

String _name(Object? value, String location, {int maxLength = 256}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    _invalid(location);
  }
  return value;
}

bool _digest(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool validManagedMaterialsReceipt(Object? value) =>
    value is Map &&
    value.length == 6 &&
    value['version'] == 1 &&
    value['profileId'] is int &&
    (value['profileId'] as int) >= 0 &&
    [
      'originSha256',
      'rawSha256',
      'materialSha256',
      'bindingsSha256',
    ].every((key) => _digest(value[key]));

Map<String, dynamic> boundedMaterialCopy(Map<String, dynamic> value) {
  var remaining = managedMaterialMaxBytes;
  var items = 0;
  Object? copy(Object? item, int depth) {
    if (++items > 200000 || depth > 64) _invalid('materialBudget');
    remaining -= 2;
    if (remaining < 0) _invalid('materialBudget');
    if (item is String) {
      if (item.length > remaining) _invalid('materialBudget');
      for (final rune in item.runes) {
        remaining -= rune < 32
            ? (rune == 8 || rune == 9 || rune == 10 || rune == 12 || rune == 13
                  ? 2
                  : 6)
            : rune == 34 || rune == 92
            ? 2
            : rune < 128
            ? 1
            : rune < 2048
            ? 2
            : rune < 65536
            ? 3
            : 4;
        if (remaining < 0) _invalid('materialBudget');
      }
    } else if (item is Map) {
      final result = <String, dynamic>{};
      for (final entry in item.entries) {
        if (entry.key is! String) _invalid('material');
        final key = copy(entry.key, depth + 1)! as String;
        result[key] = copy(entry.value, depth + 1);
      }
      return result;
    } else if (item is List) {
      return [for (final entry in item) copy(entry, depth + 1)];
    } else if (item is num || item is bool || item == null) {
      remaining -= 32;
    } else {
      _invalid('material');
    }
    if (remaining < 0) _invalid('materialBudget');
    return item;
  }

  return copy(value, 0)! as Map<String, dynamic>;
}

void validateMaterialDocument(List<int> bytes) {
  if (bytes.length > managedMaterialMaxBytes) _invalid('materialBudget');
  try {
    final value = loadYaml(utf8.decode(bytes));
    boundedMaterialCopy(_object(value, 'material'));
  } catch (error) {
    if (error is FormatException &&
        error.message ==
            'policy.materialBudget: invalid or unavailable material') {
      rethrow;
    }
    _invalid('material');
  }
}

final class MaterialPolicy {
  final Map<String, dynamic> json;
  final ManagedPolicy policy;
  final Set<String> dynamicGroups;
  final Map<String, Object?>? receipt;

  MaterialPolicy(this.json, this.dynamicGroups, this.receipt)
    : policy = ManagedPolicy.fromJson(json);
}

void validateMaterialTemplate(Object? value) {
  compileManagedProfile(resolveMaterialPolicy(value, structural: true).policy);
}

MaterialPolicy resolveMaterialPolicy(
  Object? value, {
  Map<String, dynamic>? material,
  String? identity,
  int? profileId,
  String? rawSha256,
  bool structural = false,
}) {
  final template = boundedMaterialCopy(_object(value, 'material'));
  if (!isMaterialTemplate(template)) {
    return MaterialPolicy(template, const {}, null);
  }
  const keys = {
    'schemaVersion',
    'domainRules',
    'domainDefault',
    'ipRules',
    'ipDefault',
    'dnsServices',
    'bootstrapDns',
    'proxies',
    'groups',
    'listeners',
    'materialSource',
    'collections',
  };
  if (template.keys.any((key) => !keys.contains(key))) _invalid('material');
  final origin = _object(template['materialSource'], 'materialSource');
  if (origin.length != 2 ||
      origin['profileId'] is! int ||
      (origin['profileId'] as int) < 0 ||
      !_digest(origin['identity'])) {
    _invalid('materialSource');
  }
  if (!structural &&
      (profileId != origin['profileId'] ||
          identity != origin['identity'] ||
          !_digest(rawSha256) ||
          material == null)) {
    _invalid('materialSource');
  }
  final input = material == null
      ? <String, dynamic>{}
      : boundedMaterialCopy(material);
  final proxies = _object(template['proxies'], 'proxies');
  final groups = _object(template['groups'], 'groups');
  final collections = _object(template['collections'], 'collections');
  for (final value in collections.values) {
    final reference = _object(value, 'collections');
    if (reference.length != 2 ||
        !{'domain', 'ip'}.contains(reference['kind'])) {
      _invalid('collections');
    }
    _name(reference['source'], 'collections');
  }
  var bindings = collections.length;
  var rules = 0;
  final dynamicGroups = <String>{};
  final resolvedProxies = <String, dynamic>{};
  final resolvedGroups = <String, dynamic>{};
  final dummy = {
    'type': 'socks5',
    'address': '127.0.0.1',
    'port': 1,
    'udp': false,
  };

  void binding() {
    if (++bindings > managedMaterialMaxBindings) _invalid('materialBudget');
  }

  void addProxy(String id, Object? proxy) {
    if (resolvedProxies.containsKey(id) ||
        resolvedProxies.length >= managedMaterialMaxNodes) {
      _invalid('proxies');
    }
    resolvedProxies[id] = proxy;
  }

  final sourceIndexes = <String, Map<String, Map<String, dynamic>?>>{};
  Map<String, Map<String, dynamic>?> sourceIndex(String section) =>
      sourceIndexes.putIfAbsent(section, () {
        final result = <String, Map<String, dynamic>?>{};
        for (final entry in _list(input[section] ?? [], 'material')) {
          if (entry is! Map || entry['name'] is! String) continue;
          final name = entry['name'] as String;
          result[name] = result.containsKey(name)
              ? null
              : _object(entry, section);
        }
        return result;
      });
  Map<String, dynamic> named(String section, String name) {
    final entry = sourceIndex(section)[name];
    final other = section == 'proxies' ? 'proxy-groups' : 'proxies';
    if (entry == null || sourceIndex(other).containsKey(name)) {
      _invalid(section);
    }
    return entry;
  }

  Map<String, dynamic> node(String name) {
    if (structural) return Map.of(dummy);
    final entry = named('proxies', name);
    if (entry.keys.any(
      (key) => !{
        'name',
        'type',
        'server',
        'port',
        'udp',
        'username',
        'password',
      }.contains(key),
    )) {
      _invalid('proxies');
    }
    final output = <String, dynamic>{
      for (final e in entry.entries)
        if (e.key != 'name') (e.key == 'server' ? 'address' : e.key): e.value,
    };
    parseManagedProxy(output, 'policy.proxies');
    return output;
  }

  if (bindings > managedMaterialMaxBindings) _invalid('materialBudget');
  for (final entry in proxies.entries) {
    if (entry.key.startsWith('material-')) _invalid('proxies');
    if (_source(entry.value)) {
      binding();
      addProxy(entry.key, node(_name(entry.value['source'], 'proxies')));
    } else {
      addProxy(entry.key, entry.value);
    }
  }
  for (final entry in groups.entries) {
    if (!_source(entry.value)) {
      resolvedGroups[entry.key] = entry.value;
      continue;
    }
    binding();
    dynamicGroups.add(entry.key);
    final name = _name(entry.value['source'], 'groups');
    final group = structural
        ? {
            'type': 'select',
            'proxies': ['structural'],
          }
        : named('proxy-groups', name);
    if (group['type'] != 'select' ||
        group.keys.any((key) => !{'name', 'type', 'proxies'}.contains(key))) {
      _invalid('groups');
    }
    final members = _list(group['proxies'], 'groups');
    if (members.isEmpty || members.length > managedMaterialMaxNodes) {
      _invalid('groups');
    }
    final seen = <String>{};
    final ids = <String>[];
    for (final member in members) {
      final name = _name(member, 'groups');
      if (!seen.add(name) ||
          {
            'DIRECT',
            'REJECT',
            'PASS',
            'COMPATIBLE',
            'GLOBAL',
            'REMATCH',
          }.contains(name)) {
        _invalid('groups');
      }
      final id =
          'material-${materialDigest([origin['identity'], name]).substring(0, 32)}';
      if (!resolvedProxies.containsKey(id)) addProxy(id, node(name));
      ids.add(id);
    }
    resolvedGroups[entry.key] = ids;
  }

  List<Map<String, dynamic>> conditions(String id, String kind) {
    final ref = _object(collections[id], 'collections');
    if (ref.length != 2 || ref['kind'] != kind) _invalid('collections');
    final name = _name(ref['source'], 'collections');
    if (structural) {
      return [
        kind == 'domain'
            ? {'type': 'DOMAIN', 'value': 'material.invalid'}
            : {'cidr': '127.0.0.1/32'},
      ];
    }
    final provider = _object(
      _object(input['rule-providers'], 'collections')[name],
      'collections',
    );
    if (provider['type'] != 'inline' ||
        provider.keys.any(
          (key) => !{'type', 'behavior', 'payload'}.contains(key),
        )) {
      _invalid('collections');
    }
    final behavior = provider['behavior'];
    if (behavior != 'classical' && !(kind == 'ip' && behavior == 'ipcidr')) {
      _invalid('collections');
    }
    final payload = _list(provider['payload'], 'collections');
    if (payload.isEmpty || payload.length > managedMaterialMaxRules - rules) {
      _invalid('collections');
    }
    final seen = <String>{};
    return [
      for (final item in payload)
        (() {
          final text = _name(item, 'collections', maxLength: 512);
          if (!seen.add(text)) _invalid('collections');
          final parts = text.split(',');
          if (kind == 'domain' &&
              behavior == 'classical' &&
              parts.length == 2 &&
              {'DOMAIN', 'DOMAIN-SUFFIX'}.contains(parts[0])) {
            return <String, dynamic>{'type': parts[0], 'value': parts[1]};
          }
          if (kind == 'ip' && behavior == 'ipcidr' && parts.length == 1) {
            return <String, dynamic>{'cidr': text};
          }
          if (kind == 'ip' &&
              behavior == 'classical' &&
              (parts.length == 2 ||
                  parts.length == 3 && parts[2] == 'no-resolve') &&
              {'IP-CIDR', 'IP-CIDR6'}.contains(parts[0])) {
            if ((parts[0] == 'IP-CIDR6') != parts[1].contains(':')) {
              _invalid('collections');
            }
            return <String, dynamic>{'cidr': parts[1]};
          }
          _invalid('collections');
        })(),
    ];
  }

  final collectionSlots = <String, String>{};
  List<Map<String, dynamic>> expand(String field, String kind) {
    final result = <Map<String, dynamic>>[];
    for (final row in _list(template[field], field)) {
      final entry = _object(row, field);
      if (!entry.containsKey('collection')) {
        if (++rules > managedMaterialMaxRules) _invalid('materialBudget');
        result.add(entry);
        continue;
      }
      if (entry.keys.any(
        (key) => !{
          'id',
          'collection',
          'target',
          if (kind == 'domain') 'dnsService',
        }.contains(key),
      )) {
        _invalid(field);
      }
      final id = _name(entry['id'], field);
      final collection = _name(entry['collection'], 'collections');
      final values = conditions(collection, kind);
      if (rules + values.length > managedMaterialMaxRules) {
        _invalid('materialBudget');
      }
      rules += values.length;
      for (final value in values) {
        final generatedId =
            'material-${materialDigest([id, value]).substring(0, 32)}';
        collectionSlots[generatedId] = '$field:$id';
        result.add({
          'id': generatedId,
          ...value,
          'target': entry['target'],
          if (entry.containsKey('dnsService'))
            'dnsService': entry['dnsService'],
        });
      }
    }
    return result;
  }

  final output = <String, dynamic>{
    for (final entry in template.entries)
      if (!{'materialSource', 'collections'}.contains(entry.key))
        entry.key: entry.value,
    'schemaVersion': 1,
    'proxies': resolvedProxies,
    'groups': resolvedGroups,
    'domainRules': expand('domainRules', 'domain'),
    'ipRules': expand('ipRules', 'ip'),
  };
  final resolved = MaterialPolicy(
    boundedMaterialCopy(output),
    dynamicGroups,
    structural
        ? null
        : {
            'version': 1,
            'profileId': origin['profileId'],
            'originSha256': origin['identity'],
            'rawSha256': rawSha256,
            'materialSha256': materialDigest(input),
            'bindingsSha256': materialDigest(template),
          },
  );
  final seenConditions = <String, Set<String>>{};
  for (final row in resolved.policy.domainRules) {
    final slot = collectionSlots[row.id];
    if (slot != null &&
        !seenConditions
            .putIfAbsent(slot, () => {})
            .add('${row.type}:${row.value}')) {
      _invalid('collections');
    }
  }
  for (final row in resolved.policy.ipRules) {
    final slot = collectionSlots[row.id];
    if (slot != null &&
        !seenConditions.putIfAbsent(slot, () => {}).add(row.cidr)) {
      _invalid('collections');
    }
  }
  return resolved;
}
