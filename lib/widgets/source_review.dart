import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/source_review_loading.dart';
import 'package:fl_clash/common/profile_import.dart';
import 'package:fl_clash/widgets/dialog.dart';
import 'package:material_ui/material_ui.dart';

enum SourcePermissionAction { review, stopAutomatic, stopUse }

typedef SourceReviewPresentation = ({
  Future<SourceReviewDecision?> Function(Widget) present,
  void Function(SourceReviewDecision?) onDecision,
});

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
  const SourceReviewDialog({
    super.key,
    required this.review,
    this.loadRelated,
    this.loading,
    this.routingEditable = true,
    this.onDecision,
    this.allowPartialImport = false,
    this.allowPartialConfiguration = false,
    this.partialConfiguration,
    this.partialChanges,
    this.canUseAvailableConfiguration,
    this.retrySource,
  });
  final bool allowPartialImport, allowPartialConfiguration;
  final PartialProfileConfiguration? partialConfiguration;
  final Map<String, Object?> Function()? partialChanges;
  final bool Function()? canUseAvailableConfiguration;
  final Future<void> Function(String)? retrySource;
  final SourceReview review;
  final Future<List<SourceReview>> Function(String routing)? loadRelated;
  final SourceReviewLoading? loading;
  final bool routingEditable;
  final ValueChanged<SourceReviewDecision?>? onDecision;

  @override
  State<SourceReviewDialog> createState() => _SourceReviewDialogState();
}

class _SourceReviewDialogState extends State<SourceReviewDialog> {
  bool _automatic = false;
  bool _inspectMaterial = false;
  late bool _sourceRouting = widget.review.routing != 'own';
  List<SourceReview> _related = const [];
  bool _loading = false;
  Object? _error;
  int _loadGeneration = 0;
  bool _decided = false;

  void _finish(SourceReviewDecision? decision) {
    if (_decided) return;
    _decided = true;
    final respond = widget.onDecision;
    if (respond == null) {
      Navigator.of(context).pop(decision);
    } else {
      respond(decision);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.loading?.addListener(_progressChanged);
    if (widget.loadRelated != null) unawaited(_loadRelated());
  }

  void _progressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.loading?.removeListener(_progressChanged);
    super.dispose();
  }

  Future<void> _loadRelated() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _related = const [];
    });
    try {
      final related = await widget.loadRelated!(
        _sourceRouting ? 'source' : 'own',
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _related = related;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _retrySource(String key) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await (widget.retrySource?.call(key) ?? widget.loading!.retry(key));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
    final partial =
        (widget.allowPartialImport || widget.allowPartialConfiguration) &&
        !_loading &&
        _error == null &&
        widget.loading?.settled == true &&
        !widget.loading!.ready;
    void alternative(SourceImportChoice choice) => _finish(
      SourceReviewDecision(
        automatic: false,
        routing: _sourceRouting ? 'source' : 'own',
        importChoice: choice,
      ),
    );
    return CommonDialog(
      title: widget.loadRelated != null
          ? l10n.sourceSubscriptionReview
          : script != null
          ? l10n.sourceScriptTitle
          : widget.review.kind == 'config'
          ? l10n.sourceFinalUse
          : l10n.sourceReviewTitle,
      actions: [
        TextButton(onPressed: () => _finish(null), child: Text(l10n.cancel)),
        if (partial) ...[
          if (widget.allowPartialImport)
            TextButton(
              onPressed: () => alternative(SourceImportChoice.savePending),
              child: Text(l10n.sourceSavePending),
            ),
          TextButton(
            onPressed: widget.canUseAvailableConfiguration?.call() == true
                ? () => alternative(SourceImportChoice.availableConfiguration)
                : null,
            child: Text(l10n.sourceUseAvailableConfiguration),
          ),
        ],
        if (!partial)
          TextButton(
            onPressed:
                _loading ||
                    _error != null ||
                    widget.loading != null && !widget.loading!.ready
                ? null
                : () => _finish(
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
          if (partial) Text(l10n.sourcePartialImportHint),
          if (widget.partialConfiguration != null) ...[
            if (widget.partialConfiguration!.changes['nodesOnly'] != true)
              Text(l10n.sourcePartialConfigurationHint),
            _SourcePartialChanges(
              changes: widget.partialConfiguration!.changes,
            ),
          ],
          if (partial)
            _SourcePartialChanges(
              changes: widget.partialChanges?.call() ?? const {},
            ),
          if (widget.review.origin.isNotEmpty) Text(widget.review.origin),
          if (widget.loadRelated != null) ...[
            const SizedBox(height: 12),
            if (widget.loading != null && widget.loading!.items.isNotEmpty) ...[
              _SourceReviewProgress(
                loading: widget.loading!,
                onRetry: _retrySource,
              ),
            ] else if (_loading) ...[
              Text(l10n.sourceBatchPreparing),
              const LinearProgressIndicator(),
            ] else if (_error != null) ...[
              Text(userFacingErrorMessage(_error!, l10n)),
              TextButton(
                onPressed: () => unawaited(_loadRelated()),
                child: Text(l10n.retry),
              ),
            ] else ...[
              Text(
                l10n.sourceRelatedSourcesCount(
                  _related.where((item) => item.kind != 'config').length,
                ),
              ),
              for (final related in _related)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${switch (related.kind) {
                          'config' => l10n.sourceFinalUse,
                          'provider-rule' => l10n.sourceRuleSetUse,
                          _ => l10n.sourceNodeUse,
                        }} · ${related.label}',
                      ),
                      if (related.origin.isNotEmpty) Text(related.origin),
                      if (related.details['binary'] == true)
                        Text(l10n.sourceBinaryMaterial)
                      else
                        Text(
                          l10n.sourceMaterialCounts(
                            (related.details['nodes'] as num?)?.toInt() ?? 0,
                            (related.details['rules'] as num?)?.toInt() ?? 0,
                          ),
                        ),
                      if ((related.details['protocols'] as List?)?.isNotEmpty ==
                          true)
                        Text(
                          l10n.sourceProtocols(
                            (related.details['protocols'] as List).join(', '),
                          ),
                        ),
                      if ((related.details['features'] as List?)?.isNotEmpty ==
                          true)
                        Text(
                          l10n.sourceDeclaredCapabilities(
                            (related.details['features'] as List).join(', '),
                          ),
                        ),
                      if ((related.details['dns'] as List?)?.isNotEmpty == true)
                        Text(
                          l10n.sourceProposedDns(
                            (related.details['dns'] as List).join(', '),
                          ),
                        ),
                      if (related.details['defaultTarget'] is String)
                        Text(
                          l10n.sourceDefaultExit(
                            related.details['defaultTarget'] as String,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],

          const SizedBox(height: 12),
          for (final item in widget.review.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(reason(item)),
            ),
          Text(
            widget.loadRelated == null
                ? l10n.sourceReviewScope
                : l10n.sourceBatchScope,
          ),
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
            if (widget.review.kind == 'profile' && widget.routingEditable)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _sourceRouting,
                onChanged: (value) {
                  setState(() => _sourceRouting = value ?? false);
                  if (widget.loadRelated != null) unawaited(_loadRelated());
                },
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

class _SourcePartialChanges extends StatelessWidget {
  const _SourcePartialChanges({required this.changes});
  final Map<String, Object?> changes;

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final nodesOnly = changes['nodesOnly'] == true;
    final sections = {
      'missing': l.sourcePartialMissing,
      'removedRules': l.sourcePartialRules,
      'removedGroups': l.sourcePartialGroups,
      'blocked': nodesOnly
          ? l.sourceConfigurationUnavailable
          : l.sourcePartialBlocked,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nodesOnly) Text(l.sourceNodeImportHint),
        for (final section in sections.entries)
          if (changes[section.key] case final List items
              when items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(section.value),
            for (final item in items) SelectableText('$item'),
          ],
        if (changes['defaultTarget'] case final String target
            when target.isNotEmpty)
          Text(l.sourceDefaultExit(target)),
      ],
    );
  }
}

class _SourceReviewProgress extends StatelessWidget {
  const _SourceReviewProgress({required this.loading, required this.onRetry});
  final SourceReviewLoading loading;
  final Future<void> Function(String) onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final sources = loading.items
        .where((item) => item.kind != 'config')
        .toList();
    final ready = sources
        .where((item) => item.phase == SourceReviewLoadPhase.ready)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sourceRelatedSourcesCount(sources.length)),
        Text(l10n.sourceLoadProgress(ready, sources.length)),
        if (!loading.settled)
          LinearProgressIndicator(
            value: sources.isEmpty ? null : ready / sources.length,
          ),
        for (final item in [
          ...sources,
          ...loading.items.where((item) => item.kind == 'config'),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${switch (item.kind) {
                    'config' => l10n.sourceFinalUse,
                    'provider-rule' => l10n.sourceRuleSetUse,
                    _ => l10n.sourceNodeUse,
                  }} · ${item.label}',
                ),
                if (item.origin.isNotEmpty) Text(item.origin),
                Text(switch (item.phase) {
                  SourceReviewLoadPhase.queued => l10n.sourceLoadQueued,
                  SourceReviewLoadPhase.loading => l10n.sourceLoadDownloading,
                  SourceReviewLoadPhase.parsing => l10n.sourceLoadVerifying,
                  SourceReviewLoadPhase.ready =>
                    item.kind == 'config'
                        ? l10n.sourceConfigParsed
                        : item.cached
                        ? l10n.sourceLoadCached
                        : l10n.sourceLoadReady,
                  SourceReviewLoadPhase.failed => l10n.sourceLoadFailed,
                }),
                if (item.phase == SourceReviewLoadPhase.loading ||
                    item.phase == SourceReviewLoadPhase.parsing)
                  const LinearProgressIndicator(),
                if (item.error != null) ...[
                  Text(
                    userFacingErrorMessage(item.error!, l10n),
                    style: TextStyle(color: context.colorScheme.error),
                  ),
                  TextButton(
                    key: ValueKey('retry:${item.key}'),
                    onPressed: () => unawaited(onRetry(item.key)),
                    child: Text(l10n.retry),
                  ),
                ],
                if (item.entry case final SourceReviewBatchEntry entry) ...[
                  if (entry.review.details['binary'] == true)
                    Text(l10n.sourceBinaryMaterial)
                  else
                    Text(
                      l10n.sourceMaterialCounts(
                        (entry.review.details['nodes'] as num?)?.toInt() ?? 0,
                        (entry.review.details['rules'] as num?)?.toInt() ?? 0,
                      ),
                    ),
                  if ((entry.review.details['protocols'] as List?)
                          ?.isNotEmpty ==
                      true)
                    Text(
                      l10n.sourceProtocols(
                        (entry.review.details['protocols'] as List).join(', '),
                      ),
                    ),
                  if ((entry.review.details['features'] as List?)?.isNotEmpty ==
                      true)
                    Text(
                      l10n.sourceDeclaredCapabilities(
                        (entry.review.details['features'] as List).join(', '),
                      ),
                    ),
                  if ((entry.review.details['dns'] as List?)?.isNotEmpty ==
                      true)
                    Text(
                      l10n.sourceProposedDns(
                        (entry.review.details['dns'] as List).join(', '),
                      ),
                    ),
                  if (entry.review.details['defaultTarget'] is String)
                    Text(
                      l10n.sourceDefaultExit(
                        entry.review.details['defaultTarget'] as String,
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
