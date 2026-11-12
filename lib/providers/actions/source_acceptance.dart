part of '../action.dart';

Future<SourceReviewDecision?> _showSourceReview(Ref ref, Widget child) async {
  if (!ref.mounted || !ref.read(appVisibleProvider)) {
    throw const RequestUnavailable('source_review_required');
  }
  ModalRoute<dynamic>? route;
  var interrupted = false;
  final visibility = ref.listen<bool>(appVisibleProvider, (_, visible) {
    if (visible) return;
    interrupted = true;
    final active = route;
    active?.navigator?.removeRoute(active);
  });
  try {
    final decision = await dialogs.showCommonDialog<SourceReviewDecision>(
      child: Builder(
        builder: (context) {
          route = ModalRoute.of(context);
          if (interrupted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final active = route;
              active?.navigator?.removeRoute(active);
            });
          }
          return child;
        },
      ),
    );
    if (interrupted || !ref.mounted || !ref.read(appVisibleProvider)) {
      return null;
    }
    return decision;
  } finally {
    visibility.close();
  }
}

Future<void> _prepareSourceReview(
  Ref ref,
  String label,
  Future<void> Function(SourceConfirmation confirm, bool Function() current)
  work,
) async {
  final response = Completer<SourceReviewDecision?>();
  late ValueNotifier<Widget> surface;
  Future<void>? operation;
  Object? failure;
  StackTrace? failureStack;
  ModalRoute<dynamic>? route;
  var closed = false;
  var accepted = false;
  var running = false;
  var presented = false;
  late Widget Function() status;
  Future<void> run() async {
    if (closed || running) return;
    running = true;
    failure = null;
    surface.value = status();
    try {
      await work(
        (review) => confirmSourceReview(
          ref,
          review,
          present: (child) {
            if (closed) return Future.value(null);
            presented = true;
            surface.value = child;
            return response.future;
          },
        ),
        () => !closed || accepted,
      );
      if (!closed && !presented) route?.navigator?.removeRoute(route!);
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      running = false;
      if (!closed && !presented) surface.value = status();
    }
  }

  status = () => Builder(
    builder: (context) => CommonDialog(
      title: context.appLocalizations.sourceSubscriptionReview,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appLocalizations.cancel),
        ),
        if (failure != null)
          TextButton(
            onPressed: () {
              surface.value = status();
              operation = run();
            },
            child: Text(context.appLocalizations.retry),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 12),
          if (failure == null) ...[
            Text(context.appLocalizations.sourceLoadChecking),
            const LinearProgressIndicator(),
          ] else
            Text(userFacingErrorMessage(failure!, context.appLocalizations)),
        ],
      ),
    ),
  );
  surface = ValueNotifier(status());
  try {
    final decision = await _showSourceReview(
      ref,
      ValueListenableBuilder<Widget>(
        valueListenable: surface,
        builder: (context, child, _) {
          route = ModalRoute.of(context);
          if (operation == null && !closed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!closed && operation == null) operation = run();
            });
          }
          return child;
        },
      ),
    );
    closed = true;
    accepted = decision != null;
    response.complete(decision);
    if (accepted || presented) {
      await operation;
      if (accepted && failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
    }
  } finally {
    closed = true;
    if (!response.isCompleted) response.complete(null);
    surface.dispose();
  }
}

@visibleForTesting
Future<SourceReviewDecision?> confirmSourceReview(
  Ref ref,
  SourceReview review, {
  Future<SourceReviewDecision?> Function(Widget child)? present,
  SourceReviewPresentation? presentation,
  bool importing = false,
  bool loadedNodesSnapshot = false,
}) async {
  final show =
      presentation?.present ??
      present ??
      (Widget child) => _showSourceReview(ref, child);
  final source = review.source;
  if (source == null || review.kind == 'script') {
    return show(
      SourceReviewDialog(review: review, onDecision: presentation?.onDecision),
    );
  }
  final store = SourceReviewBatchStore.forRequests(source.owner);
  final cached = store.decision(review);
  if (cached != null) return cached;
  if (!ref.mounted || !ref.read(appVisibleProvider)) {
    throw const RequestUnavailable('source_review_required');
  }
  if (!review.forceReview &&
      review.kind != 'profile' &&
      store.hasPending(source.client)) {
    throw const RequestUnavailable('source_review_required');
  }
  var root = review;
  final isComposition =
      review.kind == 'config' ||
      review.subscriptionKey?.startsWith('profile:') == true;
  if (isComposition) {
    final id = int.tryParse(
      review.kind == 'config'
          ? review.key.replaceFirst('config:', '')
          : review.subscriptionKey!.substring('profile:'.length),
    );
    final profile = (await database.profilesDao.query().get()).getProfile(id);
    if (profile == null) throw const RequestUnavailable('request_cancelled');
    final rootSource = await source.owner.captureSource(
      'profile:${profile.id}',
    );
    final body = await _sourceBody(
      await appPath.getProfilePath(profile.id.toString()),
      preserveBom: true,
    );
    final core = ref.read(coreHandlerProvider);
    final inspected = await core.sourceAcceptance({
      'action': 'inspect',
      'key': rootSource.key,
      'kind': 'profile',
      'source': {
        'client': rootSource.client ?? '',
        'dataset': rootSource.snapshot['dataset'] ?? 0,
        'sources': {rootSource.key: rootSource.snapshot['sourceRevision'] ?? 0},
      },
    });
    final routing =
        (inspected['grant'] as Map?)?['routing'] as String? ?? 'source';
    final description =
        await SourceAcceptance(core: core, requests: source.owner).preview(
          source: rootSource,
          kind: 'profile',
          body: body,
          routing: routing,
        );
    final settings = _profileSourceSettings(profile);
    root = SourceReview(
      label: profile.realLabel,
      origin: SourceAcceptance.displayOrigin(profile.url),
      kind: 'profile',
      reasons: review.reasons,
      routing: routing,
      source: rootSource,
      key: rootSource.key,
      identity: _profileSourceIdentity(profile),
      material: body,
      bodyHash: sha256.convert(utf8.encode(body)).toString(),
      settings: settings,
      settingsHash: SourceAcceptance.fingerprint(settings),
      details: Map<String, Object?>.from(
        description['details'] as Map? ?? const {},
      ),
    );
  }
  if (root.kind != 'profile') {
    return show(
      SourceReviewDialog(review: review, onDecision: presentation?.onDecision),
    );
  }
  final draft = _SubscriptionReviewDraft(ref, root, triggering: review);
  try {
    final decision = await show(
      SourceReviewDialog(
        review: root,
        loadRelated: draft.collect,
        loading: draft.loading,
        routingEditable: !isComposition && !loadedNodesSnapshot,
        onDecision: presentation?.onDecision,
        allowPartialImport: importing,
        loadedNodesSnapshot: loadedNodesSnapshot,
        canUseLoadedNodes: () => draft.loadedNodes != null,
      ),
    );
    if (decision == null) return null;
    if (!await draft.current()) {
      throw const RequestUnavailable('request_cancelled');
    }
    if (decision.importChoice != SourceImportChoice.complete) {
      if (!importing || !draft.loading.settled || draft.loading.ready) {
        throw const RequestUnavailable('request_cancelled');
      }
      if (decision.importChoice == SourceImportChoice.loadedNodes &&
          draft.loadedNodes == null) {
        throw const RequestUnavailable('request_cancelled');
      }
      store.clear();
      throw ProfileImportAlternative(
        loadedNodes: decision.importChoice == SourceImportChoice.loadedNodes
            ? draft.loadedNodes
            : null,
      );
    }
    if (!draft.loading.ready || draft.loading.busy) {
      throw const RequestUnavailable('source_review_required');
    }
    store.accept(root, draft.entries, decision);
    if (isComposition) {
      return store.decision(review) ??
          (throw const RequestUnavailable('request_cancelled'));
    }
    return decision;
  } finally {
    draft.close();
  }
}

final sourceConfirmationProvider = Provider<SourceConfirmation>(
  (ref) =>
      (review) => confirmSourceReview(ref, review),
);

SourceAcceptance _sourceAcceptance(
  CoreController core,
  Request requests, {
  SourceConfirmation? confirm,
}) => SourceAcceptance(core: core, requests: requests, confirm: confirm);

class _SubscriptionReviewDraft {
  _SubscriptionReviewDraft(this.ref, this.root, {this.triggering});
  final SourceReview? triggering;
  final Ref ref;
  final SourceReview root;
  final sessions = <RequestSession>{};
  final loading = SourceReviewLoading();
  final _verifiedBodies = <String, List<int>>{};
  final _nodeDocuments = <String, Map<String, Object?>>{};
  String? _loadedNodes;
  bool _nodesPrepared = false;
  String? get loadedNodes {
    if (!loading.settled) return null;
    if (!_nodesPrepared) {
      _loadedNodes = loadedNodesProfile(_nodeDocuments.values);
      _nodesPrepared = true;
    }
    return _loadedNodes;
  }

  List<SourceReviewBatchEntry> get entries => loading.ready
      ? loading.items.map((item) => item.entry!).toList()
      : const [];
  int _generation = 0;
  bool _closed = false;
  String? _settingsHash;
  Map<String, Object?>? _policyDescriptor;
  RequestSource? _application;

  Map<String, Object?> get settings => {
    'patch': ref
        .read(setupActionProvider.notifier)
        ._effectivePatchConfig(ref.read(patchClashConfigProvider))
        .toJson(),
    'network': ref.read(networkSettingProvider).toJson(),
    'dns': ref.read(overrideDnsProvider),
    'ntp': ref.read(overrideNtpProvider),
    'safeMode': ref.read(safeModeProvider),
    'policy': _policyDescriptor,
  };

  Future<bool> current() async =>
      !_closed &&
      ref.mounted &&
      (_settingsHash == null ||
          SourceAcceptance.fingerprint(settings) == _settingsHash) &&
      await root.source!.owner.sourceCurrent(root.source!) &&
      (_application == null ||
          await root.source!.owner.configSourceCurrent(_application!));

  void close() {
    _closed = true;
    loading.dispose();
    _verifiedBodies.clear();
    for (final session in sessions) {
      session.close();
    }
  }

  Future<List<SourceReview>> collect(String routing) async {
    final generation = ++_generation;
    for (final session in sessions) {
      session.close();
    }
    sessions.clear();
    loading.reset();
    _nodeDocuments.clear();
    _nodesPrepared = false;
    _application = await root.source!.owner.captureSource('application-config');
    Future<bool> valid() async => generation == _generation && await current();
    final source = root.source!;
    final service = SourceAcceptance(
      core: ref.read(coreHandlerProvider),
      requests: source.owner,
    );
    final description = await service.preview(
      source: source,
      kind: 'profile',
      body: root.material!,
      routing: routing,
    );
    final id = int.parse(root.key.substring('profile:'.length));
    final state = (await ref.read(setupStateProvider(id).future)).copyWith(
      overwriteType: OverwriteType.values.byName(
        root.settings['overwrite'] as String,
      ),
      matchTarget: root.settings['unmatched'] as String?,
    );
    final selection = state.policySelection;
    final selected = selection == null
        ? null
        : SelectedPolicy.decode(selection.rawContent);
    _policyDescriptor = selected?.descriptor;
    _settingsHash = SourceAcceptance.fingerprint(settings);
    final setup = ref.read(setupActionProvider.notifier);
    final patch = setup._effectivePatchConfig(
      ref.read(patchClashConfigProvider),
    );
    final document = Map<String, dynamic>.from(description['document'] as Map);
    _nodeDocuments[root.key] = document;
    late ({String yaml, String md5}) composition;
    if (selected?.usesMaterials == true) {
      var material = boundedMaterialCopy(document);
      if (state.overwriteType == OverwriteType.script && state.script != null) {
        final content = await state.script!.content ?? '';
        if (content.isNotEmpty) {
          final accepted = await _reviewScriptSource(
            core: ref.read(coreHandlerProvider),
            requests: source.owner,
            script: state.script!,
            body: content,
            automatic: true,
            isCurrent: valid,
          );
          material = boundedMaterialCopy(
            await handleAcceptedEvaluate(
              content,
              material,
              permit: accepted?.scriptPermit,
              maxBytes: managedMaterialMaxBytes,
            ),
          );
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
      final resolved = selected!.resolve(
        material: material,
        identity: root.settings['materialIdentity'] as String,
        profileId: id,
        rawSha256: root.bodyHash,
      );
      composition = await setup._composeManagedSubscription(
        state: state,
        patch: patch,
        selected: resolved,
      );
    } else {
      composition = await setup.getProfile(
        setupState: state,
        patchConfig: patch,
        previewDocument: document,
        previewOwnRouting: routing == 'own',
        isCurrent: valid,
      );
    }
    final origins = <Map<String, Object?>>[
      for (final provider in state.clashProviders)
        {
          'key': 'clash-provider:${provider.id}',
          'kind': provider.kind == ProviderKind.proxy
              ? 'provider-proxy'
              : 'provider-rule',
        },
    ];
    final finalDescription = await service.preview(
      source: source,
      kind: 'config',
      body: composition.yaml,
      rootKey: root.key,
      origins: origins,
    );
    final collected = <SourceReviewBatchEntry>[
      SourceReviewBatchEntry(
        keys: {'config:$id'},
        review: SourceReview(
          label: root.label,
          origin: root.origin,
          kind: 'config',
          reasons: const [],
          routing: 'source',
          key: 'config:$id',
          bodyHash: sha256.convert(utf8.encode(composition.yaml)).toString(),
          settingsHash: _settingsHash!,
          settings: settings,
          material: composition.yaml,
          details: Map<String, Object?>.from(
            finalDescription['details'] as Map,
          ),
        ),
      ),
    ];
    final plans = <String, Map<String, Object?>>{
      for (final item in finalDescription['providers'] as List? ?? const [])
        (item as Map)['key'] as String: Map<String, Object?>.from(item),
    };
    if (plans.length >= 256) {
      throw const RequestUnavailable('profile_download_too_large');
    }
    final sizes = <String, int>{};
    await loading.load(
      [
        SourceReviewLoadItem(
          key: 'config:$id',
          label: root.label,
          kind: 'config',
          entry: collected.single,
        ),
        for (final plan in plans.values)
          SourceReviewLoadItem(
            key: plan['key'] as String,
            label: plan['name'] as String,
            kind: plan['kind'] as String,
            origin: SourceAcceptance.displayOrigin(
              (plan['mapping'] as Map)['url'] as String? ?? '',
            ),
          ),
      ],
      (key, progress) async {
        if (!await valid()) throw const RequestUnavailable('request_cancelled');
        final plan = plans[key]!;
        final mapping = Map<String, Object?>.from(plan['mapping'] as Map);
        final cacheKey = SourceAcceptance.fingerprint([
          root.key,
          root.bodyHash,
          plan['kind'],
          mapping,
        ]);
        var cached = false;
        final trigger = triggering;
        final triggerMatches =
            trigger?.binaryMaterial != null &&
            (plan['key'] == trigger!.key ||
                (plan['origin'] as Map?)?['key'] == trigger.key);
        late List<int> body;
        try {
          final verified =
              _verifiedBodies[cacheKey] ??
              await service.previewCachedProvider(
                root: source,
                configuration: composition.yaml,
                plan: plan,
                origins: origins,
              );
          cached = verified != null;
          body =
              verified ??
              (triggerMatches
                  ? trigger.binaryMaterial!
                  : await service.previewProvider(
                      root: source,
                      configuration: composition.yaml,
                      plan: plan,
                      origins: origins,
                      mode: RequestMode.values.byName(
                        root.settings['requestMode'] as String? ?? 'auto',
                      ),
                      proxy: root.settings['requestProxy'] as String?,
                      isCurrent: valid,
                      onSession: sessions.add,
                    ));
        } on RequestUnavailable catch (error) {
          throw MessageException(
            '${plan['name']}: ${userFacingErrorMessage(error, currentAppLocalizations)}',
          );
        }
        sizes[key] = body.length;
        if (sizes.values.fold<int>(0, (a, b) => a + b) > 64 * 1024 * 1024) {
          throw const RequestUnavailable('profile_download_too_large');
        }
        progress(SourceReviewLoadPhase.parsing, cached: cached);
        final details = await service.preview(
          source: source,
          kind: plan['kind'] as String,
          body: '',
          bytes: body,
          provider: mapping,
          context: composition.yaml,
        );
        final settingsByKey = <String, String>{};
        final origin = (plan['origin'] as Map?)?['key'] as String?;
        if (origin != null) {
          if (origin.startsWith('profile:')) {
            final profile = (await database.profilesDao.query().get())
                .getProfile(int.tryParse(origin.substring('profile:'.length)));
            if (profile == null) {
              throw const RequestUnavailable('request_cancelled');
            }
            settingsByKey[origin] = SourceAcceptance.fingerprint(
              _profileSourceSettings(profile),
            );
          } else {
            for (final provider in state.clashProviders) {
              if (origin == 'clash-provider:${provider.id}') {
                settingsByKey[origin] = SourceAcceptance.fingerprint(
                  provider.definition(await provider.path),
                );
              }
            }
          }
        }
        if (!await valid()) throw const RequestUnavailable('request_cancelled');
        final frozen = (body is Uint8List ? body : Uint8List.fromList(body))
            .asUnmodifiableView();
        if (_verifiedBodies.values.fold<int>(
                  0,
                  (sum, bytes) => sum + bytes.length,
                ) -
                (_verifiedBodies[cacheKey]?.length ?? 0) +
                frozen.length <=
            64 * 1024 * 1024) {
          _verifiedBodies[cacheKey] = frozen;
        }
        if (plan['kind'] == 'provider-proxy' && details['document'] is Map) {
          _nodesPrepared = false;
          _nodeDocuments[key] = Map<String, Object?>.from(
            details['document'] as Map,
          );
        }
        return SourceReviewBatchEntry(
          keys: {
            plan['key'] as String,
            if (plan['origin'] is Map) (plan['origin'] as Map)['key'] as String,
          },
          body: frozen,
          settingsByKey: settingsByKey,
          review: SourceReview(
            label: plan['name'] as String,
            origin: SourceAcceptance.displayOrigin(
              mapping['url'] as String? ?? '',
            ),
            kind: plan['kind'] as String,
            reasons: const [],
            routing: 'source',
            key: plan['key'] as String,
            bodyHash: sha256.convert(body).toString(),
            settingsHash: SourceAcceptance.fingerprint(mapping),
            details: Map<String, Object?>.from(details['details'] as Map),
          ),
        );
      },
    );
    if (!await valid()) throw const RequestUnavailable('request_cancelled');
    return loading.items
        .where((item) => item.entry != null)
        .map((item) => item.entry!.review)
        .toList();
  }
}

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
  'materialIdentity': _materialIdentity(profile),
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
