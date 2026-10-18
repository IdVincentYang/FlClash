enum ProfileApplicationOutcome {
  notRequired,
  queued,
  activated,
  installedInactive,
  retained,
  blocked,
  superseded,
  failed,
}

class ProfileRefreshResult {
  const ProfileRefreshResult({
    this.materialSaved = false,
    this.application = ProfileApplicationOutcome.notRequired,
    this.failure,
  });

  final bool materialSaved;
  final ProfileApplicationOutcome application;
  final String? failure;
}
