part of 'database.dart';

@DataClassName('RawProfilePolicyDraft')
class ProfilePolicyDrafts extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  TextColumn get rawContent => text()();

  @override
  Set<Column> get primaryKey => {profileId};
}

@DriftAccessor(tables: [Profiles, ProfilePolicyDrafts])
class ProfilePolicyDraftsDao extends DatabaseAccessor<Database>
    with _$ProfilePolicyDraftsDaoMixin {
  ProfilePolicyDraftsDao(super.attachedDatabase);

  Selectable<ProfilePolicyDraft> query([int? profileId]) {
    final stmt = select(profilePolicyDrafts);
    if (profileId != null) {
      stmt.where((t) => t.profileId.equals(profileId));
    }
    stmt.orderBy([(t) => OrderingTerm.asc(t.profileId)]);
    return stmt.map(
      (row) => ProfilePolicyDraft(
        profileId: row.profileId,
        rawContent: row.rawContent,
      ),
    );
  }

  Future<bool> hasAny() async {
    final stmt = selectOnly(profilePolicyDrafts)
      ..addColumns([profilePolicyDrafts.profileId])
      ..limit(1);
    return (await stmt.get()).isNotEmpty;
  }

  Future<PolicyDraftWriteResult> compareAndWrite(
    int profileId, {
    required String? expectedRaw,
    required String? rawContent,
  }) {
    return transaction(() async {
      final profile = await (select(
        profiles,
      )..where((t) => t.id.equals(profileId))).getSingleOrNull();
      if (profile == null) return PolicyDraftWriteResult.missingProfile;
      final current = await query(profileId).getSingleOrNull();
      if (current?.rawContent != expectedRaw) {
        return PolicyDraftWriteResult.conflict;
      }
      if (rawContent == null) {
        await (delete(
          profilePolicyDrafts,
        )..where((t) => t.profileId.equals(profileId))).go();
      } else {
        await into(profilePolicyDrafts).insertOnConflictUpdate(
          ProfilePolicyDraftsCompanion.insert(
            profileId: Value(profileId),
            rawContent: rawContent,
          ),
        );
      }
      return PolicyDraftWriteResult.saved;
    });
  }

  void restoreWithBatch(
    Batch batch,
    List<ProfilePolicyDraft> drafts, {
    required bool isOverride,
  }) {
    if (isOverride) batch.deleteAll(profilePolicyDrafts);
    batch.insertAllOnConflictUpdate(profilePolicyDrafts, [
      for (final draft in drafts)
        ProfilePolicyDraftsCompanion.insert(
          profileId: Value(draft.profileId),
          rawContent: draft.rawContent,
        ),
    ]);
  }
}
