import 'dart:convert';

import 'package:fl_clash/common/managed_profile.dart';
import 'package:fl_clash/common/policy_migration.dart';
import 'package:fl_clash/models/managed_policy.dart';
import 'package:fl_clash/models/policy_draft.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

final class PolicyDraftProblem implements Exception {
  final String location;

  const PolicyDraftProblem(this.location);

  @override
  String toString() => 'PolicyDraftProblem($location)';
}

final class PolicyDraftPreview {
  final String fullYaml;
  final String maskedYaml;

  const PolicyDraftPreview({required this.fullYaml, required this.maskedYaml});

  @override
  String toString() => 'PolicyDraftPreview(redacted)';
}

ManagedPolicy _draftPolicy(PolicyDraftDocument draft) {
  if (draft.isReadOnly) throw const PolicyDraftProblem('draftVersion');
  if (policyMigrationIssues(draft.migration).isNotEmpty) {
    throw const PolicyDraftProblem('migration');
  }
  return ManagedPolicy.fromJson(draft.policy);
}

String? policyDraftInputProblem(PolicyDraftDocument draft) {
  try {
    _draftPolicy(draft);
    return null;
  } on PolicyDraftProblem catch (problem) {
    return problem.location;
  } on FormatException catch (error) {
    return _safePolicyLocation(error.message);
  } catch (_) {
    return 'policy';
  }
}

PolicyDraftPreview previewPolicyDraft(PolicyDraftDocument draft) {
  try {
    final full = compileManagedProfile(_draftPolicy(draft));
    final masked =
        jsonDecode(jsonEncode(loadYaml(full))) as Map<String, dynamic>;
    for (final proxy in masked['proxies'] as List) {
      for (final field in ['username', 'password']) {
        if ((proxy as Map).containsKey(field)) proxy[field] = '••••••';
      }
    }
    return PolicyDraftPreview(
      fullYaml: full,
      maskedYaml: YamlWriter().write(masked),
    );
  } on FormatException catch (error) {
    throw PolicyDraftProblem(_safePolicyLocation(error.message));
  } on PolicyDraftProblem {
    rethrow;
  } catch (_) {
    throw const PolicyDraftProblem('policy');
  }
}

String _safePolicyLocation(String message) {
  final row = RegExp(
    r'^policy\.(domainRules|ipRules)\[([0-9]+)\](?:\.(id|type|value|cidr|target|dnsService))?',
  ).firstMatch(message);
  if (row != null) return row.group(0)!;
  for (final field in [
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
  ]) {
    if (message.startsWith('policy.$field')) return 'policy.$field';
  }
  return 'policy';
}

List<String> policyDraftResourceReferences(
  PolicyDraftDocument draft,
  String category,
  String id,
) {
  final locations = <String>[];
  void route(dynamic value, String path) {
    if (value is! Map) return;
    if (category == 'dnsServices' && value['dnsService'] == id) {
      locations.add('$path.dnsService');
    }
    final target = value['target'];
    if (category == 'groups' && target is Map && target['group'] == id) {
      locations.add('$path.target');
    }
  }

  for (final field in ['domainRules', 'ipRules']) {
    for (final (index, value) in draft.rows(field).indexed) {
      route(value, '$field[$index]');
    }
  }
  route(draft.policy['domainDefault'], 'domainDefault');
  route({'target': draft.policy['ipDefault']}, 'ipDefault');
  if (category == 'proxies') {
    for (final (index, members) in draft.resources('groups').values.indexed) {
      if ((members as List).contains(id)) locations.add('groups[$index]');
    }
  }
  return locations;
}
