part of '../action.dart';

@Riverpod(keepAlive: true)
class PolicyDraftAction extends _$PolicyDraftAction {
  @override
  void build() {}

  Future<ProfilePolicyDraft?> load(int profileId) =>
      database.profilePolicyDraftsDao.query(profileId).getSingleOrNull();

  Future<PolicyDraftWriteResult> save(
    int profileId, {
    required String? expectedRaw,
    required String? rawContent,
  }) async {
    try {
      return await database.profilePolicyDraftsDao.compareAndWrite(
        profileId,
        expectedRaw: expectedRaw,
        rawContent: rawContent,
      );
    } catch (_) {
      return PolicyDraftWriteResult.failed;
    }
  }

  Future<PolicyDraftDocument> extract(int profileId) =>
      captureProfilePolicyDraft(
        profileId,
        applicationSettings: () => {
          'patch': ref.read(patchClashConfigProvider).toJson(),
          'overrideDns': ref.read(overrideDnsProvider),
        },
      );
}
