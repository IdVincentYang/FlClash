part of 'database.dart';

@DataClassName('RawProfilePolicySelection')
class ProfilePolicySelections extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  TextColumn get rawContent => text().nullable()();

  @override
  Set<Column> get primaryKey => {profileId};
}

@DriftAccessor(tables: [Profiles, ProfilePolicySelections])
class ProfilePolicySelectionsDao extends DatabaseAccessor<Database>
    with _$ProfilePolicySelectionsDaoMixin {
  ProfilePolicySelectionsDao(super.attachedDatabase);

  Selectable<ProfilePolicySelection> query([int? profileId]) {
    final stmt = select(profilePolicySelections);
    if (profileId != null) {
      stmt.where((t) => t.profileId.equals(profileId));
    }
    return stmt.map(
      (row) => ProfilePolicySelection(
        profileId: row.profileId,
        rawContent: row.rawContent,
      ),
    );
  }

  Future<bool> hasSensitiveContent() async {
    final stmt = selectOnly(profilePolicySelections)
      ..addColumns([profilePolicySelections.profileId])
      ..where(profilePolicySelections.rawContent.isNotNull())
      ..limit(1);
    return (await stmt.get()).isNotEmpty;
  }

  Future<PolicyDraftWriteResult> compareAndWrite(
    int profileId, {
    required ProfilePolicySelection? expected,
    required ProfilePolicySelection? selection,
    Future<void> Function()? beforeWrite,
  }) => transaction(() async {
    final profile = await (select(
      profiles,
    )..where((t) => t.id.equals(profileId))).getSingleOrNull();
    if (profile == null) return PolicyDraftWriteResult.missingProfile;
    final current = await query(profileId).getSingleOrNull();
    if (expected == null ? current != null : !expected.sameValue(current)) {
      return PolicyDraftWriteResult.conflict;
    }
    if (selection != null && selection.profileId != profileId) {
      throw const PolicyDraftRestoreException();
    }
    if (selection == null ? current == null : selection.sameValue(current)) {
      return PolicyDraftWriteResult.saved;
    }
    await beforeWrite?.call();
    if (selection == null) {
      await (delete(
        profilePolicySelections,
      )..where((t) => t.profileId.equals(profileId))).go();
    } else {
      await into(profilePolicySelections).insertOnConflictUpdate(
        ProfilePolicySelectionsCompanion.insert(
          profileId: Value(profileId),
          rawContent: Value(selection.rawContent),
        ),
      );
    }
    return PolicyDraftWriteResult.saved;
  });

  void restoreWithBatch(
    Batch batch,
    List<ProfilePolicySelection> selections, {
    required bool isOverride,
  }) {
    if (isOverride) batch.deleteAll(profilePolicySelections);
    batch.insertAllOnConflictUpdate(profilePolicySelections, [
      for (final item in selections)
        ProfilePolicySelectionsCompanion.insert(
          profileId: Value(item.profileId),
          rawContent: Value(item.rawContent),
        ),
    ]);
  }

  Future<void> requireSelections(Iterable<int> profileIds) async {
    final live = await (select(
      profiles,
    )..where((t) => t.id.isIn(profileIds))).get();
    final existing = (await query().get()).map((s) => s.profileId).toSet();
    await batch((b) {
      b.insertAll(profilePolicySelections, [
        for (final profile in live)
          if (!existing.contains(profile.id))
            ProfilePolicySelectionsCompanion.insert(
              profileId: Value(profile.id),
            ),
      ]);
    });
  }
}
