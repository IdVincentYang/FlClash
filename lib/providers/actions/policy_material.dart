part of '../action.dart';

String _materialIdentity(Profile profile) => profileMaterialIdentity(
  profileId: profile.id,
  type: profile.type.name,
  url: profile.url,
  overwrite: profile.overwriteType.name,
  scriptId: profile.scriptId,
);

class _ManagedMaterialFrame {
  const _ManagedMaterialFrame(
    this.file,
    this.rawSha256,
    this.identity,
    this.script,
    this.scriptPath,
    this.scriptSha256,
    this.profile,
    this.approval,
  );
  final RequestFile file;
  final String rawSha256, identity;
  final String? script, scriptPath, scriptSha256;
  final Profile profile;
  final SourceMaterialApproval? approval;

  static Future<_ManagedMaterialFrame> capture(
    Profile profile,
    SetupState state, {
    String? incomingPath,
    SourceMaterialApproval? approval,
  }) async {
    final path =
        incomingPath ?? await appPath.getProfilePath(profile.id.toString());
    final bytes = await _readMaterialBytes(path);
    if (state.overwriteType == OverwriteType.script &&
        profile.scriptId != null &&
        state.script == null) {
      throw const PolicyDraftProblem('materialSource');
    }
    final scriptPath =
        state.overwriteType == OverwriteType.script && state.script != null
        ? await state.script!.path
        : null;
    final scriptBytes = scriptPath == null
        ? null
        : await _readMaterialBytes(scriptPath);
    String? script;
    try {
      script = scriptBytes == null ? null : utf8.decode(scriptBytes);
    } on FormatException {
      throw const PolicyDraftProblem('materialScript');
    }
    return _ManagedMaterialFrame(
      await RequestFile.stage(bytes),
      sha256.convert(bytes).toString(),
      _materialIdentity(profile),
      script,
      scriptPath,
      scriptBytes == null ? null : sha256.convert(scriptBytes).toString(),
      profile,
      approval,
    );
  }

  Future<_ManagedMaterialFrame> incoming(
    String path, {
    SourceMaterialApproval? approval,
  }) async {
    final bytes = await _readMaterialBytes(path);
    return _ManagedMaterialFrame(
      await RequestFile.stage(bytes),
      sha256.convert(bytes).toString(),
      identity,
      script,
      scriptPath,
      scriptSha256,
      profile,
      approval,
    );
  }

  Future<bool> scriptCurrent() async =>
      scriptPath == null ||
      await _boundedFileDigest(scriptPath!) == scriptSha256;

  Future<SelectedPolicy> resolve(
    CoreController core,
    SetupState state,
    SelectedPolicy selected, {
    required Request requests,
    SourceConfirmation? confirm,
    bool automatic = false,
    Future<bool> Function()? isCurrent,
    void Function(Map<String, Object?>)? onSourceUse,
  }) async {
    final material = await read(
      core,
      state,
      requests: requests,
      confirm: confirm,
      automatic: automatic,
      isCurrent: isCurrent,
      onSourceUse: onSourceUse,
    );
    return selected.resolve(
      material: material,
      identity: identity,
      profileId: state.profileId!,
      rawSha256: rawSha256,
    );
  }

  Future<Map<String, dynamic>> read(
    CoreController core,
    SetupState state, {
    required Request requests,
    SourceConfirmation? confirm,
    bool automatic = false,
    Future<bool> Function()? isCurrent,
    void Function(Map<String, Object?>)? onSourceUse,
  }) async {
    validateMaterialDocument(await _readMaterialBytes(file.staged.path));
    final sourceBody = requests.requiresSourceAcceptance
        ? await _sourceBody(file.staged.path, preserveBom: true)
        : null;
    final source = await requests.captureSource('profile:${profile.id}');
    if (approval != null && approval!.materialHash != rawSha256) {
      throw const PolicyDraftProblem('materialSource');
    }
    final acceptedSource = approval == null
        ? await _reviewProfileSource(
            confirm: confirm,
            core: core,
            requests: requests,
            profile: profile,
            path: file.staged.path,
            body: sourceBody,
            source: source,
            automatic: automatic,
            isCurrent: isCurrent,
          )
        : null;
    if (acceptedSource != null) onSourceUse?.call(acceptedSource.use);
    late Map<String, dynamic> material;
    try {
      material = boundedMaterialCopy(
        approval != null
            ? await approval!.project()
            : requests.requiresSourceAcceptance
            ? await _sourceAcceptance(core, requests, confirm: confirm).project(
                source: source,
                identity: _profileSourceIdentity(profile),
                body: sourceBody!,
              )
            : await core.getConfigPath(file.staged.path),
      );
    } catch (_) {
      throw const PolicyDraftProblem('material');
    }
    if (script?.isNotEmpty == true) {
      try {
        final accepted = await _reviewScriptSource(
          confirm: confirm,
          core: core,
          requests: requests,
          script: state.script!,
          body: script!,
          isCurrent: () async =>
              await scriptCurrent() && (isCurrent == null || await isCurrent()),
          automatic: automatic,
        );
        if (accepted != null) onSourceUse?.call(accepted.use);
        if (isCurrent != null && !await isCurrent()) {
          throw const RequestUnavailable('request_cancelled');
        }
        material = boundedMaterialCopy(
          requests.requiresSourceAcceptance
              ? await handleAcceptedEvaluate(
                  script!,
                  material,
                  permit: accepted?.scriptPermit,
                  maxBytes: managedMaterialMaxBytes,
                )
              : await handleEvaluate(
                  script!,
                  material,
                  maxBytes: managedMaterialMaxBytes,
                ),
        );
      } catch (_) {
        throw const PolicyDraftProblem('materialScript');
      }
    }
    if (state.overwriteType == OverwriteType.custom) {
      if (state.customProxies.isNotEmpty) {
        material['proxies'] = state.customProxies
            .map((p) => p.definition)
            .toList();
      }
      if (state.proxyGroups.isNotEmpty) {
        material['proxy-groups'] = state.proxyGroups
            .map((g) => g.definition)
            .toList();
      }
    }
    return material;
  }
}

class PolicyMaterialCandidate {
  PolicyMaterialCandidate._(
    this._inputs,
    this._frame,
    this._sources,
    this._client,
    this._core,
    this._originalSha256,
    this._selectionRaw,
    this._confirmation,
  );
  final _SetupInputs _inputs;
  _ManagedMaterialFrame _frame;
  final List<RequestSource> _sources;
  final Request _client;
  final CoreController _core;
  final String _originalSha256;
  final String? _selectionRaw;
  final SourceConfirmation _confirmation;
  RequestSession? _session;
  SourceMaterialApproval? _approval;
  SubscriptionInfo? _subscription;
  bool _closed = false;
  ({String draftSha256, _ManagedMaterialFrame frame})? _qualified;
  int _previewRevision = 0;
  Future<Map<String, dynamic>>? _material;
  bool get latest => _session != null;
  int get profileId => _inputs.profile.id;
  String get identity => _frame.identity;

  Future<bool> current({bool beginning = false}) async {
    if (_closed || _session != null && !_session!.isActive) return false;
    for (final source in _sources) {
      if (beginning && source.key == 'profile:$profileId') continue;
      if (!await _client.configSourceCurrent(source)) return false;
    }
    final profile = (await database.profilesDao.query().get()).getProfile(
      profileId,
    );
    final selection = await database.profilePolicySelectionsDao
        .query(profileId)
        .getSingleOrNull();
    if (profile == null ||
        _materialIdentity(profile) != identity ||
        selection?.rawContent != _selectionRaw) {
      return false;
    }
    final path = await appPath.getProfilePath(profileId.toString());
    try {
      final digest = await _boundedFileDigest(path);
      return !_closed &&
          digest == _originalSha256 &&
          await _frame.scriptCurrent();
    } on FileSystemException {
      return false;
    } on PolicyDraftProblem {
      return false;
    }
  }

  Future<PolicyDraftPreview> preview(PolicyDraftDocument draft) async {
    final raw = draft.encode();
    final frozen = PolicyDraftDocument.decode(raw);
    final frame = _frame;
    final revision = ++_previewRevision;
    _qualified = null;
    bool owned() =>
        !_closed && revision == _previewRevision && identical(frame, _frame);
    try {
      if (!await current() || !owned()) {
        throw const PolicyDraftProblem('materialSource');
      }
      final material = await (_material ??= frame.read(
        _core,
        _inputs.state,
        requests: _client,
        confirm: _confirmation,
        isCurrent: current,
      ));
      if (!owned()) throw const PolicyDraftProblem('materialSource');
      final resolved = resolveMaterialPolicy(
        frozen.policy,
        material: material,
        identity: identity,
        profileId: profileId,
        rawSha256: frame.rawSha256,
      );
      final result = previewPolicyDraft(frozen, material: resolved);
      if (!await current() || !owned() || draft.encode() != raw) {
        throw const PolicyDraftProblem('materialSource');
      }
      _qualified = (draftSha256: materialDigest(raw), frame: frame);
      return result;
    } on PolicyDraftProblem {
      rethrow;
    } catch (_) {
      throw const PolicyDraftProblem('material');
    }
  }

  Future<Map<String, List<String>>> sourceNames() async {
    if (!await current()) throw const PolicyDraftProblem('materialSource');
    final frame = _frame;
    final material = await (_material ??= frame.read(
      _core,
      _inputs.state,
      requests: _client,
      confirm: _confirmation,
      isCurrent: current,
    ));
    if (!identical(frame, _frame) || !await current()) {
      throw const PolicyDraftProblem('materialSource');
    }
    List<String> names(String key) => material[key] is List
        ? [
            for (final entry in material[key] as List)
              if (entry is Map && entry['name'] is String)
                entry['name'] as String,
          ]
        : [];
    final providers = material['rule-providers'];
    final collections = providers is Map ? providers : const {};
    return {
      'proxies': names('proxies'),
      'groups': names('proxy-groups'),
      'domain': [
        for (final entry in collections.entries)
          if (entry.key is String) entry.key as String,
      ],
      'ip': [
        for (final entry in collections.entries)
          if (entry.key is String) entry.key as String,
      ],
    };
  }

  bool qualifies(PolicyDraftDocument draft) =>
      !_closed &&
      identical(_qualified?.frame, _frame) &&
      _qualified?.draftSha256 == materialDigest(draft.encode());

  _SetupInputs _inputsWithSelection(String raw, {bool resetPicks = false}) =>
      _SetupInputs(
        applicationRouting: _inputs.applicationRouting,
        state: _inputs.state.copyWith(
          policySelection: ProfilePolicySelection(
            profileId: profileId,
            rawContent: raw,
          ),
        ),
        profile: resetPicks
            ? _inputs.profile.copyWith(
                selectedMap: _withoutManagedPicks(_inputs.profile.selectedMap),
              )
            : _inputs.profile,
        patch: _inputs.patch,
        network: _inputs.network,
        overrideDns: _inputs.overrideDns,
        overrideNtp: _inputs.overrideNtp,
        safeMode: _inputs.safeMode,
        testUrl: _inputs.testUrl,
        picks: _inputs.picks,
        shared: _inputs.shared,
        vpn: _inputs.vpn,
        fact: _inputs.fact,
        policy: SelectedPolicy.decode(raw),
      );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _session?.close();
    await _approval?.release();
    await _frame.file.close();
  }
}

Future<String> _boundedFileDigest(String path) async =>
    sha256.convert(await _readMaterialBytes(path)).toString();

Future<List<int>> _readMaterialBytes(String path) async {
  final bytes = <int>[];
  await for (final chunk in File(path).openRead()) {
    if (bytes.length + chunk.length > managedMaterialMaxBytes) {
      throw const PolicyDraftProblem('materialBudget');
    }
    bytes.addAll(chunk);
  }
  return bytes;
}

mixin _PolicyMaterialSetup on _$SetupAction {
  CoreController get _core;
  Request get _requests;
  PatchClashConfig _effectivePatchConfig(PatchClashConfig patchConfig);

  Future<PolicyMaterialCandidate> capturePolicyMaterial(
    int profileId, {
    bool latest = false,
    void Function(PolicyMaterialCandidate)? onCreated,
    String? incomingPath,
    Request? client,
    SourceMaterialApproval? approval,
  }) async {
    final requests = client ?? _requests;
    final candidate = await requests.mutate(() async {
      final profile = (await database.profilesDao.query().get()).getProfile(
        profileId,
      );
      if (profile == null) throw const PolicyDraftProblem('materialSource');
      ref.invalidate(setupStateProvider(profileId));
      final state = await ref.read(setupStateProvider(profileId).future);
      final selected = state.policySelection;
      SelectedPolicy? policy;
      try {
        if (selected != null) {
          policy = SelectedPolicy.decode(selected.rawContent);
        }
      } on PolicyDraftProblem {
        policy = null;
      }
      final frame = await _ManagedMaterialFrame.capture(
        profile,
        state,
        incomingPath: incomingPath,
        approval: approval,
      );
      try {
        final keys = <String>{
          'profile:$profileId',
          'application-config',
          if (state.overwriteType == OverwriteType.script &&
              state.script != null)
            'script:${state.script!.id}',
        };
        final sources = <RequestSource>[];
        for (final key in keys) {
          sources.add(await requests.captureSource(key));
        }
        final inputs = _SetupInputs(
          applicationRouting: await database.readApplicationRouting(),
          state: state,
          profile: profile,
          patch: _effectivePatchConfig(ref.read(patchClashConfigProvider)),
          network: ref.read(networkSettingProvider),
          overrideDns: ref.read(overrideDnsProvider),
          overrideNtp: ref.read(overrideNtpProvider),
          safeMode: ref.read(safeModeProvider),
          testUrl: ref.read(appSettingProvider).testUrl,
          picks: const {},
          shared: ref.read(sharedStateProvider),
          vpn: ref.read(vpnStateProvider),
          fact: await _core.getConfigState(),
          policy: policy,
        );
        return PolicyMaterialCandidate._(
          inputs,
          frame,
          sources,
          requests,
          _core,
          incomingPath == null
              ? frame.rawSha256
              : await _boundedFileDigest(
                  await appPath.getProfilePath(profileId.toString()),
                ),
          selected?.rawContent,
          ref.read(sourceConfirmationProvider),
        );
      } catch (_) {
        await frame.file.close();
        rethrow;
      }
    });
    onCreated?.call(candidate);
    if (candidate._closed) throw const PolicyDraftProblem('materialSource');
    if (!latest) return candidate;
    try {
      final profile = candidate._inputs.profile;
      if (profile.type != ProfileType.url) {
        throw const PolicyDraftProblem('materialSource');
      }
      final session = await requests.begin(
        key: 'profile:$profileId',
        url: profile.url,
        mode: profile.requestMode,
        proxy: profile.requestProxy,
        label: profile.realLabel,
        expectedSource: candidate._sources.first,
        sourceIsCurrent: () => candidate.current(beginning: true),
      );
      candidate._session = session;
      await requests.mutate(() async {
        final previous = candidate._sources.first;
        final current = await requests.captureSource(previous.key);
        if (current.revision != previous.revision + 1 ||
            current.dataset != previous.dataset ||
            current.client != previous.client ||
            current.snapshot['dataset'] != previous.snapshot['dataset'] ||
            current.snapshot['sourceRevision'] !=
                previous.snapshot['sourceRevision'] ||
            !await candidate.current(beginning: true)) {
          throw const PolicyDraftProblem('materialSource');
        }
        candidate._sources[0] = current;
      });
      final response = await session.run(
        () => requests.downloadFileForUrl(profile.url),
      );
      try {
        if (!await candidate.current()) {
          throw const PolicyDraftProblem('materialSource');
        }
        final approval = await _reviewProfileMaterial(
          core: _core,
          requests: requests,
          profile: profile,
          path: response.file.staged.path,
          session: session,
          isCurrent: candidate.current,
          confirm: ref.read(sourceConfirmationProvider),
        );
        candidate._approval = approval;
        final frame = await candidate._frame.incoming(
          response.file.staged.path,
          approval: approval,
        );
        await candidate._frame.file.close();
        candidate._frame = frame;
        candidate._material = null;
        candidate._qualified = null;
        candidate._previewRevision++;
        candidate._subscription = SubscriptionInfo.fromHeaderValues(
          response.headers['subscription-userinfo'],
        );
      } finally {
        await response.file.close();
      }
      return candidate;
    } catch (_) {
      await candidate.close();
      rethrow;
    }
  }

  Future<PolicyMaterialCandidate?> preflightPolicyMaterial(
    int profileId,
    String incomingPath,
    Request client, {
    SourceMaterialApproval? approval,
    SourceConfirmation? confirm,
  }) async {
    final selected = await database.profilePolicySelectionsDao
        .query(profileId)
        .getSingleOrNull();
    if (selected == null ||
        !SelectedPolicy.decode(selected.rawContent).usesMaterials) {
      return null;
    }
    final candidate = await capturePolicyMaterial(
      profileId,
      incomingPath: incomingPath,
      client: client,
      approval: approval,
    );
    try {
      await _buildMaterialProfile(
        candidate._inputs,
        candidate._frame,
        (_) {},
        confirm: confirm,
      );
      if (!await candidate.current()) {
        throw const PolicyDraftProblem('materialSource');
      }
      return candidate;
    } catch (_) {
      await candidate.close();
      rethrow;
    }
  }

  Future<({String yaml, String md5})> _buildMaterialProfile(
    _SetupInputs snapshot,
    _ManagedMaterialFrame frame,
    void Function(SelectedPolicy) resolved, {
    void Function(Map<String, Object?>)? onSourceUse,
    void Function(Map<String, Object?>)? onRuleLedger,
    bool allowSourceReview = true,
    SourceConfirmation? confirm,
    Future<bool> Function()? isCurrent,
  }) async {
    final selected = await frame.resolve(
      _core,
      snapshot.state,
      snapshot.policy!,
      requests: _requests,
      confirm: confirm ?? ref.read(sourceConfirmationProvider),
      automatic: !allowSourceReview || !ref.read(appVisibleProvider),
      onSourceUse: onSourceUse,
      isCurrent: isCurrent,
    );
    selected.picks(snapshot.profile.selectedMap);
    resolved(selected);
    return _composeManagedSubscription(
      state: snapshot.state,
      patch: snapshot.patch,
      selected: selected,
      network: snapshot.network,
      overrideDns: snapshot.overrideDns,
      overrideNtp: snapshot.overrideNtp,
      safeMode: snapshot.safeMode,
      onRuleLedger: onRuleLedger,
    );
  }

  Future<({String yaml, String md5})> _composeManagedSubscription({
    required SetupState state,
    required PatchClashConfig patch,
    required SelectedPolicy selected,
    NetworkProps? network,
    bool? overrideDns,
    bool? overrideNtp,
    bool? safeMode,
    void Function(Map<String, Object?>)? onRuleLedger,
  }) async {
    final NetworkProps networkSetting =
        network ?? ref.read<NetworkProps>(networkSettingProvider);
    final composition = await makeProfileCompositionTask(
      MakeRealProfileState(
        rules: const [],
        proxyGroups: const [],
        addedRules: const [],
        profilesPath: await appPath.profilesPath,
        profileId: state.profileId!,
        rawConfig: const {},
        realPatchConfig: patch.copyWith(
          tun: patch.tun.getRealTun(networkSetting.routeMode),
        ),
        overrideDns: overrideDns ?? ref.read(overrideDnsProvider),
        overrideNtp: overrideNtp ?? ref.read(overrideNtpProvider),
        appendSystemDns: networkSetting.appendSystemDns,
        defaultUA: globalState.packageInfo.ua,
        authentication: networkSetting.authentication.credentials,
        matchTarget: state.matchTarget,
        safeMode: safeMode ?? ref.read(safeModeProvider),
        policySelection: state.policySelection,
        resolvedManagedPolicy: selected.policyJson,
      ),
    );
    onRuleLedger?.call(composition.ledger);
    return (yaml: composition.yaml, md5: composition.md5);
  }
}
