import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:material_ui/material_ui.dart';

enum SourcePermissionAction { review, stopAutomatic, stopUse }

typedef SourcePermissionChoice = ({
  SourcePermissionAction action,
  SourcePermission? permission,
});

class SourcePermissionsDialog extends StatelessWidget {
  const SourcePermissionsDialog({
    super.key,
    required this.label,
    required this.permissions,
  });

  final String label;
  final List<SourcePermission> permissions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    String purpose(String kind) => switch (kind) {
      'profile' => l10n.sourceProfileUse,
      'provider-proxy' => l10n.sourceNodeUse,
      'provider-rule' => l10n.sourceRuleSetUse,
      'config' => l10n.sourceFinalUse,
      'script' => l10n.script,
      _ => kind,
    };
    void choose(
      SourcePermissionAction action, [
      SourcePermission? permission,
    ]) => Navigator.of(
      context,
    ).pop<SourcePermissionChoice>((action: action, permission: permission));
    return CommonDialog(
      title: l10n.sourcePermissions,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => choose(SourcePermissionAction.review),
          child: Text(l10n.sourceReviewTitle),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(height: 12),
          Text(l10n.sourcePermissionEffects),
          if (permissions.isEmpty) Text(l10n.sourceNoPermissions),
          for (final permission in permissions) ...[
            const SizedBox(height: 16),
            Text(purpose(permission.kind)),
            Text(l10n.sourceAcceptedRevisions(permission.acceptedCount)),
            Text(
              permission.automatic
                  ? l10n.sourceAutomaticAllowed
                  : l10n.sourceAutomaticStopped,
            ),
            Wrap(
              spacing: 8,
              children: [
                if (permission.automatic)
                  TextButton(
                    onPressed: () => choose(
                      SourcePermissionAction.stopAutomatic,
                      permission,
                    ),
                    child: Text(l10n.sourceStopAutomatic),
                  ),
                if (permission.acceptedCount > 0)
                  TextButton(
                    onPressed: () =>
                        choose(SourcePermissionAction.stopUse, permission),
                    child: Text(l10n.sourceStopUse),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SourceReviewDialog extends StatefulWidget {
  const SourceReviewDialog({super.key, required this.review});
  final SourceReview review;

  @override
  State<SourceReviewDialog> createState() => _SourceReviewDialogState();
}

class _SourceReviewDialogState extends State<SourceReviewDialog> {
  bool _automatic = false;
  bool _inspectMaterial = false;
  late bool _sourceRouting = widget.review.routing != 'own';

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final script = widget.review.script;
    final details = widget.review.details;
    final dns = List<String>.from(details['dns'] as List? ?? const []);
    final previousDns = List<String>.from(
      widget.review.previous['dns'] as List? ?? const [],
    );
    final protocols = List<String>.from(
      details['protocols'] as List? ?? const [],
    );
    final features = List<String>.from(
      details['features'] as List? ?? const [],
    );
    final previousProtocols = List<String>.from(
      widget.review.previous['protocols'] as List? ?? const [],
    );
    final previousFeatures = List<String>.from(
      widget.review.previous['features'] as List? ?? const [],
    );
    String reason(String code) => switch (code) {
      'first_use' => l10n.sourceFirstUse,
      'dns_changed' => l10n.sourceDnsChanged,
      'ordered_routing_changed' ||
      'routing_changed' => l10n.sourceRoutingChanged,
      'proxy_capability_changed' ||
      'group_binding_changed' => l10n.sourceCapabilitiesChanged,
      'provider_source_changed' ||
      'source_bindings_changed' => l10n.sourceProviderChanged,
      'entry_or_control_changed' => l10n.sourceEntryChanged,
      'script_code_changed' => l10n.sourceCodeChanged,
      'automatic_maintenance_not_delegated' => l10n.sourceNotDelegated,
      _ => l10n.sourceUnknownChanged,
    };
    return CommonDialog(
      title: script == null ? l10n.sourceReviewTitle : l10n.sourceScriptTitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            SourceReviewDecision(
              automatic: script == null && _automatic,
              routing: _sourceRouting ? 'source' : 'own',
            ),
          ),
          child: Text(l10n.sourceAcceptRevision),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.review.label),
          if (widget.review.origin.isNotEmpty) Text(widget.review.origin),
          const SizedBox(height: 12),
          for (final item in widget.review.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(reason(item)),
            ),
          Text(l10n.sourceReviewScope),
          if (script == null) ...[
            const SizedBox(height: 12),
            if (details['binary'] == true)
              Text(l10n.sourceBinaryMaterial)
            else
              Text(
                l10n.sourceMaterialCounts(
                  (details['nodes'] as num?)?.toInt() ?? 0,
                  (details['rules'] as num?)?.toInt() ?? 0,
                ),
              ),
            if (previousProtocols.isNotEmpty)
              Text(l10n.sourceAcceptedProtocols(previousProtocols.join(', '))),
            if (protocols.isNotEmpty)
              Text(l10n.sourceProtocols(protocols.join(', '))),
            if (previousFeatures.isNotEmpty)
              Text(
                l10n.sourceAcceptedCapabilities(previousFeatures.join(', ')),
              ),
            if (features.isNotEmpty)
              Text(l10n.sourceDeclaredCapabilities(features.join(', '))),
            if (previousDns.isNotEmpty)
              Text(l10n.sourceAcceptedDns(previousDns.join(', '))),
            if (const {'profile', 'config'}.contains(widget.review.kind))
              Text(
                l10n.sourceProposedDns(
                  dns.isEmpty ? l10n.sourceNotDeclared : dns.join(', '),
                ),
              ),
            if (_sourceRouting &&
                const {'profile', 'config'}.contains(widget.review.kind))
              Text(
                l10n.sourceDefaultExit(
                  details['defaultTarget'] as String? ??
                      l10n.sourceImplicitDirect,
                ),
              ),
            if (widget.review.kind == 'profile')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _sourceRouting,
                onChanged: (value) =>
                    setState(() => _sourceRouting = value ?? false),
                title: Text(l10n.sourceUseRouting),
                subtitle: Text(l10n.sourceOwnRoutingHint),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _automatic,
              onChanged: (value) => setState(() => _automatic = value ?? false),
              title: Text(l10n.sourceDelegateMaintenance),
              subtitle: Text(l10n.sourceMaintenanceLimits),
            ),
            if (widget.review.ruleTargets.isNotEmpty)
              Text(
                l10n.sourceRuleDelegation(widget.review.ruleTargets.join(', ')),
              ),
            if (widget.review.material case final String text) ...[
              TextButton(
                onPressed: () =>
                    setState(() => _inspectMaterial = !_inspectMaterial),
                child: Text(l10n.sourceInspectMaterial),
              ),
              if (_inspectMaterial) SelectableText(text),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Text(l10n.sourceScriptScope),
            const SizedBox(height: 8),
            SelectableText(script),
          ],
        ],
      ),
    );
  }
}
