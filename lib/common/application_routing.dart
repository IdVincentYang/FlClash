import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/enum/enum.dart';

import 'global_proxy_groups.dart';
import 'local_proxy_groups.dart';

enum ApplicationTargetIssue { preparing, missing, disabled, unbound, empty }

class ApplicationTargetState {
  const ApplicationTargetState({this.target, this.issue, this.members});
  final ApplicationRouteTarget? target;
  final ApplicationTargetIssue? issue;
  final int? members;
  bool get available => target != null && issue == null;
}

ApplicationRouteTarget? applicationTargetFor(
  ApplicationRoutingSettings settings,
  ApplicationRouteRule rule,
  int? profileId,
) {
  final targets = rule.useSharedTarget ? settings.sharedTargets : rule.targets;
  if (targets[profileId] case final target?) return target;
  return applicationBindingTarget(targets, profileId);
}

ApplicationRouteTarget? applicationBindingTarget(
  Map<int, ApplicationRouteTarget> targets,
  int? profileId,
) {
  if (targets[profileId] case final target?) return target;
  final global = targets.values
      .where((target) => target.kind == ApplicationTargetKind.globalGroup)
      .toList();
  return global.isNotEmpty &&
          global.every((target) => target.groupId == global.first.groupId)
      ? global.first
      : null;
}

String normalizeActivityHost(String host) =>
    host.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');

Rule hostRuleTemplate(String host) {
  final normalized = normalizeActivityHost(host);
  final ip = InternetAddress.tryParse(normalized);
  return Rule(
    ruleAction: ip == null
        ? RuleAction.DOMAIN
        : ip.type == InternetAddressType.IPv4
        ? RuleAction.IP_CIDR
        : RuleAction.IP_CIDR6,
    content: ip == null
        ? normalized
        : '${ip.address}/${ip.type == InternetAddressType.IPv4 ? 32 : 128}',
    ruleTarget: 'DIRECT',
  );
}

bool hostRuleApplies(Rule rule, int? profileId) =>
    rule.hostBinding != null &&
    (rule.hostBinding!.profileId == null ||
        rule.hostBinding!.profileId == profileId) &&
    !rule.hostBinding!.disabledProfiles.contains(profileId);

String hostRuleCondition(Rule rule) {
  if (rule.ruleAction == RuleAction.DOMAIN) {
    return 'domain:${normalizeActivityHost(rule.content ?? '')}';
  }
  final parts = (rule.content ?? '').split('/');
  final ip = InternetAddress.tryParse(parts.first);
  if (ip != null &&
      parts.last == (ip.type == InternetAddressType.IPv4 ? '32' : '128')) {
    return 'ip:${ip.rawAddress.join('.')}';
  }
  return '${rule.ruleAction.value}:${rule.content}';
}

Rule? applicationHostRule(
  ApplicationRoutingSettings settings,
  String host,
  String? package,
  int? profileId, {
  bool includeDisabled = false,
}) {
  final condition = hostRuleCondition(hostRuleTemplate(host));
  final matches =
      settings.hostRules
          .where(
            (r) =>
                (includeDisabled
                    ? (r.hostBinding!.profileId == null ||
                          r.hostBinding!.profileId == profileId)
                    : hostRuleApplies(r, profileId)) &&
                r.hostBinding!.packageName == package &&
                hostRuleCondition(r) == condition,
          )
          .toList()
        ..sort((a, b) {
          final legacy = (a.hostBinding!.legacy ? 1 : 0).compareTo(
            b.hostBinding!.legacy ? 1 : 0,
          );
          return legacy != 0
              ? legacy
              : (a.hostBinding!.profileId == profileId ? 0 : 1).compareTo(
                  b.hostBinding!.profileId == profileId ? 0 : 1,
                );
        });
  return matches.firstOrNull;
}

ApplicationRouteTarget? hostRuleTarget(Rule rule, int? profileId) =>
    applicationBindingTarget(rule.hostBinding?.targets ?? const {}, profileId);

String hostRuleKey(Map<String, dynamic> entry) => sha256
    .convert(
      utf8.encode(
        '${entry['id']}\u0000${entry['package']}\u0000${entry['type']}\u0000${entry['content']}\u0000${entry['target']}\u0000${entry['groupId'] ?? '-'}',
      ),
    )
    .toString();

({Rule? hostRule, ApplicationRouteRule? appRule, String fallback})
effectiveHostPolicy(
  ApplicationRoutingSettings settings,
  String host,
  String? package,
  int? profileId,
  Mode mode,
) {
  if (mode == Mode.global) {
    return (hostRule: null, appRule: null, fallback: 'GLOBAL');
  }
  final app = settings.rules[package];
  if (package != null && app?.enabled == true) {
    final rule = applicationHostRule(settings, host, package, profileId);
    if (rule != null) return (hostRule: rule, appRule: null, fallback: '');
    if (app!.hasDefault) return (hostRule: null, appRule: app, fallback: '');
  }
  if (mode == Mode.direct) {
    return (hostRule: null, appRule: null, fallback: 'DIRECT');
  }
  return (
    hostRule: applicationHostRule(settings, host, null, profileId),
    appRule: null,
    fallback: '',
  );
}

({Rule? hostRule, ApplicationRouteRule? appRule, String fallback})
effectiveHostPolicyForPackages(
  ApplicationRoutingSettings settings,
  String host,
  List<String> packages,
  int? profileId,
  Mode mode,
) {
  if (packages.length <= 1 || mode == Mode.global) {
    return effectiveHostPolicy(
      settings,
      host,
      packages.firstOrNull,
      profileId,
      mode,
    );
  }
  String decision(String package) {
    final selected = effectiveHostPolicy(
      settings,
      host,
      package,
      profileId,
      mode,
    );
    final rule = selected.hostRule;
    if (rule != null && rule.hostBinding!.packageName != null) {
      final target = hostRuleTarget(rule, profileId);
      return const {'DIRECT', 'REJECT'}.contains(rule.ruleTarget)
          ? rule.ruleTarget!
          : target?.groupId != null
          ? 'group:${target!.groupId}'
          : target?.name ?? 'REJECT';
    }
    final app = selected.appRule;
    if (app == null) return '';
    if (app.action != ApplicationRouteAction.proxy) {
      return app.action == ApplicationRouteAction.direct ? 'DIRECT' : 'REJECT';
    }
    final target = applicationTargetFor(settings, app, profileId);
    return target?.groupId != null
        ? 'group:${target!.groupId}'
        : target?.name ?? 'REJECT';
  }

  final decisions = packages.map(decision).toSet();
  return effectiveHostPolicy(
    settings,
    host,
    decisions.length == 1 && decisions.single.isNotEmpty
        ? packages.first
        : null,
    profileId,
    mode,
  );
}

ApplicationTargetState resolveApplicationTarget({
  required ApplicationRouteTarget? target,
  required Profile? profile,
  required List<Group> groups,
  required List<LocalProxyGroup> definitions,
  required bool ready,
}) {
  if (!ready) {
    return ApplicationTargetState(
      target: target,
      issue: ApplicationTargetIssue.preparing,
    );
  }
  if (target == null || profile == null) {
    return ApplicationTargetState(
      target: target,
      issue: ApplicationTargetIssue.missing,
    );
  }
  var name = target.name;
  if (target.kind == ApplicationTargetKind.globalGroup) {
    final groupId = target.groupId;
    final definition = definitions.where((g) => g.id == groupId).firstOrNull;
    if (definition == null) {
      return ApplicationTargetState(
        target: target,
        issue: ApplicationTargetIssue.missing,
      );
    }
    if (!definition.enabled) {
      return ApplicationTargetState(
        target: target.copyWith(name: definition.name),
        issue: ApplicationTargetIssue.disabled,
      );
    }
    final binding = profile.localGroups
        .where((g) => g.id == groupId)
        .firstOrNull;
    if (binding == null) {
      return ApplicationTargetState(
        target: target.copyWith(name: definition.name),
        issue: ApplicationTargetIssue.unbound,
      );
    }
    name = binding.name;
    target = target.copyWith(name: definition.name);
    if (!sameGlobalGroupDefinition(binding, definition)) {
      return ApplicationTargetState(
        target: target,
        issue: ApplicationTargetIssue.preparing,
      );
    }
  }
  if (target.kind == ApplicationTargetKind.node) {
    return ApplicationTargetState(
      target: target,
      issue: localGroupNodes(groups).any((p) => p.name == name)
          ? null
          : ApplicationTargetIssue.missing,
    );
  }
  final group = groups.where((g) => g.name == name).firstOrNull;
  if (group == null) {
    return ApplicationTargetState(
      target: target,
      issue: ApplicationTargetIssue.missing,
    );
  }
  final count = target.kind == ApplicationTargetKind.globalGroup
      ? localGroupNodes([group]).length
      : group.all.length;
  return ApplicationTargetState(
    target: target,
    members: count,
    issue: count == 0 ? ApplicationTargetIssue.empty : null,
  );
}

Map<String, dynamic> compileApplicationRouting(
  ApplicationRoutingSettings settings,
  int? profileId,
) {
  final entries = <Map<String, dynamic>>[];
  for (final rule in settings.rules.values.sortedBy((r) => r.packageName)) {
    if (!rule.enabled || !rule.hasDefault) continue;
    final target = applicationTargetFor(settings, rule, profileId);
    entries.add({
      'package': rule.packageName,
      'target': switch (rule.action) {
        ApplicationRouteAction.direct => 'DIRECT',
        ApplicationRouteAction.reject => 'REJECT',
        ApplicationRouteAction.proxy => target?.name ?? 'REJECT',
      },
      if (rule.action == ApplicationRouteAction.proxy &&
          target?.groupId != null)
        'groupId': target!.groupId,
    });
  }
  final hosts = <Map<String, dynamic>>[];
  final hostConditions = <String>{};
  final candidates = settings.hostRules.toList()
    ..sort(
      (a, b) => (a.hostBinding?.profileId == profileId ? 0 : 1).compareTo(
        b.hostBinding?.profileId == profileId ? 0 : 1,
      ),
    );
  for (final rule in candidates) {
    if (!hostRuleApplies(rule, profileId) || rule.hostBinding!.legacy) continue;
    final package = rule.hostBinding!.packageName;
    if (!hostConditions.add(
      '${package ?? ''}\u0000${hostRuleCondition(rule)}',
    )) {
      continue;
    }
    if (package != null && settings.rules[package]?.enabled != true) continue;
    final target = hostRuleTarget(rule, profileId);
    final builtin = const {
      'DIRECT',
      'REJECT',
    }.contains(rule.ruleTarget?.toUpperCase());
    hosts.add({
      'id': rule.id.toString(),
      'package': package ?? '',
      'type': rule.ruleAction.value,
      'content': rule.content ?? '',
      'target': builtin
          ? rule.ruleTarget!.toUpperCase()
          : target?.name ?? 'REJECT',
      if (!builtin && target?.groupId != null) 'groupId': target!.groupId,
    });
  }
  hosts.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  final canonical =
      '${profileId ?? '-'}\n${settings.revision}\n${entries.map((entry) => '${entry['package']}\u0000${entry['target']}\u0000${entry['groupId'] ?? '-'}\n').join()}'
      '${hosts.isEmpty ? '' : 'host-rules\n${hosts.map((e) => '${e['id']}\u0000${e['package']}\u0000${e['type']}\u0000${e['content']}\u0000${e['target']}\u0000${e['groupId'] ?? '-'}\n').join()}'}';
  return {
    'profileId': profileId,
    'version': settings.revision,
    'revision': sha256.convert(utf8.encode(canonical)).toString(),
    'rules': entries,
    if (hosts.isNotEmpty) 'hostRules': hosts,
  };
}

bool applicationCaptured(AccessControlProps settings, String package) =>
    !settings.enable ||
    switch (settings.mode) {
      AccessControlMode.acceptSelected => settings.acceptList.contains(package),
      AccessControlMode.rejectSelected => !settings.rejectList.contains(
        package,
      ),
    };

AccessControlProps setApplicationCapture(
  AccessControlProps previous,
  Iterable<String> packages,
  bool enabled,
) {
  if (!previous.enable) {
    if (enabled) return previous;
    return previous.copyWith(
      enable: true,
      mode: AccessControlMode.rejectSelected,
      rejectList: packages.toSet().toList()..sort(),
    );
  }
  final list = previous.currentList.toSet();
  final add = previous.mode == AccessControlMode.acceptSelected
      ? enabled
      : !enabled;
  add ? list.addAll(packages) : list.removeAll(packages);
  return previous.copyWithNewList(list.toList()..sort());
}

String applicationRuleKey(Map<String, dynamic> entry) => sha256
    .convert(utf8.encode('${entry['target']}\u0000${entry['groupId'] ?? '-'}'))
    .toString();

String applicationCaptureFingerprint(AccessControlProps settings) {
  final entries = settings.enable
      ? (settings.currentList.toSet().toList()..sort())
      : <String>[];
  final mode = !settings.enable
      ? 'all'
      : settings.mode == AccessControlMode.acceptSelected
      ? 'allow'
      : 'deny';
  return sha256
      .convert(utf8.encode('$mode\n${entries.map((name) => '$name\n').join()}'))
      .toString();
}
