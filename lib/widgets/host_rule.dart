import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'application_policy_status.dart';
import 'package:material_ui/material_ui.dart';

String hostPolicyLabel(
  BuildContext context,
  WidgetRef ref,
  String host,
  List<String> packages,
) {
  final settings =
      ref.watch(applicationRoutingSettingsProvider).value ??
      const ApplicationRoutingSettings();
  final profile = ref.watch(currentProfileIdProvider);
  final mode = ref.watch(patchClashConfigProvider).mode;
  final selected = effectiveHostPolicyForPackages(
    settings,
    host,
    packages,
    profile,
    mode,
  );
  final rule = selected.hostRule;
  if (rule != null) {
    if (rule.hostBinding!.legacy) {
      return context.appLocalizations.appPolicyFollowRule;
    }
    return const {'DIRECT', 'REJECT'}.contains(rule.ruleTarget)
        ? rule.ruleTarget!
        : hostRuleTargetState(ref, rule)?.target?.name ??
              hostRuleTarget(rule, profile)?.name ??
              rule.ruleTarget ??
              context.appLocalizations.appPolicyChoose;
  }
  final app = selected.appRule;
  if (app != null) {
    return switch (app.action) {
      ApplicationRouteAction.direct => 'DIRECT',
      ApplicationRouteAction.reject => 'REJECT',
      ApplicationRouteAction.proxy =>
        applicationTargetFor(settings, app, profile)?.name ??
            context.appLocalizations.appPolicyChoose,
    };
  }
  return selected.fallback.isNotEmpty
      ? selected.fallback
      : context.appLocalizations.appPolicyFollowRule;
}

class HostRuleButton extends ConsumerWidget {
  const HostRuleButton({
    super.key,
    required this.host,
    required this.packages,
    required this.onPressed,
  });
  final String host;
  final List<String> packages;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = hostPolicyLabel(context, ref, host, packages);
    final settings = ref.watch(applicationRoutingSettingsProvider).value;
    final fact = ref.watch(configStateProvider).fact;
    final wire = ref.watch(applicationRoutingWireProvider);
    final adopted =
        settings != null && fact.applicationRoutingRevision == wire['revision'];
    final global = ref.watch(patchClashConfigProvider).mode == Mode.global;
    final running = ref.watch(runControlProvider);
    final selected = effectiveHostPolicyForPackages(
      settings ?? const ApplicationRoutingSettings(),
      host,
      packages,
      ref.watch(currentProfileIdProvider),
      ref.watch(patchClashConfigProvider).mode,
    );
    final label = selected.appRule != null
        ? context.appLocalizations.appPolicyFollowApp
        : detail;
    final target = selected.hostRule != null
        ? hostRuleTargetState(ref, selected.hostRule!)
        : selected.appRule?.action == ApplicationRouteAction.proxy
        ? applicationTargetState(ref, selected.appRule!)
        : null;
    final issue = target?.issue;
    final failed = issue != null && issue != ApplicationTargetIssue.preparing;
    final pending =
        !adopted ||
        !running ||
        global ||
        issue == ApplicationTargetIssue.preparing;
    final color = failed
        ? context.colorScheme.error
        : pending
        ? context.colorScheme.onSurfaceVariant
        : context.colorScheme.primary;
    final reason = failed
        ? applicationTargetIssueText(context, issue)
        : global
        ? context.appLocalizations.appPolicyGlobalPaused
        : !running
        ? context.appLocalizations.appPolicyVpnStopped
        : !adopted
        ? context.appLocalizations.appPolicyPreparing
        : context.appLocalizations.appPolicyApplied;
    return SizedBox(
      width: 64,
      height: 56,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
        child: Tooltip(
          message: '${label == detail ? detail : '$label · $detail'}\n$reason',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (failed) ...[
                GlyphIcon(AppGlyphs.warning, size: 14, color: color),
                const SizedBox(height: 2),
              ],
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: SizedBox(
                    width: 56,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
