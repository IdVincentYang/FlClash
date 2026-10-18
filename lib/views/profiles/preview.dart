import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PreviewProfileView extends ConsumerStatefulWidget {
  final Profile profile;
  final bool actual;

  const PreviewProfileView({
    super.key,
    required this.profile,
    this.actual = false,
  });

  @override
  ConsumerState<PreviewProfileView> createState() => _PreviewProfileViewState();
}

class _PreviewProfileViewState extends ConsumerState<PreviewProfileView> {
  String? _full;
  String? _actualName;

  Future<String> _load() async {
    final String full;
    if (widget.actual) {
      final core = ref.read(coreHandlerProvider);
      final before = await core.getConfigState();
      final map = await core.getAppliedConfig();
      final after = await core.getConfigState();
      if (before.runtimeEpoch != after.runtimeEpoch ||
          before.version != after.version ||
          before.inputId != after.inputId) {
        throw const RequestUnavailable('request_cancelled');
      }
      if (map.containsKey('rule')) map['rules'] = map.remove('rule');
      full = await encodeYamlTask(map);
      if (mounted) setState(() => _actualName = before.profileName);
    } else {
      full = await ref
          .read(setupActionProvider.notifier)
          .getProfileWithId(widget.profile.id);
    }
    final masked = maskedPolicyConfig(full);
    _full = full;
    return masked;
  }

  Future<void> _copyFull() async {
    final snapshot = _full;
    if (snapshot == null) return;
    if (await dialogs.showMessage(
              context: context,
              message: TextSpan(
                text: context.appLocalizations.policyDraftCopyFullConfirm,
              ),
            ) !=
            true ||
        !mounted) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: snapshot));
      if (mounted) context.showNotifier(context.appLocalizations.copySuccess);
    } catch (_) {
      if (mounted) {
        context.showNotifier(context.appLocalizations.clipboardWriteFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return EditorPage(
      title:
          '${widget.actual ? l.policyActualPreview : l.policyFinalPreview} · ${_actualName ?? widget.profile.realLabel}',
      load: _load,
      readOnly: true,
      onCopyFull: _copyFull,
    );
  }
}
