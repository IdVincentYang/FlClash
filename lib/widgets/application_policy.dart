import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/android_service_state.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/application_routing.dart';
import 'package:fl_clash/views/application_policy.dart';
import 'application_policy_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ApplicationPolicySwitch extends ConsumerWidget {
  const ApplicationPolicySwitch({
    super.key,
    required this.packages,
    required this.label,
  });
  final List<String> packages;
  final String label;

  Future<void> _choose(BuildContext context) async {
    if (!await confirmApplicationPackages(context, packages) ||
        !context.mounted) {
      return;
    }
    await BaseNavigator.push(
      context,
      ApplicationPolicyView(packages: packages, label: label),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (packages.isEmpty) return const SizedBox.shrink();
    final l = context.appLocalizations;
    final settings = ref.watch(applicationRoutingSettingsProvider).value;
    final rule =
        settings?.rules[packages.first] ??
        ApplicationRouteRule(packageName: packages.first);
    final target = applicationTargetState(ref, rule);
    final operation = ref.watch(applicationRoutingControllerProvider);
    final pending = packages.any(operation.pending.contains);
    final error = packages
        .map((name) => operation.errors[name])
        .whereType<String>()
        .firstOrNull;
    final global =
        ref.watch(patchClashConfigProvider.select((value) => value.mode)) ==
        Mode.global;
    final native = ref.watch(nativeRequestStateProvider);
    final vpn = ref.watch(vpnSettingProvider).accessControlProps;
    final captured = packages.every((name) => applicationCaptured(vpn, name));
    final running =
        ref.watch(androidServiceStatusProvider) ==
        AndroidServiceStatus.vpnActive;
    final fact = ref.watch(configStateProvider).fact;
    final entries = ref.watch(applicationRoutingKeysProvider);
    final adopted =
        fact.profileId == ref.watch(currentProfileIdProvider) &&
        packages.every(
          (name) => fact.applicationRoutingRules[name] == entries[name],
        );
    final invalid =
        rule.enabled &&
        rule.action == ApplicationRouteAction.proxy &&
        target.issue != null &&
        target.issue != ApplicationTargetIssue.preparing;
    final policyIdentities = packages.map((name) {
      final policy = settings?.rules[name];
      if (policy == null || !policy.enabled) return '';
      if (policy.action != ApplicationRouteAction.proxy) {
        return policy.action.name;
      }
      final target = applicationTargetFor(
        settings!,
        policy,
        ref.read(currentProfileIdProvider),
      );
      return target?.groupId != null
          ? 'group:${target!.groupId}'
          : target?.name ?? '';
    }).toSet();
    final sharedConflict = policyIdentities.length > 1;
    final failed =
        sharedConflict ||
        error != null ||
        invalid ||
        !rule.enabled && !adopted && !pending && running;
    final waiting =
        pending ||
        rule.enabled &&
            (global ||
                !running ||
                !captured ||
                pending ||
                !adopted ||
                native['captureFingerprint'] !=
                    applicationCaptureFingerprint(vpn) ||
                target.issue == ApplicationTargetIssue.preparing &&
                    rule.action == ApplicationRouteAction.proxy);
    final color = failed
        ? context.colorScheme.error
        : waiting
        ? Colors.amber.shade700
        : !rule.enabled
        ? context.colorScheme.outline
        : context.colorScheme.primary;
    final configuredName = switch (rule.action) {
      ApplicationRouteAction.direct => 'DIRECT',
      ApplicationRouteAction.reject => 'REJECT',
      ApplicationRouteAction.proxy => target.target?.name ?? l.appPolicyChoose,
    };
    final name = !rule.enabled
        ? (ref.watch(patchClashConfigProvider).mode == Mode.direct
              ? 'DIRECT'
              : l.appPolicyFollowRule)
        : configuredName;
    final statusGlyph = failed
        ? AppGlyphs.warning
        : global
        ? AppGlyphs.playPause(1)
        : !running
        ? AppGlyphs.wifiOff
        : !captured
        ? AppGlyphs.vpn
        : waiting
        ? AppGlyphs.sync
        : AppGlyphs.check;
    final reason =
        error ??
        (sharedConflict
            ? l.appPolicySharedIdentity(packages.join('\n'))
            : null) ??
        (invalid
            ? applicationTargetIssueText(context, target.issue)
            : global
            ? l.appPolicyGlobalPaused
            : !captured
            ? l.appPolicyExcluded
            : !running
            ? l.appPolicyVpnStopped
            : waiting || !adopted
            ? l.appPolicyPreparing
            : rule.enabled
            ? l.appPolicyApplied
            : l.disabled);
    return SizedBox(
      width: 112,
      child: Tooltip(
        message: '$name\n$reason',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: pending || settings == null
                  ? null
                  : () => _choose(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                child: Row(
                  children: [
                    if (failed || waiting || rule.enabled) ...[
                      if (pending)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        GlyphIcon(statusGlyph, size: 14, color: color),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: Switch(
                value: rule.enabled,
                activeTrackColor: color,
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? color
                      : failed
                      ? color.withValues(alpha: 0.3)
                      : null,
                ),
                onChanged: global || pending || settings == null
                    ? null
                    : (enabled) async {
                        if (!await confirmApplicationPackages(
                              context,
                              packages,
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        if (enabled &&
                            rule.action == ApplicationRouteAction.proxy &&
                            !target.available) {
                          await BaseNavigator.push(
                            context,
                            ApplicationPolicyView(
                              packages: packages,
                              label: label,
                              enableOnSave: true,
                            ),
                          );
                          return;
                        }
                        try {
                          await ref
                              .read(
                                applicationRoutingControllerProvider.notifier,
                              )
                              .setEnabled(packages, enabled);
                        } catch (error) {
                          if (context.mounted) {
                            context.showNotifier(
                              userFacingErrorMessage(error, l),
                              level: MessageLevel.error,
                            );
                          }
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
