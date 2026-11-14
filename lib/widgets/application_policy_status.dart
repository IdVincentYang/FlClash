import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

ApplicationTargetState applicationTargetState(
  WidgetRef ref,
  ApplicationRouteRule rule,
) {
  final settings =
      ref.watch(applicationRoutingSettingsProvider).value ??
      const ApplicationRoutingSettings();
  final profile = ref.watch(currentProfileProvider);
  final fact = ref.watch(configStateProvider).fact;
  final target = resolveApplicationTarget(
    target: applicationTargetFor(settings, rule, profile?.id),
    profile: profile,
    groups: ref.watch(groupsProvider),
    definitions: ref.watch(globalLocalGroupsProvider).value ?? const [],
    ready:
        profile != null &&
        fact.profileId == profile.id &&
        fact.phase == 'ready',
  );
  if (target.issue == ApplicationTargetIssue.preparing &&
      ref.watch(globalGroupsActionProvider) != null) {
    return ApplicationTargetState(
      target: target.target,
      issue: ApplicationTargetIssue.unbound,
    );
  }
  return target;
}

String applicationTargetIssueText(
  BuildContext context,
  ApplicationTargetIssue? issue,
) => switch (issue) {
  ApplicationTargetIssue.preparing =>
    context.appLocalizations.appPolicyPreparing,
  ApplicationTargetIssue.empty => context.appLocalizations.appPolicyEmptyGroup,
  ApplicationTargetIssue.disabled =>
    context.appLocalizations.appPolicyDisabledGroup,
  ApplicationTargetIssue.unbound => context.appLocalizations.appPolicyUnbound,
  _ => context.appLocalizations.appPolicyMissingTarget,
};

class ApplicationPolicyStatus extends ConsumerWidget {
  const ApplicationPolicyStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((value) => value.mode),
    );
    final count = ref
        .watch(configStateProvider)
        .fact
        .applicationRoutingRules
        .length;
    if (mode != Mode.global && (mode != Mode.direct || count == 0)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Text(
        mode == Mode.global
            ? context.appLocalizations.appPolicyGlobalPaused
            : context.appLocalizations.appPolicyDirectExceptions(count),
        style: context.textTheme.bodySmall,
      ),
    );
  }
}

Future<bool> confirmApplicationPackages(
  BuildContext context,
  List<String> packages,
) async {
  if (packages.length <= 1) return packages.isNotEmpty;
  return await dialogs.showMessage(
        context: context,
        message: TextSpan(
          text: context.appLocalizations.appPolicySharedIdentity(
            packages.join('\n'),
          ),
        ),
      ) ==
      true;
}
