import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/profile_import.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProfileUrlImportDialog extends ConsumerStatefulWidget {
  const ProfileUrlImportDialog({super.key});

  @override
  ConsumerState<ProfileUrlImportDialog> createState() =>
      _ProfileUrlImportDialogState();
}

class _ProfileUrlImportDialogState
    extends ConsumerState<ProfileUrlImportDialog> {
  String _label = '';
  String _url = '';
  RequestMode _mode = RequestMode.auto;
  String? _proxy;
  Object? _error;
  ProfileImportTask? _task;
  ProfileImportPhase _phase = ProfileImportPhase.preparing;
  Widget? _review;
  Completer<SourceReviewDecision?>? _response;

  void _cancelAttempt() {
    _task?.cancel();
    final response = _response;
    if (response != null && !response.isCompleted) response.complete(null);
    _response = null;
    _task = null;
    _review = null;
  }

  @override
  void dispose() {
    _cancelAttempt();
    super.dispose();
  }

  void _decide(SourceReviewDecision? decision) {
    final response = _response;
    if (response == null || response.isCompleted) return;
    if (decision == null) {
      setState(_cancelAttempt);
    } else {
      setState(() {
        _phase = ProfileImportPhase.saving;
        _review = null;
      });
      response.complete(decision);
    }
  }

  Future<void> _submit(({String label, String url}) input) async {
    if (_task != null) return;
    late final ProfileImportTask task;
    task = ProfileImportTask(
      onPhase: (phase) {
        if (mounted && identical(_task, task)) {
          setState(() => _phase = phase);
        }
      },
    );
    setState(() {
      _label = input.label;
      _url = input.url;
      _error = null;
      _phase = ProfileImportPhase.preparing;
      _task = task;
    });
    try {
      final result = await ref
          .read(profilesActionProvider.notifier)
          .addProfileFormURL(
            _url,
            label: _label,
            mode: _mode,
            proxy: _proxy,
            confirmed: true,
            importTask: task,
            reviewPresentation: (
              present: (child) {
                if (!mounted || !task.isCurrent || !identical(_task, task)) {
                  return Future.value(null);
                }
                final response = Completer<SourceReviewDecision?>();
                setState(() {
                  _phase = ProfileImportPhase.reviewing;
                  _review = child;
                  _response = response;
                });
                return response.future;
              },
              onDecision: (decision) {
                if (task.isCurrent && identical(_task, task)) _decide(decision);
              },
            ),
          );
      if (!mounted || !task.isCurrent || !identical(_task, task)) return;
      if (result?.materialSaved == true) {
        Navigator.of(context).pop(true);
      } else {
        throw const RequestUnavailable('request_cancelled');
      }
    } catch (error) {
      if (mounted && task.isCurrent && identical(_task, task)) {
        setState(() {
          _cancelAttempt();
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final reservedLabels = ref.watch(
      appProviderLabelsProvider(ProviderKind.proxy),
    );
    final busy = _task != null;
    final saving = busy && _phase == ProfileImportPhase.saving;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && busy && !saving) setState(_cancelAttempt);
      },
      child:
          _review ??
          (busy
              ? CommonDialog(
                  title: l.importFromURL,
                  actions: [
                    if (!saving)
                      TextButton(
                        onPressed: () => setState(_cancelAttempt),
                        child: Text(l.cancel),
                      ),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 16,
                    children: [
                      if (_label.isNotEmpty) Text(_label),
                      Text(switch (_phase) {
                        ProfileImportPhase.saving => l.profileImportSaving,
                        ProfileImportPhase.downloading =>
                          l.profileImportDownloading,
                        _ => l.profileImportPreparing,
                      }),
                      const LinearProgressIndicator(),
                    ],
                  ),
                )
              : NamedUrlDialog(
                  title: l.importFromURL,
                  label: _label,
                  url: _url,
                  submitText: l.profileImportContinue,
                  errorText: _error == null
                      ? null
                      : switch (_error) {
                          RequestUnavailable(code: 'profile_download_failed') =>
                            l.profileImportDownloadFailed,
                          RequestUnavailable(code: 'profile_invalid') =>
                            l.profileImportInvalid,
                          _ => userFacingErrorMessage(_error!, l),
                        },
                  requestMode: _mode,
                  requestProxy: _proxy,
                  requestRouteCollapsible: false,
                  onRequestRouteChanged: (value) {
                    _mode = value.$1;
                    _proxy = value.$2;
                  },
                  labelValidator: (value) =>
                      reservedLabels.contains(value?.trim())
                      ? l.existsTip(l.name)
                      : null,
                  onSubmit: (input) => unawaited(_submit(input)),
                )),
    );
  }
}
