import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/common/managed_material.dart';
import 'package:fl_clash/common/policy_draft.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/managed_policy.dart';
import 'package:fl_clash/models/models.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

String maskedPolicyConfig(String yaml) {
  dynamic mask(dynamic value, [String? key]) {
    if ({
      'username',
      'password',
      'authentication',
      'secret',
      'token',
      'uuid',
      'private-key',
      'url',
    }.contains(key)) {
      return '••••••';
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key: mask(entry.value, '${entry.key}'),
      };
    }
    if (value is List) return value.map((item) => mask(item)).toList();
    return value;
  }

  try {
    return YamlWriter().write(mask(loadYaml(yaml)));
  } catch (_) {
    throw const PolicyDraftProblem('preview');
  }
}

final class SelectedPolicy {
  final ManagedPolicy? _policy;
  final Map<String, dynamic> policyJson;
  final Set<String> dynamicGroups;
  final Map<String, Object?>? materials;
  final String digest;
  final String? maintenanceProxy;

  const SelectedPolicy._(
    this._policy,
    this.policyJson,
    this.digest,
    this.maintenanceProxy, {
    this.dynamicGroups = const {},
    this.materials,
  });

  bool get usesMaterials => isMaterialTemplate(policyJson) || materials != null;
  bool get isResolved => _policy != null;
  ManagedPolicy get policy =>
      _policy ?? (throw const PolicyDraftProblem('material'));
  int get mixedPort =>
      _policy?.mixedPort ??
      (policyJson['listeners'] as Map)['mixedPort'] as int;

  SelectedPolicy resolve({
    required Map<String, dynamic> material,
    required String identity,
    required int profileId,
    required String rawSha256,
  }) {
    if (isResolved) return this;
    final resolved = resolveMaterialPolicy(
      policyJson,
      material: material,
      identity: identity,
      profileId: profileId,
      rawSha256: rawSha256,
    );
    final yaml = compileManagedProfile(resolved.policy);
    if (utf8.encode(yaml).length > managedMaterialMaxBytes) {
      throw const PolicyDraftProblem('materialBudget');
    }
    return SelectedPolicy._(
      resolved.policy,
      resolved.json,
      digest,
      maintenanceProxy,
      dynamicGroups: resolved.dynamicGroups,
      materials: resolved.receipt,
    );
  }

  factory SelectedPolicy.decode(String? raw) {
    try {
      final value = raw == null ? null : jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.keys.any(
            (key) => !{
              'selectionVersion',
              'policy',
              'maintenanceProxyTarget',
            }.contains(key),
          ) ||
          value['selectionVersion'] is! int ||
          !{1, 2}.contains(value['selectionVersion'])) {
        throw const PolicyDraftProblem('selection');
      }
      final template = boundedMaterialCopy(
        Map<String, dynamic>.from(value['policy'] as Map),
      );
      final materialTemplate = value['selectionVersion'] == 2;
      if (materialTemplate != isMaterialTemplate(template)) {
        throw const PolicyDraftProblem('selection');
      }
      ManagedPolicy? policy;
      if (materialTemplate) {
        validateMaterialTemplate(template);
      } else {
        policy = ManagedPolicy.fromJson(template);
        compileManagedProfile(policy);
      }
      final target = value['maintenanceProxyTarget'];
      String? proxy;
      if (target != null) {
        if (target is! Map ||
            target.length != 2 ||
            !target.containsKey('kind') ||
            !target.containsKey('id') ||
            target['id'] is! String) {
          throw const PolicyDraftProblem('maintenanceProxyTarget');
        }
        final id = target['id'] as String;
        proxy = switch (target['kind']) {
          'group' when (template['groups'] as Map).containsKey(id) =>
            managedGroupName(id),
          'proxy' when (template['proxies'] as Map).containsKey(id) =>
            managedProxyName(id),
          _ => throw const PolicyDraftProblem('maintenanceProxyTarget'),
        };
      }
      return SelectedPolicy._(
        policy,
        template,
        sha256.convert(utf8.encode(raw!)).toString(),
        proxy,
      );
    } on PolicyDraftProblem {
      rethrow;
    } catch (_) {
      throw const PolicyDraftProblem('selection');
    }
  }

  Map<String, Object?> get descriptor => {
    'version': 1,
    'policySha256': digest,
    'maintenanceProxy': ?maintenanceProxy,
  };

  Map<String, String> picks(Map<String, String> values) {
    final result = <String, String>{};
    for (final group in policy.groups.entries) {
      final name = managedGroupName(group.key);
      final selected = values[name];
      if (selected == null) continue;
      if (!group.value.map(managedProxyName).contains(selected)) {
        if (dynamicGroups.contains(group.key)) {
          result[name] = managedProxyName(group.value.first);
          continue;
        }
        throw const PolicyDraftProblem('selectedMap');
      }
      result[name] = selected;
    }
    return result;
  }

  @override
  String toString() => 'SelectedPolicy(redacted)';
}

String selectPolicyDraft(
  PolicyDraftDocument draft, {
  Map<String, String>? maintenanceProxyTarget,
}) {
  if (draft.isReadOnly) throw const PolicyDraftProblem('draftVersion');
  if (isMaterialTemplate(draft.policy)) {
    if (draft.isReadOnly || policyDraftInputProblem(draft) != null) {
      throw const PolicyDraftProblem('material');
    }
    validateMaterialTemplate(draft.policy);
  } else {
    previewPolicyDraft(draft);
  }
  final raw = jsonEncode({
    'selectionVersion': isMaterialTemplate(draft.policy) ? 2 : 1,
    'policy': draft.policy,
    'maintenanceProxyTarget': ?maintenanceProxyTarget,
  });
  SelectedPolicy.decode(raw);
  return raw;
}

Map<String, dynamic> managedFinalProfile(MakeRealProfileState data) {
  final selected = SelectedPolicy.decode(data.policySelection!.rawContent);
  final policy = selected.usesMaterials
      ? ManagedPolicy.fromJson(
          data.resolvedManagedPolicy ??
              (throw const PolicyDraftProblem('material')),
        )
      : selected.policy;
  final output =
      jsonDecode(jsonEncode(loadYaml(compileManagedProfile(policy))))
          as Map<String, dynamic>;
  final patch = data.realPatchConfig;
  if (patch.interfaceNameMode == InterfaceNameMode.follow) {
    throw const PolicyDraftProblem('interface-name');
  }
  output['authentication'] = List<String>.of(data.authentication);
  output['skip-auth-prefixes'] = <String>[];
  output['interface-name'] = patch.interfaceNameMode == InterfaceNameMode.custom
      ? patch.interfaceName
      : '';
  output['log-level'] = patch.logLevel.name;
  output['tcp-concurrent'] = patch.tcpConcurrent;
  output['unified-delay'] = patch.unifiedDelay;
  output['tun'] = {
    'enable': !data.safeMode && patch.tun.enable,
    'device': patch.tun.device,
    'dns-hijack': List<String>.of(patch.tun.dnsHijack),
    'stack': patch.tun.stack.name,
    'route-address': List<String>.of(patch.tun.routeAddress),
    'auto-route': patch.tun.autoRoute,
  };
  if (data.safeMode) output['dns']['listen'] = '';
  return output;
}
