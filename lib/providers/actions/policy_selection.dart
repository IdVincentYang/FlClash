part of '../action.dart';

Map<String, String> _withoutManagedPicks(Map<String, String> values) => {
  for (final entry in values.entries)
    if (!entry.key.startsWith('fc-managed-group-')) entry.key: entry.value,
};

@Riverpod(keepAlive: true)
class PolicySelectionAction extends _$PolicySelectionAction {
  bool get supportsManaged => system.isAndroid;

  @protected
  Request get requestClient => request;

  @override
  void build() {}

  Future<ProfilePolicySelection?> load(int profileId) =>
      database.profilePolicySelectionsDao.query(profileId).getSingleOrNull();

  Future<PolicyDraftWriteResult> selectConfirmed(
    int profileId, {
    required ProfilePolicySelection? expected,
    required String? draftRaw,
    required String? selectionRaw,
    PolicyMaterialCandidate? material,
  }) async {
    final next = selectionRaw == null
        ? null
        : ProfilePolicySelection(
            profileId: profileId,
            rawContent: selectionRaw,
          );
    final resetPicks = next != null && !next.sameValue(expected);
    if (selectionRaw != null) {
      if (!supportsManaged) {
        throw const RequestUnavailable('managed_policy_android_required');
      }
      if (draftRaw == null) throw const PolicyDraftProblem('draft');
      final selected = SelectedPolicy.decode(selectionRaw);
      if (selected.usesMaterials) {
        final draft = PolicyDraftDocument.decode(draftRaw);
        if (material == null ||
            material.profileId != profileId ||
            !material.qualifies(draft) ||
            !await material.current()) {
          throw const PolicyDraftProblem('materialSource');
        }
        await ref
            .read(setupActionProvider.notifier)
            ._buildMaterialProfile(
              material._inputsWithSelection(
                selectionRaw,
                resetPicks: resetPicks,
              ),
              material._frame,
              (_) {},
            );
      }
      final envelope = jsonDecode(selectionRaw) as Map<String, dynamic>;
      final target = envelope['maintenanceProxyTarget'];
      final expectedRaw = selectPolicyDraft(
        PolicyDraftDocument.decode(draftRaw),
        maintenanceProxyTarget: target == null
            ? null
            : Map<String, String>.from(target as Map),
      );
      if (selectionRaw != expectedRaw) {
        throw const PolicyDraftProblem('selection');
      }
    }
    ConfigFailureObservation? failure;
    var invalidated = false;
    final setup = ref.read(setupActionProvider.notifier);
    late final PolicyDraftWriteResult result;
    try {
      Future<PolicyDraftWriteResult> commit() async {
        if (material != null && !await material.current()) {
          return PolicyDraftWriteResult.conflict;
        }
        Future<PolicyDraftWriteResult> persist() =>
            database.transaction(() async {
              final draft = await database.profilePolicyDraftsDao
                  .query(profileId)
                  .getSingleOrNull();
              if (selectionRaw != null && draft?.rawContent != draftRaw) {
                return PolicyDraftWriteResult.conflict;
              }
              final result = await database.profilePolicySelectionsDao
                  .compareAndWrite(
                    profileId,
                    expected: expected,
                    selection: next,
                    beforeWrite: () async {
                      failure = await setup.captureConfigFailure(requestClient);
                      if (material?.latest == true &&
                          material?._approval != null) {
                        await material!._approval!.invalidate();
                      } else {
                        await requestClient.invalidate('profile:$profileId');
                      }
                      invalidated = true;
                    },
                  );
              if (result == PolicyDraftWriteResult.saved && resetPicks) {
                final profile = (await database.profilesDao.query().get())
                    .getProfile(profileId)!;
                await database.profilesDao.putAll([
                  profile
                      .copyWith(
                        selectedMap: _withoutManagedPicks(profile.selectedMap),
                      )
                      .toCompanion(),
                ]);
              }
              if (result == PolicyDraftWriteResult.saved &&
                  material?.latest == true) {
                if (!invalidated) {
                  failure = await setup.captureConfigFailure(requestClient);
                  if (material?._approval != null) {
                    await material!._approval!.invalidate();
                  } else {
                    await requestClient.invalidate('profile:$profileId');
                  }
                  invalidated = true;
                }
                await ref
                    .read(profilesProvider.notifier)
                    .persistRefresh(
                      material!._inputs.profile.copyWith(
                        subscriptionInfo: material._subscription,
                        lastUpdateDate: DateTime.now(),
                      ),
                      importing: false,
                    );
              }
              return result;
            });
        if (material?.latest == true) {
          return material!._frame.file.replace(
            await appPath.getProfilePath(profileId.toString()),
            () async {
              final written = await persist();
              if (written != PolicyDraftWriteResult.saved) {
                throw const _MaterialSelectionConflict();
              }
              return written;
            },
          );
        }
        return persist();
      }

      result = material?._approval != null
          ? await material!._approval!.commit(
              session: material._session,
              action: commit,
            )
          : material?._session == null
          ? await requestClient.mutate(commit)
          : await material!._session!.commit(commit);
    } on _MaterialSelectionConflict {
      return PolicyDraftWriteResult.conflict;
    } catch (_) {
      final observation = failure;
      if (observation != null) await setup.finishConfigFailure(observation);
      throw const RequestUnavailable('policy_selection_write_failed');
    }
    if (result == PolicyDraftWriteResult.saved) {
      if (material?.latest == true) {
        await ref.read(profilesProvider.notifier).publishRefresh();
      }
      if (ref.read(currentProfileIdProvider) != profileId &&
          selectionRaw != null) {
        await chooseProfile(profileId, confirmLeave: () async => true);
      } else if (ref.read(currentProfileIdProvider) == profileId &&
          ref.read(initProvider)) {
        await ref.read(setupActionProvider.notifier).applyProfile(force: true);
      }
    }
    return result;
  }

  Future<bool> chooseProfile(
    int? profileId, {
    required Future<bool> Function() confirmLeave,
  }) async {
    final previousId = ref.read(currentProfileIdProvider);
    if (previousId == profileId) return true;
    final previous = previousId == null ? null : await load(previousId);
    final next = profileId == null ? null : await load(profileId);
    if (next == null &&
        (previous != null || ref.read(configStateProvider).fact.isManaged) &&
        !await confirmLeave()) {
      return false;
    }
    ConfigFailureObservation? failure;
    final setup = ref.read(setupActionProvider.notifier);
    try {
      return await requestClient.mutate(() async {
        if (ref.read(currentProfileIdProvider) != previousId) return false;
        if (previousId != null && !_same(previous, await load(previousId)) ||
            profileId != null && !_same(next, await load(profileId))) {
          return false;
        }
        if (profileId != null &&
            !(await database.profilesDao.query().get()).any(
              (p) => p.id == profileId,
            )) {
          return false;
        }
        if (previousId != null) {
          failure = await setup.captureConfigFailure(requestClient);
          await requestClient.invalidate('profile:$previousId');
        }
        ref.read(currentProfileIdProvider.notifier).value = profileId;
        return true;
      });
    } catch (_) {
      final observation = failure;
      if (observation != null) await setup.finishConfigFailure(observation);
      throw const RequestUnavailable('policy_selection_write_failed');
    }
  }

  bool _same(ProfilePolicySelection? left, ProfilePolicySelection? right) =>
      left == null ? right == null : left.sameValue(right);
}

class _MaterialSelectionConflict implements Exception {
  const _MaterialSelectionConflict();
}
