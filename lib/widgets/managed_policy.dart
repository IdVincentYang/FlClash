import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/policy_draft.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<bool> chooseProfileFromUi(
  BuildContext context,
  WidgetRef ref,
  int? profileId,
) async =>
    await globalState.safeRun(
      () => ref
          .read(policySelectionActionProvider.notifier)
          .chooseProfile(
            profileId,
            confirmLeave: () async =>
                await dialogs.showMessage(
                  context: context,
                  message: TextSpan(
                    text: context.appLocalizations.policyOriginalConfirm,
                  ),
                ) ==
                true,
          ),
    ) ==
    true;

Widget? managedPolicySettingsGate(
  BuildContext context,
  WidgetRef ref, {
  int? profileId,
}) {
  final id = profileId ?? ref.watch(currentProfileIdProvider);
  if (id == null) return null;
  final selection = ref.watch(policySelectionProvider(id));
  if (selection.hasValue && selection.value == null) return null;
  final profile = ref.watch(profileProvider(id));
  final l = context.appLocalizations;
  return CommonScaffold(
    title: l.policyDraftTitle,
    body: selection.isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l.policyManagedEditRequired),
              if (profile != null)
                ListItem.open(
                  title: Text(l.policyDraftTitle),
                  widget: PolicyDraftView(profile: profile),
                ),
            ],
          ),
  );
}
