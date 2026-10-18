import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/managed_profile.dart';
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
  final ManagedPolicy policy;
  final String digest;
  final String? maintenanceProxy;

  const SelectedPolicy._(this.policy, this.digest, this.maintenanceProxy);

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
          value['selectionVersion'] != 1) {
        throw const PolicyDraftProblem('selection');
      }
      final policy = ManagedPolicy.fromJson(value['policy']);
      compileManagedProfile(policy);
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
          'group' when policy.groups.containsKey(id) => managedGroupName(id),
          'proxy' when policy.proxies.containsKey(id) => managedProxyName(id),
          _ => throw const PolicyDraftProblem('maintenanceProxyTarget'),
        };
      }
      return SelectedPolicy._(
        policy,
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
  previewPolicyDraft(draft);
  final raw = jsonEncode({
    'selectionVersion': 1,
    'policy': draft.policy,
    'maintenanceProxyTarget': ?maintenanceProxyTarget,
  });
  SelectedPolicy.decode(raw);
  return raw;
}

Map<String, dynamic> managedFinalProfile(MakeRealProfileState data) {
  final policy = SelectedPolicy.decode(data.policySelection!.rawContent).policy;
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
