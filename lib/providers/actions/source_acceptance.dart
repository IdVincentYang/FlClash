part of '../action.dart';

Future<SourceReviewDecision?> _confirmSourceReview(SourceReview review) =>
    dialogs.showCommonDialog<SourceReviewDecision>(
      child: SourceReviewDialog(review: review),
    );

final sourceConfirmationProvider = Provider<SourceConfirmation>(
  (ref) => _confirmSourceReview,
);

SourceAcceptance _sourceAcceptance(
  CoreController core,
  Request requests, {
  SourceConfirmation? confirm,
}) => SourceAcceptance(
  core: core,
  requests: requests,
  confirm: confirm ?? _confirmSourceReview,
);

Future<String> _sourceBody(String path, {bool preserveBom = false}) async {
  final buffered = BytesBuilder(copy: false);
  await for (final chunk in File(path).openRead()) {
    if (buffered.length + chunk.length > 16 * 1024 * 1024) {
      throw const RequestUnavailable('profile_download_too_large');
    }
    buffered.add(chunk);
  }
  try {
    final bytes = buffered.takeBytes();
    final text = utf8.decode(bytes);
    return preserveBom &&
            bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? '\uFEFF$text'
        : text;
  } on FormatException {
    throw const RequestUnavailable('profile_invalid');
  }
}

String _profileSourceIdentity(Profile profile) => SourceAcceptance.fingerprint({
  'kind': 'profile',
  'id': profile.id,
  'url': profile.url,
  'type': profile.type.name,
});

String _scriptSourceIdentity(Script script) => SourceAcceptance.fingerprint({
  'kind': 'script',
  'id': script.id,
  'url': script.url,
});

Map<String, Object?> _profileSourceSettings(Profile profile) => {
  'overwrite': profile.overwriteType.name,
  'script': profile.scriptId,
  'unmatched': profile.matchTarget,
  'requestMode': profile.requestMode.name,
  'requestProxy': profile.requestProxy,
};

Future<SourceMaterialApproval?> _reviewProfileMaterial({
  required CoreController core,
  required Request requests,
  required Profile profile,
  required String path,
  RequestSource? source,
  RequestSession? session,
  bool automatic = false,
  bool fresh = false,
  String kind = 'profile',
  Future<bool> Function()? isCurrent,
  SourceConfirmation? confirm,
}) async {
  if (!requests.requiresSourceAcceptance) return null;
  return _sourceAcceptance(core, requests, confirm: confirm).reviewMaterial(
    source: source ?? await requests.captureSource('profile:${profile.id}'),
    identity: _profileSourceIdentity(profile),
    settings: _profileSourceSettings(profile),
    body: await _sourceBody(path, preserveBom: true),
    label: profile.realLabel,
    location: profile.url,
    kind: kind,
    session: session,
    automatic: automatic,
    fresh: fresh,
    isCurrent: isCurrent,
  );
}

Future<SourceMaterialApproval?> _reviewScriptMaterial({
  required CoreController core,
  required Request requests,
  required Script script,
  required String body,
  RequestSession? session,
  Future<bool> Function()? isCurrent,
  SourceConfirmation? confirm,
}) async {
  if (!requests.requiresSourceAcceptance) return null;
  return _sourceAcceptance(core, requests, confirm: confirm).reviewMaterial(
    source: await requests.captureSource('script:${script.id}'),
    identity: _scriptSourceIdentity(script),
    settings: {
      'requestMode': script.requestMode.name,
      'requestProxy': script.requestProxy,
    },
    body: body,
    label: script.label,
    location: script.url ?? '',
    kind: 'script',
    session: session,
    isCurrent: isCurrent,
  );
}

String _clashProviderSourceIdentity(ClashProvider provider) =>
    SourceAcceptance.fingerprint({
      'kind': provider.kind.name,
      'id': provider.id,
      'url': provider.url,
      'format': provider.format?.name,
      'behavior': provider.behavior?.name,
    });

Future<AcceptedSourceRevision?> _reviewProfileSource({
  required CoreController core,
  required Request requests,
  required Profile profile,
  required String path,
  String? body,
  RequestSource? source,
  bool automatic = false,
  bool forceReview = false,
  bool fresh = false,
  String kind = 'profile',
  Future<bool> Function()? isCurrent,
  SourceConfirmation? confirm,
}) async {
  if (!requests.requiresSourceAcceptance) return null;
  final accepted = await _sourceAcceptance(core, requests, confirm: confirm)
      .review(
        source: source ?? await requests.captureSource('profile:${profile.id}'),
        identity: _profileSourceIdentity(profile),
        settings: _profileSourceSettings(profile),
        body: body ?? await _sourceBody(path, preserveBom: true),
        label: profile.realLabel,
        location: profile.url,
        kind: kind,
        automatic: automatic,
        forceReview: forceReview,
        fresh: fresh,
        isCurrent: isCurrent,
      );
  await accepted.release();
  return accepted;
}

Future<AcceptedSourceRevision?> _reviewScriptSource({
  required CoreController core,
  required Request requests,
  required Script script,
  required String body,
  RequestSource? source,
  bool automatic = false,
  bool forceReview = false,
  Future<bool> Function()? isCurrent,
  SourceConfirmation? confirm,
}) async {
  if (!requests.requiresSourceAcceptance) return null;
  final accepted = await _sourceAcceptance(core, requests, confirm: confirm)
      .review(
        source: source ?? await requests.captureSource('script:${script.id}'),
        identity: _scriptSourceIdentity(script),
        settings: {
          'requestMode': script.requestMode.name,
          'requestProxy': script.requestProxy,
        },
        body: body,
        label: script.label,
        location: script.url ?? '',
        kind: 'script',
        automatic: automatic,
        forceReview: forceReview,
        isCurrent: isCurrent,
      );
  await accepted.release();
  return accepted;
}

Future<List<Map<String, Object?>>> _sourceRecoveryRows() async {
  final rows = <Map<String, Object?>>[
    for (final profile in await database.profilesDao.query().get())
      {
        'key': 'profile:${profile.id}',
        'identity': _profileSourceIdentity(profile),
      },
    for (final script in await database.scriptsDao.query().get())
      {'key': 'script:${script.id}', 'identity': _scriptSourceIdentity(script)},
  ];
  rows.sort((a, b) => (a['key'] as String).compareTo(b['key'] as String));
  return rows;
}

Future<Map<String, Object?>?> _recoverSourceMaterialCommit(
  CoreController core,
  Request requests,
) async {
  final acceptance = _sourceAcceptance(core, requests);
  final source = await requests.captureSource('application-config');
  await acceptance.inspectMaterialRecovery(source: source, rows: const []);
  final rows = await dataMutations.run(_sourceRecoveryRows);
  final snapshot = await acceptance.inspectMaterialRecovery(
    source: source,
    rows: rows,
  );
  final run = await requests.captureNativeRunState();
  final l10n = currentAppLocalizations;
  final confirmed = await dialogs.showMessage(
    title: l10n.sourceRecoveryTitle,
    message: TextSpan(text: l10n.sourceRecoveryDescription),
  );
  if (confirmed != true) return null;
  await dataMutations.run(() async {
    if (jsonEncode(await _sourceRecoveryRows()) != jsonEncode(rows)) {
      throw const RequestUnavailable('request_cancelled');
    }
    await acceptance.recoverMaterialCommit(source: source, snapshot: snapshot);
  });
  final currentRun = await requests.captureNativeRunState();
  return run != null && currentRun != null && _sameSetupRun(run, currentRun)
      ? run
      : null;
}
