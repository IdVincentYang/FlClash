import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/managed_policy.dart';
import 'package:fl_clash/models/models.dart';
import 'package:yaml/yaml.dart';

final class PolicyMigrationIssue {
  final String code;
  final int? index;
  final String? field;

  const PolicyMigrationIssue(this.code, [this.index, this.field]);

  String get location =>
      field ?? (index == null ? 'migration' : 'rules[$index]');

  @override
  String toString() => 'PolicyMigrationIssue($code, $location)';
}

final class PolicyMigrationAnalysis {
  final List<String> rules;
  final List<String> origins;
  final List<PolicyMigrationIssue> issues;
  final Map<String, dynamic> proxies;
  final Map<String, dynamic> groups;
  final Map<String, String> targets;
  final Map<String, String> labels;

  const PolicyMigrationAnalysis({
    this.rules = const [],
    this.origins = const [],
    this.issues = const [],
    this.proxies = const {},
    this.groups = const {},
    this.targets = const {},
    this.labels = const {},
  });

  @override
  String toString() => 'PolicyMigrationAnalysis(redacted)';
}

List<PolicyMigrationIssue> policyMigrationIssues(
  Map<String, dynamic>? snapshot,
) => analyzePolicyMigration(snapshot).issues;

Future<PolicyDraftDocument> captureProfilePolicyDraft(
  int profileId, {
  required Map<String, dynamic> Function() applicationSettings,
}) {
  return dataMutations.run(
    () => database.transaction(() async {
      final raw = await (database.select(
        database.profiles,
      )..where((t) => t.id.equals(profileId))).getSingleOrNull();
      if (raw == null) throw const FileSystemException('profile_missing');
      final profile = raw.toProfile();
      final bytes = await File(
        await appPath.getProfilePath('$profileId'),
      ).readAsBytes();
      final links =
          await (database.select(database.profileRuleLinks)..where(
                (t) => t.profileId.isNull() | t.profileId.equals(profileId),
              ))
              .get();
      final added = profile.overwriteType == OverwriteType.standard
          ? await database.rulesDao.queryAddedRules(profileId).get()
          : <Rule>[];
      final custom = profile.overwriteType == OverwriteType.custom
          ? await database.rulesDao.queryProfileCustomRules(profileId).get()
          : <Rule>[];
      final profileAdded = links
          .where((l) => l.profileId == profileId && l.scene == RuleScene.added)
          .map((l) => l.ruleId)
          .toSet();
      final usedProfile = <int>{};
      final relatedRuleIds = links.map((l) => l.ruleId).toSet();
      final groups = profile.overwriteType == OverwriteType.custom
          ? await database.proxyGroupsDao.query(profileId).get()
          : <ProxyGroup>[];
      final proxies =
          profile.overwriteType == OverwriteType.custom && feature.customProxies
          ? await database.customProxiesDao.query(profileId).get()
          : <CustomProxy>[];
      final scriptPath = profile.scriptId == null
          ? null
          : await appPath.getScriptPath('${profile.scriptId}');
      final script = scriptPath != null && await File(scriptPath).exists()
          ? base64Encode(await File(scriptPath).readAsBytes())
          : null;
      final providerNames = <String>{
        for (final group in groups) ...?group.use,
        for (final rule in custom)
          if (rule.rawValue.startsWith('RULE-SET,'))
            rule.rawValue.split(',')[1],
      };
      final snapshot = <String, dynamic>{
        'formatVersion': 1,
        'profile': profile.toJson(),
        'mode': profile.overwriteType.name,
        'sourceBytes': base64Encode(bytes),
        'applicationSettings': applicationSettings(),
        'addedRules': added.map((r) => r.toJson()).toList(),
        'addedOrigins': [
          for (final rule in added)
            profileAdded.contains(rule.id) && usedProfile.add(rule.id)
                ? 'profile'
                : 'global',
        ],
        'customRules': custom.map((r) => r.toJson()).toList(),
        'links': [
          for (final link in links)
            {
              'id': link.id,
              'profileId': link.profileId,
              'ruleId': link.ruleId,
              'scene': link.scene?.name,
              'order': link.order,
            },
        ],
        'allRules':
            await (database.select(database.rules)
                  ..where((t) => t.id.isIn(relatedRuleIds)))
                .map((r) => r.toRule().toJson())
                .get(),
        'customGroups': groups.map((g) => g.definition).toList(),
        'customProxies': proxies.map((p) => p.definition).toList(),
        'providers': (await database.clashProvidersDao.queryAll().get())
            .where((p) => providerNames.contains(p.label))
            .map(
              (p) => {
                'id': p.id,
                'kind': p.kind.name,
                'label': p.label,
                'url': p.url,
                'behavior': p.behavior?.name,
                'format': p.format?.name,
                'order': p.order,
              },
            )
            .toList(),
        'scriptBytes': script,
      };
      return policyDraftFromSnapshot(jsonDecode(jsonEncode(snapshot)));
    }),
  );
}

PolicyDraftDocument policyDraftFromSnapshot(Map<String, dynamic> snapshot) {
  final draft = PolicyDraftDocument.empty()..setMigration(snapshot);
  final analysis = analyzePolicyMigration(snapshot);
  draft.policy['proxies'] = Map<String, dynamic>.from(analysis.proxies);
  draft.policy['groups'] = Map<String, dynamic>.from(analysis.groups);
  analysis.labels.forEach(draft.setLabel);
  Map<String, dynamic>? target(String value) => switch (value) {
    'DIRECT' => {'kind': 'direct'},
    'REJECT' => {'kind': 'reject'},
    _ =>
      analysis.targets[value] == null
          ? null
          : {'kind': 'proxy', 'group': analysis.targets[value]},
  };
  final domains = <Map<String, dynamic>>[];
  final ips = <Map<String, dynamic>>[];
  for (final (index, raw) in analysis.rules.indexed) {
    final parts = raw.split(',').map((p) => p.trim()).toList();
    if (parts.length == 3 && ['DOMAIN', 'DOMAIN-SUFFIX'].contains(parts[0])) {
      domains.add({
        'id': 'domain$index',
        'type': parts[0],
        'value': parts[1],
        'target': target(parts[2]),
      });
    } else if (parts.length >= 3 &&
        ['IP-CIDR', 'IP-CIDR6'].contains(parts[0])) {
      ips.add({'id': 'ip$index', 'cidr': parts[1], 'target': target(parts[2])});
    }
  }
  draft.policy['domainRules'] = domains;
  draft.policy['ipRules'] = ips;
  return draft;
}

PolicyMigrationAnalysis analyzePolicyMigration(Map<String, dynamic>? snapshot) {
  if (snapshot == null) return const PolicyMigrationAnalysis();
  try {
    if (snapshot['formatVersion'] != 1 ||
        snapshot['profile'] is! Map ||
        snapshot['addedRules'] is! List ||
        snapshot['customRules'] is! List ||
        snapshot['addedOrigins'] is! List ||
        snapshot['customGroups'] is! List ||
        snapshot['customProxies'] is! List) {
      throw const FormatException();
    }
    final source = jsonDecode(
      jsonEncode(
        loadYaml(utf8.decode(base64Decode(snapshot['sourceBytes'] as String))),
      ),
    );
    if (source is! Map<String, dynamic>) throw const FormatException();
    final mode = snapshot['mode'];
    if (mode == 'script') {
      return const PolicyMigrationAnalysis(
        issues: [PolicyMigrationIssue('script')],
      );
    }
    if (mode != 'standard' && mode != 'custom') throw const FormatException();
    final added = (snapshot['addedRules'] as List)
        .map((r) => Rule.fromJson(Map<String, Object?>.from(r)))
        .toList();
    final custom = (snapshot['customRules'] as List)
        .map((r) => Rule.fromJson(Map<String, Object?>.from(r)))
        .toList();
    final addedOrigins = List<String>.from(snapshot['addedOrigins']);
    if (added.length != addedOrigins.length ||
        !addedOrigins.every({'profile', 'global'}.contains)) {
      throw const FormatException();
    }
    final activeCustom = mode == 'custom' ? custom : <Rule>[];
    final activeAdded = mode == 'standard' ? added : <Rule>[];
    final rules = composeProfileRules(
      sourceRules: source['rules'],
      customRules: activeCustom,
      addedRules: activeAdded,
      matchTarget: mode == 'standard'
          ? snapshot['profile']['matchTarget']
          : null,
    );
    final origins = activeCustom.isNotEmpty
        ? List.filled(rules.length, 'custom')
        : [
            ...(mode == 'standard' ? addedOrigins : <String>[]),
            ...List.filled(rules.length - activeAdded.length, 'source'),
          ];
    final issues = <PolicyMigrationIssue>[];
    const knownFields = {
      'mode',
      'rules',
      'proxies',
      'proxy-groups',
      'dns',
      'port',
      'socks-port',
      'mixed-port',
      'redir-port',
      'tproxy-port',
      'allow-lan',
      'bind-address',
      'log-level',
      'ipv6',
      'external-controller',
      'external-ui',
      'secret',
      'profile',
      'sniffer',
      'hosts',
      'tun',
      'ntp',
      'proxy-providers',
      'rule-providers',
    };
    if (source.keys.any((key) => !knownFields.contains(key))) {
      issues.add(const PolicyMigrationIssue('configuration', null, 'source'));
    }
    final appSettings = snapshot['applicationSettings'];
    if (appSettings is! Map ||
        appSettings['patch'] is! Map ||
        appSettings['patch']['mode'] != 'rule') {
      issues.add(
        const PolicyMigrationIssue(
          'configuration',
          null,
          'applicationSettings.patch.mode',
        ),
      );
    }
    if (source['mode'] != null && source['mode'] != 'rule') {
      issues.add(
        const PolicyMigrationIssue('configuration', null, 'source.mode'),
      );
    }
    for (final config in [
      source,
      if (appSettings is Map && appSettings['patch'] is Map)
        appSettings['patch'] as Map,
    ]) {
      final path = identical(config, source)
          ? 'source'
          : 'applicationSettings.patch';
      for (final field in [
        'dns',
        'sniffer',
        'tun',
        'ntp',
        'hosts',
        'profile',
        'proxy-providers',
        'rule-providers',
      ]) {
        if (config[field] != null && config[field] is! Map) {
          issues.add(
            PolicyMigrationIssue('configuration', null, '$path.$field'),
          );
        }
      }
      for (final field in ['sniffer', 'tun', 'ntp']) {
        final value = config[field];
        if (value is Map &&
            (value['enable'] == true ||
                value['write-to-system'] == true ||
                (value['enable'] != null && value['enable'] is! bool))) {
          issues.add(
            PolicyMigrationIssue('configuration', null, '$path.$field'),
          );
        }
      }
      for (final field in ['hosts', 'proxy-providers', 'rule-providers']) {
        if (config[field] is Map && (config[field] as Map).isNotEmpty) {
          issues.add(
            PolicyMigrationIssue('configuration', null, '$path.$field'),
          );
        }
      }
    }
    final proxies = <String, dynamic>{};
    final groups = <String, dynamic>{};
    final proxyNames = <String, String>{};
    final targets = <String, String>{};
    final labels = <String, String>{};
    final rawProxies = (snapshot['customProxies'] as List).isNotEmpty
        ? snapshot['customProxies']
        : source['proxies'] ?? [];
    if (rawProxies is! List) {
      issues.add(const PolicyMigrationIssue('resources', null, 'proxies'));
    }
    for (final (i, item) in (rawProxies is List ? rawProxies : []).indexed) {
      if (item is! Map ||
          item['type'] != 'socks5' ||
          item['name'] is! String ||
          !item.keys.every(
            {
              'name',
              'type',
              'server',
              'port',
              'udp',
              'username',
              'password',
            }.contains,
          )) {
        issues.add(PolicyMigrationIssue('resources', null, 'proxies[$i]'));
        continue;
      }
      final id = 'proxy$i';
      if (proxyNames.containsKey(item['name'])) {
        issues.add(PolicyMigrationIssue('resources', null, 'proxies[$i].name'));
      }
      proxyNames[item['name']] = id;
      labels[id] = item['name'];
      final projected = {
        'type': 'socks5',
        'address': item['server'],
        'port': item['port'],
        'udp': item.containsKey('udp') ? item['udp'] : false,
        if (item.containsKey('username')) 'username': item['username'],
        if (item.containsKey('password')) 'password': item['password'],
      };
      try {
        parseManagedProxy(projected, 'proxies[$i]');
      } on FormatException {
        issues.add(PolicyMigrationIssue('resources', null, 'proxies[$i]'));
      }
      proxies[id] = projected;
    }
    final rawGroups = (snapshot['customGroups'] as List).isNotEmpty
        ? snapshot['customGroups']
        : source['proxy-groups'] ?? [];
    if (rawGroups is! List) {
      issues.add(const PolicyMigrationIssue('resources', null, 'groups'));
    }
    for (final (i, item) in (rawGroups is List ? rawGroups : []).indexed) {
      if (item is! Map ||
          item['type'] != 'select' ||
          item['name'] is! String ||
          item['proxies'] is! List ||
          !item.keys.every({'name', 'type', 'proxies'}.contains) ||
          !(item['proxies'] as List).every(proxyNames.containsKey)) {
        issues.add(PolicyMigrationIssue('resources', null, 'groups[$i]'));
        continue;
      }
      final id = 'group$i';
      if (targets.containsKey(item['name'])) {
        issues.add(PolicyMigrationIssue('resources', null, 'groups[$i].name'));
      }
      targets[item['name']] = id;
      labels[id] = item['name'];
      final members = [for (final name in item['proxies']) proxyNames[name]];
      try {
        parseManagedProxyGroup(members, 'groups[$i]');
      } on FormatException {
        issues.add(PolicyMigrationIssue('resources', null, 'groups[$i]'));
      }
      groups[id] = members;
    }
    bool knownTarget(String name) =>
        name == 'DIRECT' || name == 'REJECT' || targets.containsKey(name);
    for (final (index, raw) in rules.indexed) {
      final parts = raw.split(',').map((s) => s.trim()).toList();
      final domain =
          parts.length == 3 && ['DOMAIN', 'DOMAIN-SUFFIX'].contains(parts[0]);
      final ip =
          (parts.length == 3 ||
              (parts.length == 4 && parts[3] == 'no-resolve')) &&
          ['IP-CIDR', 'IP-CIDR6'].contains(parts[0]);
      final match = parts.length == 2 && parts[0] == 'MATCH';
      if (ip) issues.add(PolicyMigrationIssue('ip', index));
      if (match && index != rules.length - 1) {
        issues.add(PolicyMigrationIssue('intermediate_match', index));
      }
      if ((!domain && !ip && !match) ||
          !knownTarget(
            parts.last == 'no-resolve' ? parts[parts.length - 2] : parts.last,
          )) {
        issues.add(PolicyMigrationIssue('rule', index));
      }
    }
    return PolicyMigrationAnalysis(
      rules: rules,
      origins: origins,
      issues: issues,
      proxies: proxies,
      groups: groups,
      targets: targets,
      labels: labels,
    );
  } catch (_) {
    return const PolicyMigrationAnalysis(
      issues: [PolicyMigrationIssue('snapshot')],
    );
  }
}
