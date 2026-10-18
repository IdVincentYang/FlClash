part of '../action.dart';

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
  }) async {
    if (selectionRaw != null) {
      if (!supportsManaged) {
        throw const RequestUnavailable('managed_policy_android_required');
      }
      if (draftRaw == null) throw const PolicyDraftProblem('draft');
      SelectedPolicy.decode(selectionRaw);
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
    final setup = ref.read(setupActionProvider.notifier);
    late final PolicyDraftWriteResult result;
    try {
      result = await requestClient.mutate(
        () => database.transaction(() async {
          final draft = await database.profilePolicyDraftsDao
              .query(profileId)
              .getSingleOrNull();
          if (selectionRaw != null && draft?.rawContent != draftRaw) {
            return PolicyDraftWriteResult.conflict;
          }
          final next = selectionRaw == null
              ? null
              : ProfilePolicySelection(
                  profileId: profileId,
                  rawContent: selectionRaw,
                );
          final result = await database.profilePolicySelectionsDao
              .compareAndWrite(
                profileId,
                expected: expected,
                selection: next,
                beforeWrite: () async {
                  failure = await setup.captureConfigFailure(requestClient);
                  await requestClient.invalidate('profile:$profileId');
                },
              );
          if (result == PolicyDraftWriteResult.saved &&
              selectionRaw != null &&
              !(next?.sameValue(expected) ?? false)) {
            final profile = (await database.profilesDao.query().get())
                .getProfile(profileId)!;
            await database.profilesDao.putAll([
              profile
                  .copyWith(
                    selectedMap: {
                      for (final item in profile.selectedMap.entries)
                        if (!item.key.startsWith('fc-managed-group-'))
                          item.key: item.value,
                    },
                  )
                  .toCompanion(),
            ]);
          }
          return result;
        }),
      );
    } catch (_) {
      final observation = failure;
      if (observation != null) await setup.finishConfigFailure(observation);
      throw const RequestUnavailable('policy_selection_write_failed');
    }
    if (result == PolicyDraftWriteResult.saved) {
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
