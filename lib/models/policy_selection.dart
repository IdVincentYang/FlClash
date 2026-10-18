final class ProfilePolicySelection {
  final int profileId;
  final String? rawContent;

  const ProfilePolicySelection({required this.profileId, this.rawContent});

  bool sameValue(ProfilePolicySelection? other) =>
      other != null &&
      profileId == other.profileId &&
      rawContent == other.rawContent;

  @override
  String toString() =>
      'ProfilePolicySelection(profileId: $profileId, redacted)';
}

bool validPolicySelectionRelations(
  Iterable<ProfilePolicySelection> selections,
  Iterable<int> profileIds,
) {
  final profiles = profileIds.toSet();
  final seen = <int>{};
  return selections.every(
    (item) => profiles.contains(item.profileId) && seen.add(item.profileId),
  );
}
