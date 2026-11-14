import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

final applicationRoutingSettingsProvider =
    StreamProvider<ApplicationRoutingSettings>((ref) {
      return database.watchApplicationRouting();
    });

final applicationRoutingWireProvider = Provider<Map<String, dynamic>>(
  (ref) => compileApplicationRouting(
    ref.watch(applicationRoutingSettingsProvider).value ??
        const ApplicationRoutingSettings(),
    ref.watch(currentProfileIdProvider),
  ),
);

final applicationRoutingKeysProvider = Provider<Map<String, String>>((ref) {
  final wire = ref.watch(applicationRoutingWireProvider);
  return {
    for (final entry in wire['hostRules'] as List? ?? [])
      '@host:${entry['id']}': hostRuleKey(
        Map<String, dynamic>.from(entry as Map),
      ),
    for (final entry in wire['rules'] as List)
      entry['package'] as String: applicationRuleKey(
        Map<String, dynamic>.from(entry as Map),
      ),
  };
});

class ApplicationRoutingOperation {
  const ApplicationRoutingOperation({
    this.pending = const {},
    this.errors = const {},
  });
  final Set<String> pending;
  final Map<String, String> errors;
}

final applicationRoutingControllerProvider =
    NotifierProvider<ApplicationRoutingController, ApplicationRoutingOperation>(
      ApplicationRoutingController.new,
    );

class ApplicationRoutingController
    extends Notifier<ApplicationRoutingOperation> {
  int _generation = 0;

  @override
  ApplicationRoutingOperation build() => const ApplicationRoutingOperation();

  Future<void> _change(
    Set<String> affected,
    FutureOr<ApplicationRoutingSettings> Function(ApplicationRoutingSettings)
    update, {
    bool rebuild = false,
  }) async {
    final generation = ++_generation;
    state = ApplicationRoutingOperation(
      pending: {...state.pending, ...affected},
      errors: Map.of(state.errors)
        ..removeWhere((key, _) => affected.contains(key)),
    );
    final setup = ref.read(setupActionProvider.notifier);
    var persisted = false;
    try {
      final saved = await request.mutate(
        () => database.transaction(() async {
          final previous = await database.readApplicationRouting();
          return database.writeApplicationRouting(await update(previous));
        }),
      );
      persisted = true;
      if (!ref.mounted || generation != _generation) return;
      setup.reserveSetupSequence();
      final needsGroupBinding =
          saved.hostRules.any(
            (r) =>
                hostRuleApplies(r, ref.read(currentProfileIdProvider)) &&
                (affected.contains('@host:${r.id}') ||
                    affected.contains(r.hostBinding!.packageName)) &&
                (r.hostBinding!.packageName == null ||
                    saved.rules[r.hostBinding!.packageName]?.enabled == true) &&
                hostRuleTarget(
                      r,
                      ref.read(currentProfileIdProvider),
                    )?.groupId !=
                    null,
          ) ||
          affected.any((package) {
            final rule = saved.rules[package];
            return rule != null &&
                rule.enabled &&
                rule.action == ApplicationRouteAction.proxy &&
                applicationTargetFor(
                      saved,
                      rule,
                      ref.read(currentProfileIdProvider),
                    )?.kind ==
                    ApplicationTargetKind.globalGroup;
          });
      if (needsGroupBinding) {
        await ref
            .read(globalGroupsActionProvider.notifier)
            .synchronizeApplicationGroups();
      }
      if (!ref.mounted || generation != _generation) return;
      final profileId = ref.read(currentProfileIdProvider);
      final core = ref.read(coreHandlerProvider);
      final ConfigFact fact;
      try {
        fact = await core.getConfigState();
      } catch (_) {
        if (!ref.read(runControlProvider)) return;
        rethrow;
      }
      if (!ref.mounted || generation != _generation) return;
      if (rebuild && ref.read(initProvider)) {
        if (!await setup.applyProfile(force: true, allowSourceReview: false)) {
          throw const RequestUnavailable('configuration_reapply_required');
        }
      } else if (fact.profileId == profileId && fact.phase == 'ready') {
        final result = await core.updateApplicationRouting(
          compileApplicationRouting(saved, profileId),
        );
        if (result.isNotEmpty) throw MessageException(result);
        await ref.read(configStateProvider.notifier).refresh();
      } else if (profileId != null &&
          ref.read(initProvider) &&
          ref.read(runControlProvider)) {
        final applied = await setup.applyProfile(
          force: true,
          allowSourceReview: false,
        );
        if (!applied) {
          throw const RequestUnavailable('configuration_reapply_required');
        }
      }
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = ApplicationRoutingOperation(
          pending: state.pending.difference(affected),
          errors: {
            ...state.errors,
            if (persisted)
              for (final key in affected)
                key: userFacingErrorMessage(error, currentAppLocalizations),
          },
        );
      }
      rethrow;
    } finally {
      if (ref.mounted && generation == _generation) {
        state = ApplicationRoutingOperation(errors: state.errors);
      }
    }
  }

  Future<void> setEnabled(Iterable<String> packages, bool enabled) =>
      _change(packages.toSet(), (previous) {
        final rules = Map.of(previous.rules);
        for (final package in packages) {
          final rule =
              rules[package] ?? ApplicationRouteRule(packageName: package);
          rules[package] = rule.copyWith(enabled: enabled);
        }
        return previous.copyWith(rules: rules);
      });

  Future<void> setPolicy(
    Iterable<String> packages,
    ApplicationRouteAction action, {
    ApplicationRouteTarget? target,
    bool shared = false,
    bool? enable,
    int? expectedProfileId,
  }) {
    final profileId = expectedProfileId ?? ref.read(currentProfileIdProvider);
    return _change(packages.toSet(), (previous) {
      if (target != null &&
          (profileId == null ||
              ref.read(currentProfileIdProvider) != profileId)) {
        throw MessageException(currentAppLocalizations.localGroupsChanged);
      }
      final rules = Map.of(previous.rules);
      for (final package in packages) {
        final rule =
            rules[package] ?? ApplicationRouteRule(packageName: package);
        rules[package] = rule.copyWith(
          hasDefault: true,
          enabled: enable ?? rule.enabled,
          action: action,
          useSharedTarget: shared,
          targets: {
            ...rule.targets,
            if (target != null && profileId != null) profileId: target,
          },
        );
      }
      return previous.copyWith(rules: rules);
    });
  }

  Future<void> saveHostRules(
    List<Rule> hostRules, {
    required int expectedProfileId,
  }) => _change(
    {
      for (final rule in hostRules) ...{
        ?rule.hostBinding?.packageName,
        '@host:${rule.id}',
      },
    },
    (previous) async {
      if (ref.read(currentProfileIdProvider) != expectedProfileId) {
        throw MessageException(currentAppLocalizations.localGroupsChanged);
      }
      for (final rule in hostRules) {
        await database.rulesDao.putGlobalRule(
          rule.copyWith(hostBinding: rule.hostBinding!.copyWith(legacy: false)),
        );
        await database.rulesDao.delDisabledLink(expectedProfileId, rule.id);
      }
      final next = await database.readApplicationRouting();
      final rules = Map.of(next.rules);
      for (final rule in hostRules) {
        final package = rule.hostBinding?.packageName;
        if (package != null) {
          rules.putIfAbsent(
            package,
            () => ApplicationRouteRule(
              packageName: package,
              hasDefault: false,
              useSharedTarget: false,
            ),
          );
        }
      }
      return next.copyWith(rules: rules);
    },
    rebuild: hostRules.any((r) => r.hostBinding?.legacy == true),
  );

  Future<void> deleteHostRules(Iterable<int> ids) async {
    final keys = ids.toSet();
    final before = await database.readApplicationRouting();
    return _change(
      {
        for (final rule in before.hostRules)
          if (keys.contains(rule.id)) ...{
            '@host:${rule.id}',
            ?rule.hostBinding?.packageName,
          },
      },
      (previous) async {
        await database.rulesDao.delRules(keys);
        final next = await database.readApplicationRouting();
        return next.copyWith(
          rules: Map.fromEntries(
            next.rules.entries.where(
              (entry) =>
                  entry.value.hasDefault ||
                  next.hostRules.any(
                    (rule) => rule.hostBinding?.packageName == entry.key,
                  ),
            ),
          ),
        );
      },
      rebuild: before.hostRules.any(
        (r) => keys.contains(r.id) && r.hostBinding!.legacy,
      ),
    );
  }

  Future<void> setSharedTarget(
    ApplicationRouteTarget target, {
    int? expectedProfileId,
  }) {
    final profileId = expectedProfileId ?? ref.read(currentProfileIdProvider);
    if (profileId == null) throw const RequestUnavailable('request_cancelled');
    final rules =
        ref.read(applicationRoutingSettingsProvider).value?.rules.values ??
        const <ApplicationRouteRule>[];
    return _change(
      rules.where((r) => r.useSharedTarget).map((r) => r.packageName).toSet(),
      (previous) {
        if (ref.read(currentProfileIdProvider) != profileId) {
          throw MessageException(currentAppLocalizations.localGroupsChanged);
        }
        return previous.copyWith(
          sharedTargets: {...previous.sharedTargets, profileId: target},
        );
      },
    );
  }
}
