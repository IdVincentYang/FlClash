import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/policy_draft.dart';
import 'package:fl_clash/common/policy_migration.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/common/managed_material.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'policy_draft_form.dart';
import 'preview.dart';

class PolicyDraftView extends ConsumerStatefulWidget {
  final Profile profile;

  const PolicyDraftView({super.key, required this.profile});

  @override
  ConsumerState<PolicyDraftView> createState() => _PolicyDraftViewState();
}

class _PolicyDraftViewState extends ConsumerState<PolicyDraftView> {
  PolicyDraftDocument? _draft;
  PolicyMaterialCandidate? _material;
  String? _storedRaw;
  String? _storedEncoding;
  String? _problemLocation;
  ProfilePolicySelection? _selected;
  bool _previewed = false;
  bool _loadingMaterial = false;
  bool _busy = true;
  bool _leaving = false;
  bool _allowPop = false;
  int _operation = 0;

  bool get _dirty =>
      _draft != null &&
      !_draft!.isReadOnly &&
      _draft!.encode() != _storedEncoding;

  PolicyDraftAction get _action => ref.read(policyDraftActionProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  bool _ownsOperation(int operation) => mounted && operation == _operation;

  Future<void> _load() async {
    final operation = ++_operation;
    await _material?.close();
    if (!mounted || !_ownsOperation(operation)) return;
    _material = null;
    setState(() => _busy = true);
    try {
      final row = await _action.load(widget.profile.id);
      final selected = await ref
          .read(policySelectionActionProvider.notifier)
          .load(widget.profile.id);
      if (!mounted || operation != _operation) return;
      final draft = row == null
          ? PolicyDraftDocument.empty()
          : PolicyDraftDocument.decode(row.rawContent);
      setState(() {
        _storedRaw = row?.rawContent;
        _selected = selected;
        _draft = draft;
        _storedEncoding = draft.encode();
        _problemLocation = null;
        _previewed = false;
      });
    } catch (_) {
      if (mounted && _ownsOperation(operation)) {
        _notify(context.appLocalizations.policyDraftLoadFailed);
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  void _notify(String message) => context.showNotifier(message);

  void _change(VoidCallback update) {
    setState(() {
      update();
      _problemLocation = null;
      _previewed = false;
      _operation++;
    });
  }

  Future<bool> _confirm(String message) async =>
      await dialogs.showMessage(
        context: context,
        title: context.appLocalizations.policyDraftTitle,
        message: TextSpan(text: message),
      ) ==
      true;

  Future<bool> _save({bool delete = false}) async {
    if (_busy || _draft == null || (!delete && _draft!.isReadOnly)) {
      return false;
    }
    final raw = delete ? null : _draft!.encode();
    setState(() => _busy = true);
    try {
      final result = await _action.save(
        widget.profile.id,
        expectedRaw: _storedRaw,
        rawContent: raw,
      );
      if (!mounted) return result == PolicyDraftWriteResult.saved;
      final l = context.appLocalizations;
      if (result != PolicyDraftWriteResult.saved) {
        _notify(switch (result) {
          PolicyDraftWriteResult.conflict => l.policyDraftConflict,
          PolicyDraftWriteResult.missingProfile => l.policyDraftMissing,
          _ => l.policyDraftSaveFailed,
        });
        return false;
      }
      setState(() {
        _storedRaw = raw;
        if (delete) _draft = PolicyDraftDocument.empty();
        _storedEncoding = _draft!.encode();
      });
      _notify(delete ? l.policyDraftDeleted : l.policyDraftSaved);
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _operation++;
    unawaited(_material?.close());
    super.dispose();
  }

  Future<PolicyMaterialCandidate> _ensureMaterial(
    int operation, {
    bool latest = false,
  }) async {
    final old = _material;
    if (!latest && old != null) {
      final current = await old.current();
      if (!_ownsOperation(operation)) {
        throw const PolicyDraftProblem('materialSource');
      }
      if (current) return old;
    }
    await old?.close();
    if (!_ownsOperation(operation)) {
      throw const PolicyDraftProblem('materialSource');
    }
    _material = null;
    final candidate = await ref
        .read(setupActionProvider.notifier)
        .capturePolicyMaterial(
          widget.profile.id,
          latest: latest,
          onCreated: (candidate) {
            if (_ownsOperation(operation)) {
              _material = candidate;
            } else {
              unawaited(candidate.close());
            }
          },
        );
    if (!_ownsOperation(operation)) {
      await candidate.close();
      throw const PolicyDraftProblem('materialSource');
    }
    _material = candidate;
    return candidate;
  }

  void _discardMaterial() {
    _operation++;
    unawaited(_material?.close());
    _material = null;
    if (mounted) {
      setState(() {
        _previewed = false;
        if (_loadingMaterial) {
          _busy = false;
          _loadingMaterial = false;
        }
      });
    }
  }

  Future<void> _loadLatestMaterial() async {
    if (_busy) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _loadingMaterial = true;
    });
    try {
      await _ensureMaterial(operation, latest: true);
      if (!mounted || !_ownsOperation(operation)) return;
      setState(() => _previewed = false);
      _notify(context.appLocalizations.policyMaterialLoaded);
    } catch (_) {
      if (mounted && _ownsOperation(operation)) {
        _notify(context.appLocalizations.policyMaterialUnavailable);
      }
    } finally {
      if (_ownsOperation(operation)) {
        setState(() {
          _loadingMaterial = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _sourcesMenu() async {
    if (_busy || _draft == null || _draft!.isReadOnly) return;
    final operation = _operation;
    final l = context.appLocalizations;
    final choices = <String, String>{
      'proxies': l.policyMaterialNode,
      'groups': l.policyMaterialGroup,
      'domain': l.policyMaterialDomain,
      'ip': l.policyMaterialIp,
      if (widget.profile.type == ProfileType.url)
        'latest': l.policyMaterialLatest,
    };
    final choice = await dialogs.showCommonDialog<String>(
      context: context,
      child: CommonDialog(
        title: l.policyMaterialBindings,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in choices.entries)
              ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.of(context).pop(entry.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || !_ownsOperation(operation) || choice == null) return;
    if (choice == 'latest') {
      await _loadLatestMaterial();
    } else {
      await _bindSource(choice);
    }
  }

  Future<void> _bindSource(String kind, {String? id}) async {
    if (_busy || _draft == null || _draft!.isReadOnly) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _loadingMaterial = true;
    });
    try {
      final candidate = await _ensureMaterial(operation);
      final sources = (await candidate.sourceNames())[kind] ?? [];
      if (!mounted || !_ownsOperation(operation)) return;
      final l = context.appLocalizations;
      final name = await dialogs.showCommonDialog<String>(
        context: context,
        child: CommonDialog(
          title: l.policyMaterialSource,
          child: SizedBox(
            width: 360,
            height: 360,
            child: sources.isEmpty
                ? Text(l.policyMaterialUnavailable)
                : ListView.builder(
                    itemCount: sources.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(sources[index]),
                      onTap: () => Navigator.of(context).pop(sources[index]),
                    ),
                  ),
          ),
        ),
      );
      if (name == null ||
          !await candidate.current() ||
          !_ownsOperation(operation)) {
        return;
      }
      final resourceId = id ?? 'resource$uniqueId';
      final category = kind == 'domain' || kind == 'ip' ? 'collections' : kind;
      setState(() {
        _busy = false;
        _loadingMaterial = false;
      });
      _change(() {
        _draft!.useMaterialSource(widget.profile.id, candidate.identity);
        _draft!.policy[category] = {
          ..._draft!.resources(category),
          resourceId: {
            'source': name,
            if (category == 'collections') 'kind': kind,
          },
        };
        _draft!.setLabel(resourceId, name);
      });
    } catch (_) {
      if (mounted && _ownsOperation(operation)) {
        _notify(context.appLocalizations.policyMaterialUnavailable);
      }
    } finally {
      if (_ownsOperation(operation)) {
        setState(() {
          _busy = false;
          _loadingMaterial = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    if (_busy) return;
    if (_dirty &&
        !await _confirm(context.appLocalizations.policyDraftDiscard)) {
      return;
    }
    if (mounted) await _load();
  }

  Future<void> _apply() async {
    if (_busy || _draft == null || _draft!.isReadOnly) return;
    if (_dirty || _storedRaw == null) {
      if (!await _save()) return;
    }
    if (!mounted) return;
    if (isMaterialTemplate(_draft!.policy)) {
      if (await _previewSnapshot() == null || !mounted) return;
    } else if (_staticPreviewSnapshot() == null) {
      return;
    }
    final l = context.appLocalizations;
    final expected = _selected;
    final draftRaw = _storedRaw!;
    final draft = PolicyDraftDocument.decode(draftRaw);
    final targets = <String, String>{
      'none': l.policyMaintenanceNone,
      for (final id in draft.resources('groups').keys)
        'group:$id': '${l.proxyGroup}: ${draft.label(id)}',
      for (final id in draft.resources('proxies').keys)
        'proxy:$id': '${l.proxies}: ${draft.label(id)}',
    };
    final target = await dialogs.showCommonDialog<String>(
      context: context,
      child: CommonDialog(
        title: l.policyMaintenanceTarget,
        child: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in targets.entries)
                  ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.of(context).pop(entry.key),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    final raw = selectPolicyDraft(
      draft,
      maintenanceProxyTarget: target == 'none'
          ? null
          : {
              'kind': target.substring(0, target.indexOf(':')),
              'id': target.substring(target.indexOf(':') + 1),
            },
    );
    if (!await _confirm(
      '${l.policyApplyConfirm}\n\n'
      '${l.policyMaintenanceTarget}: ${targets[target]}',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(policySelectionActionProvider.notifier)
          .selectConfirmed(
            widget.profile.id,
            expected: expected,
            draftRaw: draftRaw,
            selectionRaw: raw,
            material: isMaterialTemplate(draft.policy) ? _material : null,
          );
      if (!mounted) return;
      if (result == PolicyDraftWriteResult.saved) {
        setState(
          () => _selected = ProfilePolicySelection(
            profileId: widget.profile.id,
            rawContent: raw,
          ),
        );
        _notify(l.policyApplyRequested);
      } else {
        _notify(
          result == PolicyDraftWriteResult.conflict
              ? l.policyDraftConflict
              : l.policyDraftSaveFailed,
        );
      }
    } catch (_) {
      if (mounted) _notify(l.policyDraftSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useOriginal() async {
    if (_busy || _selected == null) return;
    final expected = _selected;
    if (!await _confirm(context.appLocalizations.policyOriginalConfirm) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(policySelectionActionProvider.notifier)
          .selectConfirmed(
            widget.profile.id,
            expected: expected,
            draftRaw: null,
            selectionRaw: null,
          );
      if (!mounted) return;
      if (result == PolicyDraftWriteResult.saved) {
        setState(() => _selected = null);
        _notify(context.appLocalizations.policyApplyRequested);
      } else {
        _notify(context.appLocalizations.policyDraftConflict);
      }
    } catch (_) {
      if (mounted) _notify(context.appLocalizations.policyDraftSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _selectionStatus() {
    final l = context.appLocalizations;
    if (_selected == null) return l.policyOriginalStatus;
    try {
      SelectedPolicy.decode(_selected!.rawContent);
      final envelope = jsonDecode(_selected!.rawContent!) as Map;
      return jsonEncode(envelope['policy']) == jsonEncode(_draft?.policy)
          ? l.policySelectedStatus
          : l.policyUnappliedEdits;
    } catch (_) {
      return l.policySelectionUnavailable;
    }
  }

  Future<void> _rebuild() async {
    if (_busy ||
        !await _confirm(context.appLocalizations.policyDraftRebuildConfirm)) {
      return;
    }
    if (mounted) _change(() => _draft = PolicyDraftDocument.empty());
  }

  Future<void> _delete() async {
    if (_busy ||
        !await _confirm(
          context.appLocalizations.deleteTip(
            context.appLocalizations.policyDraftTitle,
          ),
        )) {
      return;
    }
    if (mounted) await _save(delete: true);
  }

  Future<void> _extract() async {
    if (_busy ||
        !await _confirm(context.appLocalizations.policyDraftExtractConfirm)) {
      return;
    }
    if (!mounted) return;
    final operation = ++_operation;
    setState(() => _busy = true);
    try {
      final value = await _action.extract(widget.profile.id);
      if (!mounted || operation != _operation) return;
      _change(() => _draft = value);
    } catch (_) {
      if (mounted) _notify(context.appLocalizations.policyDraftExtractFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PolicyDraftPreview? _staticPreviewSnapshot() {
    try {
      final preview = previewPolicyDraft(_draft!);
      setState(() => _previewed = true);
      return preview;
    } on PolicyDraftProblem catch (problem) {
      setState(() => _problemLocation = problem.location);
      _notify(context.appLocalizations.policyDraftIncomplete(problem.location));
      return null;
    }
  }

  Future<PolicyDraftPreview?> _previewSnapshot() async {
    if (!isMaterialTemplate(_draft!.policy)) return _staticPreviewSnapshot();
    final original = _draft!;
    final raw = original.encode();
    final frozen = PolicyDraftDocument.decode(raw);
    final operation = ++_operation;
    setState(() => _previewed = false);
    bool owned() =>
        _ownsOperation(operation) &&
        identical(_draft, original) &&
        original.encode() == raw;
    try {
      final candidate = await _ensureMaterial(operation);
      final preview = await candidate.preview(frozen);
      if (!mounted ||
          !owned() ||
          !identical(candidate, _material) ||
          !candidate.qualifies(original)) {
        return null;
      }
      setState(() => _previewed = true);
      return preview;
    } catch (error) {
      if (!mounted || !owned()) return null;
      final location = error is PolicyDraftProblem
          ? error.location
          : 'material';
      setState(() => _problemLocation = location);
      _notify(context.appLocalizations.policyDraftIncomplete(location));
      return null;
    }
  }

  Future<void> _preview() async {
    if (_busy || _draft == null) return;
    final snapshot = await _previewSnapshot();
    if (snapshot == null || !mounted) return;
    final l = context.appLocalizations;
    await BaseNavigator.push(
      context,
      EditorPage(
        title:
            '${l.policyDraftGeneratePreview} · ${_dirty || _storedRaw == null ? l.policyDraftUnsaved : l.policyDraftSaved}',
        content: snapshot.maskedYaml,
        readOnly: true,
      ),
    );
  }

  Future<void> _copyFull() async {
    if (_busy || _draft == null) return;
    final snapshot = await _previewSnapshot();
    if (snapshot == null || !mounted) return;
    if (!await _confirm(context.appLocalizations.policyDraftCopyFullConfirm)) {
      return;
    }
    if (!mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: snapshot.fullYaml));
      if (mounted) _notify(context.appLocalizations.copySuccess);
    } catch (_) {
      if (mounted) _notify(context.appLocalizations.clipboardWriteFailed);
    }
  }

  Future<void> _leave() async {
    if (_loadingMaterial) _discardMaterial();
    if (_busy || _leaving) return;
    _leaving = true;
    try {
      if (_dirty) {
        final l = context.appLocalizations;
        final choice = await dialogs.showCommonDialog<String>(
          context: context,
          child: CommonDialog(
            title: l.policyDraftDiscard,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('discard'),
                child: Text(l.confirm),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop('save'),
                child: Text(l.save),
              ),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return;
        if (choice == 'save' && !await _save()) return;
      }
      if (mounted) {
        setState(() => _allowPop = true);
        Navigator.of(context).pop();
      }
    } finally {
      _leaving = false;
    }
  }

  Future<PolicyDraftFormResult?> _form(
    PolicyDraftFormKind kind,
    String title,
    Map<String, dynamic> initial, {
    String? resourceId,
  }) => dialogs.showCommonDialog<PolicyDraftFormResult>(
    context: context,
    child: PolicyDraftForm(
      kind: kind,
      title: title,
      document: _draft!,
      initial: initial,
      resourceId: resourceId,
    ),
  );

  Future<void> _editRow(String field, [int? index]) async {
    final domain = field == 'domainRules';
    final rows = _draft!.rows(field);
    final value = await _form(
      domain ? PolicyDraftFormKind.domain : PolicyDraftFormKind.ip,
      domain
          ? context.appLocalizations.policyDraftDomainRules
          : context.appLocalizations.policyDraftIpRules,
      index == null
          ? {'id': 'row$uniqueId'}
          : Map<String, dynamic>.from(rows[index]),
    );
    if (value == null || !mounted) return;
    _change(
      () => _draft!.policy[field] = [
        for (final (i, row) in rows.indexed) i == index ? value.value : row,
        if (index == null) value.value,
      ],
    );
  }

  void _move(String field, int from, int to) {
    _change(() {
      final rows = [..._draft!.rows(field)];
      rows.insert(to, rows.removeAt(from));
      _draft!.policy[field] = rows;
    });
  }

  Future<void> _editSingleton(
    String field,
    PolicyDraftFormKind kind,
    String title,
  ) async {
    final original = _draft!.policy[field];
    final initial = field == 'ipDefault'
        ? {'target': original}
        : Map<String, dynamic>.from(original ?? {});
    final result = await _form(kind, title, initial);
    if (result == null || !mounted) return;
    _change(
      () => _draft!.policy[field] = field == 'ipDefault'
          ? result.value['target']
          : result.value,
    );
  }

  Future<void> _editResource(
    String category,
    String title, [
    String? id,
  ]) async {
    if (id != null) {
      final current = _draft!.resources(category)[id];
      if (current is Map && current.containsKey('source')) {
        await _bindSource(
          category == 'collections' ? current['kind'] as String : category,
          id: id,
        );
        return;
      }
    }
    final resourceId = id ?? 'resource$uniqueId';
    final kind = switch (category) {
      'proxies' => PolicyDraftFormKind.proxy,
      'groups' => PolicyDraftFormKind.group,
      _ => PolicyDraftFormKind.dns,
    };
    final current = _draft!.resources(category)[resourceId];
    final initial = category == 'groups'
        ? {'members': current ?? []}
        : Map<String, dynamic>.from(
            current ??
                (category == 'proxies' ? {'type': 'socks5', 'udp': false} : {}),
          );
    final result = await _form(kind, title, initial, resourceId: resourceId);
    if (result == null || !mounted) return;
    _change(() {
      _draft!.policy[category] = {
        ..._draft!.resources(category),
        resourceId: category == 'groups'
            ? result.value['members']
            : result.value,
      };
      _draft!.setLabel(resourceId, result.label);
    });
  }

  Future<void> _removeResource(String category, String id) async {
    final refs = policyDraftResourceReferences(_draft!, category, id);
    if (refs.isNotEmpty) {
      await dialogs.showMessage(
        context: context,
        cancelable: false,
        message: TextSpan(
          text: context.appLocalizations.policyDraftReferenced(refs.join(', ')),
        ),
      );
      return;
    }
    _change(() {
      _draft!.policy[category] = {..._draft!.resources(category)}..remove(id);
      if (![
        'proxies',
        'groups',
        'dnsServices',
        'collections',
      ].any((c) => _draft!.resources(c).containsKey(id))) {
        _draft!.removeLabel(id);
      }
    });
  }

  Widget _section(String label, VoidCallback add) => ListTile(
    title: Text(label),
    trailing: IconButton(
      tooltip: '${context.appLocalizations.add} $label',
      onPressed: add,
      icon: const GlyphIcon(AppGlyphs.add),
    ),
  );

  List<Widget> _rows(String field, String title) {
    final l = context.appLocalizations;
    final rows = _draft!.rows(field);
    return [
      _section(title, () => _editRow(field)),
      for (final (i, row) in rows.indexed)
        ListTile(
          key: ValueKey('draft-$field-$i'),
          title: Text(
            '${i + 1}. ${row['collection'] is String ? _draft!.label(row['collection']) : row['value'] ?? row['cidr'] ?? l.policyDraftUnset}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${row['collection'] != null ? l.policyMaterialCollections : row['type'] ?? 'CIDR'} · ${_targetText(row['target'])}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l.policyDraftMoveUp,
                onPressed: i == 0 ? null : () => _move(field, i, i - 1),
                icon: const GlyphIcon(AppGlyphs.arrowUp),
              ),
              IconButton(
                tooltip: l.policyDraftMoveDown,
                onPressed: i == rows.length - 1
                    ? null
                    : () => _move(field, i, i + 1),
                icon: const GlyphIcon(AppGlyphs.arrowDown),
              ),
              IconButton(
                tooltip: l.edit,
                onPressed: () => _editRow(field, i),
                icon: const GlyphIcon(AppGlyphs.edit),
              ),
              IconButton(
                tooltip: l.delete,
                onPressed: () => _change(
                  () => _draft!.policy[field] = [...rows]..removeAt(i),
                ),
                icon: const GlyphIcon(AppGlyphs.delete),
              ),
            ],
          ),
        ),
    ];
  }

  String _targetText(dynamic target) {
    final l = context.appLocalizations;
    if (target is! Map) return l.policyDraftUnset;
    return switch (target['kind']) {
      'direct' => 'DIRECT',
      'reject' => 'REJECT',
      'proxy' => '${l.proxyGroup}: ${_draft!.label('${target['group']}')}',
      _ => l.policyDraftUnset,
    };
  }

  List<Widget> _resources(String category, String title) => [
    _section(
      title,
      () => category == 'collections'
          ? _bindSource('domain')
          : _editResource(category, title),
    ),
    for (final id in _draft!.resources(category).keys)
      ListTile(
        title: Text(
          _draft!.label(id),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _editResource(category, title, id),
        trailing: IconButton(
          tooltip: context.appLocalizations.delete,
          onPressed: () => _removeResource(category, id),
          icon: const GlyphIcon(AppGlyphs.delete),
        ),
      ),
  ];

  String _migrationMessage(String code) {
    final l = context.appLocalizations;
    return switch (code) {
      'ip' => l.policyDraftMigrationIp,
      'intermediate_match' => l.policyDraftMigrationMatch,
      'script' => l.policyDraftMigrationScript,
      _ => l.policyDraftMigrationUnsupported,
    };
  }

  Widget _migration() {
    final PolicyMigrationAnalysis analysis = analyzePolicyMigration(
      _draft!.migration,
    );
    final l = context.appLocalizations;
    final Iterable<PolicyMigrationIssue> generalIssues = {
      for (final issue in analysis.issues.where((i) => i.index == null))
        '${issue.code}:${issue.location}': issue,
    }.values;
    return ExpansionTile(
      title: Text(l.policyDraftMigration),
      subtitle: analysis.issues.isEmpty
          ? null
          : Text(l.policyDraftMigrationBlocked),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(l.policyDraftMigrationChoices),
        ),
        for (final issue in generalIssues)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${issue.location}: ${_migrationMessage(issue.code)}'),
          ),
        SizedBox(
          height: 320,
          child: ListView.builder(
            itemCount: analysis.rules.length,
            itemBuilder: (_, i) => ListTile(
              title: Text('${i + 1}. ${analysis.rules[i]}'),
              subtitle: Text(
                [
                  switch (analysis.origins[i]) {
                    'profile' => l.profile,
                    'global' => l.global,
                    'custom' => l.custom,
                    _ => l.source,
                  },
                  ...analysis.issues
                      .where((p) => p.index == i)
                      .map((p) => _migrationMessage(p.code)),
                ].join('\n'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final editable = !_busy && _draft != null && !_draft!.isReadOnly;
    final problem =
        _problemLocation ??
        (_draft == null ? null : policyDraftInputProblem(_draft!));
    final canPreview = editable && problem == null;
    final supportsManaged = ref
        .read(policySelectionActionProvider.notifier)
        .supportsManaged;
    return PopScope(
      canPop: !_busy && (!_dirty || _allowPop),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: CommonScaffold(
        title: '${l.policyDraftTitle} · ${widget.profile.realLabel}',
        isLoading: _busy,
        backAction: _leave,
        primaryAction: IconButtonData(
          glyph: AppGlyphs.save,
          tooltip: l.save,
          onPressed: editable ? () => _save() : null,
        ),
        iconActions: [
          IconButtonData(
            glyph: AppGlyphs.eye,
            tooltip: l.policyDraftGeneratePreview,
            onPressed: canPreview ? _preview : null,
          ),
        ],
        menuItems: [
          if (_material != null || _loadingMaterial)
            CommonPopupMenuItem(
              label: l.policyMaterialCancel,
              glyph: AppGlyphs.close,
              onPressed: _busy && !_loadingMaterial ? null : _discardMaterial,
            ),
          CommonPopupMenuItem(
            label: l.policyMaterialBindings,
            glyph: AppGlyphs.importFile,
            onPressed: editable ? _sourcesMenu : null,
          ),
          CommonPopupMenuItem(
            label: l.policyActualPreview,
            glyph: AppGlyphs.eye,
            onPressed: () => BaseNavigator.push<String>(
              context,
              PreviewProfileView(profile: widget.profile, actual: true),
            ),
          ),
          CommonPopupMenuItem(
            label: l.policyApply,
            glyph: AppGlyphs.check,
            onPressed: canPreview && supportsManaged ? _apply : null,
          ),
          CommonPopupMenuItem(
            label: l.policyOriginal,
            glyph: AppGlyphs.refresh,
            onPressed: !_busy && _selected != null ? _useOriginal : null,
          ),
          CommonPopupMenuItem(
            label: l.policyDraftCopyFull,
            glyph: AppGlyphs.copy,
            onPressed: canPreview ? _copyFull : null,
          ),
          CommonPopupMenuItem(
            label: l.policyDraftExtract,
            glyph: AppGlyphs.importFile,
            onPressed: editable ? _extract : null,
          ),
          CommonPopupMenuItem(
            label: l.policyDraftReload,
            glyph: AppGlyphs.refresh,
            onPressed: !_busy ? _reload : null,
          ),
          CommonPopupMenuItem(
            label: l.policyDraftRebuild,
            glyph: AppGlyphs.add,
            onPressed: !_busy ? _rebuild : null,
          ),
          CommonPopupMenuItem(
            label: l.delete,
            glyph: AppGlyphs.delete,
            danger: true,
            onPressed: !_busy && _storedRaw != null ? _delete : null,
          ),
        ],
        body: Builder(
          builder: (bodyContext) => AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                bodyContext.contentTopPadding,
                16,
                16 + BottomInsetScope.of(bodyContext),
              ),
              children: [
                Text(_selectionStatus()),
                if (!supportsManaged) Text(l.policyAndroidRequired),
                Text(
                  _dirty || _storedRaw == null
                      ? l.policyDraftUnsaved
                      : l.policyDraftSaved,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l.policyDraftStorage),
                ),
                if (_draft == null) ...[
                  if (!_busy) Text(l.policyDraftLoadFailed),
                ] else if (_draft!.isReadOnly)
                  Text(l.policyDraftReadOnly)
                else ...[
                  if (problem != null)
                    Text(
                      problem == 'migration'
                          ? l.policyDraftMigrationBlocked
                          : l.policyDraftIncomplete(problem),
                    )
                  else
                    Text(
                      _previewed
                          ? l.policyDraftReady
                          : l.policyDraftNeedsPreview,
                    ),
                  ListTile(
                    title: Text(l.policyDraftDomainDefault),
                    subtitle: Text(
                      _targetText(_draft!.policy['domainDefault']?['target']),
                    ),
                    onTap: () => _editSingleton(
                      'domainDefault',
                      PolicyDraftFormKind.domainDefault,
                      l.policyDraftDomainDefault,
                    ),
                  ),
                  ListTile(
                    title: Text(l.policyDraftIpDefault),
                    subtitle: Text(_targetText(_draft!.policy['ipDefault'])),
                    onTap: () => _editSingleton(
                      'ipDefault',
                      PolicyDraftFormKind.ipDefault,
                      l.policyDraftIpDefault,
                    ),
                  ),
                  ..._rows('domainRules', l.policyDraftDomainRules),
                  ..._rows('ipRules', l.policyDraftIpRules),
                  ..._resources('proxies', l.policyDraftNodes),
                  ..._resources('groups', l.policyDraftGroups),
                  if (isMaterialTemplate(_draft!.policy))
                    ..._resources('collections', l.policyMaterialCollections),
                  ..._resources('dnsServices', l.policyDraftDnsServices),
                  ListTile(
                    title: Text(l.policyDraftBootstrap),
                    onTap: () => _editSingleton(
                      'bootstrapDns',
                      PolicyDraftFormKind.bootstrap,
                      l.policyDraftBootstrap,
                    ),
                  ),
                  ListTile(
                    title: Text(l.policyDraftListeners),
                    onTap: () => _editSingleton(
                      'listeners',
                      PolicyDraftFormKind.listeners,
                      l.policyDraftListeners,
                    ),
                  ),
                  if (_draft!.migration != null) _migration(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
