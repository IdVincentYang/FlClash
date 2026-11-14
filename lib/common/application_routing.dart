import 'dart:convert';

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
  final global = targets.values
      .where((target) => target.kind == ApplicationTargetKind.globalGroup)
      .toList();
  return global.isNotEmpty &&
          global.every((target) => target.groupId == global.first.groupId)
      ? global.first
      : null;
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
    if (!rule.enabled) continue;
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
  final canonical =
      '${profileId ?? '-'}\n${settings.revision}\n${entries.map((entry) => '${entry['package']}\u0000${entry['target']}\u0000${entry['groupId'] ?? '-'}\n').join()}';
  return {
    'profileId': profileId,
    'version': settings.revision,
    'revision': sha256.convert(utf8.encode(canonical)).toString(),
    'rules': entries,
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
