import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/method.dart';

import 'request.dart';
import 'print.dart';
import '../enum/enum.dart';
import '../models/profile.dart';
import '../models/config_state.dart';

part 'source_review_batch.dart';

typedef SourceConfirmation =
    Future<SourceReviewDecision?> Function(SourceReview review);

enum SourceReviewStatus { ready, required }

class SourcePermission {
  const SourcePermission({
    required this.source,
    required this.key,
    required this.kind,
    required this.incarnation,
    required this.revision,
    required this.automatic,
    required this.acceptedCount,
  });

  final RequestSource source;
  final String key, kind, incarnation;
  final int revision, acceptedCount;
  final bool automatic;
}

class SourceReviewDecision {
  const SourceReviewDecision({required this.automatic, required this.routing});
  final bool automatic;
  final String routing;
}

class SourceReview {
  const SourceReview({
    required this.label,
    required this.origin,
    required this.kind,
    required this.reasons,
    required this.routing,
    this.script,
    this.material,
    this.details = const {},
    this.previous = const {},
    this.ruleTargets = const [],
    this.source,
    this.key = '',
    this.identity = '',
    this.bodyHash = '',
    this.settingsHash = '',
    this.settings = const {},
    this.forceReview = false,
    this.subscriptionKey,
    this.binaryMaterial,
  });
  final String label, origin, kind, routing;
  final List<String> reasons;
  final String? script;
  final String? material;
  final Map<String, Object?> details, previous;
  final List<String> ruleTargets;
  final RequestSource? source;
  final String key, identity, bodyHash, settingsHash;
  final Map<String, Object?> settings;
  final bool forceReview;
  final String? subscriptionKey;
  final List<int>? binaryMaterial;
}

class AcceptedSourceRevision {
  const AcceptedSourceRevision({
    required this.use,
    required this.routing,
    this.scriptPermit,
    this.materialHash,
    this.providers = const [],
    this.releaseMaterial,
  });
  final Map<String, Object?> use;
  final String routing;
  final ScriptExecutionPermit? scriptPermit;
  final String? materialHash;
  final List<Map<String, Object?>> providers;
  final Future<void> Function()? releaseMaterial;

  Future<void> release() async => releaseMaterial?.call();
}

class SourceProviderBundle {
  const SourceProviderBundle(
    this.rootUse,
    this.materials,
    this.uses,
    this.sources, [
    this.revisions = const [],
  ]);
  final Map<String, Object?> rootUse;
  final List<Map<String, Object?>> materials, uses;
  final List<RequestSource> sources;
  final List<AcceptedSourceRevision> revisions;

  Future<void> release() async {
    for (final revision in revisions) {
      await revision.release();
    }
  }
}

class ScriptExecutionPermit {
  const ScriptExecutionPermit._(this.digest, this._check);
  final String digest;
  final Future<void> Function() _check;

  Future<void> verify(String code) async {
    if (sha256.convert(utf8.encode(code)).toString() != digest) {
      throw const RequestUnavailable('source_review_required');
    }
    await _check();
  }
}

class SourceMaterialApproval {
  SourceMaterialApproval._({
    required this.requests,
    required this.key,
    required this.materialHash,
    required this.pending,
    required Future<Map<String, Object?>> Function(String, String?) call,
    required Future<Map<String, dynamic>> Function() project,
    required Future<void> Function() release,
  }) : _call = call,
       _project = project,
       _release = release;

  final Request requests;
  final String key, materialHash;
  final bool pending;
  final Future<Map<String, Object?>> Function(String, String?) _call;
  final Future<Map<String, dynamic>> Function() _project;
  final Future<void> Function() _release;

  Future<Map<String, dynamic>> project() => _project();
  Future<void> release() => _release();

  Future<void> invalidate() async {
    if (!pending) return requests.invalidate(key);
    final receipt = requests.activeReceiptId;
    if (receipt == null) throw const RequestUnavailable('request_cancelled');
    final result = await _call('invalidateMaterialSource', receipt);
    if (result['status'] != 'invalidated') {
      throw const RequestUnavailable('request_cancelled');
    }
    requests.cancelKey(key);
  }

  Future<T> commit<T>({
    RequestSession? session,
    required Future<T> Function() action,
  }) async {
    if (!pending) {
      return session == null ? requests.mutate(action) : session.commit(action);
    }
    Future<T> execute() async {
      final receipt = requests.activeReceiptId;
      if (receipt == null) throw const RequestUnavailable('request_cancelled');
      final prepared = await _call('prepareMaterialCommit', receipt);
      if (prepared['status'] != 'prepared') {
        throw const RequestUnavailable('request_cancelled');
      }
      try {
        final value = await action();
        final published = await _call('publishMaterialCommit', receipt);
        if (published['status'] != 'accepted' || published['use'] is! Map) {
          throw const RequestUnavailable('request_partial_commit');
        }
        return value;
      } catch (_) {
        await requests.markPartialCommit();
        throw const RequestUnavailable('request_partial_commit');
      }
    }

    return session == null
        ? requests.approvedLocalCommit(
            grant: () async {
              final result = await _call('grantLocalMaterialCommit', null);
              if (result['status'] != 'granted' ||
                  result['receipt'] is! String) {
                throw const RequestUnavailable('request_cancelled');
              }
              return result['receipt'] as String;
            },
            action: execute,
          )
        : session.commit(execute);
  }
}

class SourceAcceptance {
  const SourceAcceptance({
    required this.core,
    required this.requests,
    this.confirm,
  });

  final CoreController core;
  final Request requests;
  final SourceConfirmation? confirm;

  static String fingerprint(Object? value) =>
      sha256.convert(utf8.encode(json.encode(value))).toString();

  static String displayOrigin(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).origin;
  }

  Future<Map<String, Object?>> _call(Map<String, Object?> arguments) async {
    if (const {'withdraw', 'reset'}.contains(arguments['action'])) {
      SourceReviewBatchStore.forRequests(requests).clear();
    }
    try {
      return await core.sourceAcceptance(arguments);
    } on CoreMethodException catch (error) {
      commonPrint.log(
        'Source acceptance ${arguments['action']}: ${error.code}',
      );
      throw RequestUnavailable(switch (error.code) {
        'local_groups_ambiguous' => 'local_groups_ambiguous',
        'local_groups_in_use' => 'local_groups_in_use',
        'local_groups_invalid' => 'local_groups_changed',
        'source_superseded' => 'request_cancelled',
        'request_commit_busy' => 'request_commit_busy',
        'request_restart_required' => 'request_restart_required',
        'source_budget_exceeded' => 'source_storage_full',
        'source_use_revoked' ||
        'source_review_required' => 'source_review_required',
        'source_content_invalid' => 'profile_invalid',
        'source_material_unavailable' => 'source_material_unavailable',
        'source_routing_excluded' => 'source_routing_excluded',
        'source_recovery_unavailable' => 'source_recovery_unavailable',
        _ => 'source_permissions_unavailable',
      });
    }
  }

  Map<String, Object?> _ticket(RequestSource source) => {
    'client': source.client ?? '',
    'dataset': source.snapshot['dataset'] ?? 0,
    'sources': {source.key: source.snapshot['sourceRevision'] ?? 0},
  };

  Future<Map<String, Object?>> preview({
    required RequestSource source,
    required String kind,
    required String body,
    String? routing,
    String? rootKey,
    List<Map<String, Object?>> origins = const [],
    List<int>? bytes,
    Map<String, Object?>? provider,
    String? context,
  }) async {
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final result = await _call({
      'action': 'preview',
      'key': source.key,
      'kind': kind,
      'source': _ticket(source),
      if (bytes == null) 'body': body else 'bodyBase64': base64Encode(bytes),
      'routing': ?routing,
      if (rootKey != null) 'parent': {'key': rootKey},
      'uses': origins,
      'provider': ?provider,
      'format': ?provider?['format'],
      'behavior': ?provider?['behavior'],
      'preview': ?context,
    });
    if (result['status'] != 'preview' ||
        !await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    return result;
  }

  Future<List<int>?> previewCachedProvider({
    required RequestSource root,
    required String configuration,
    required Map<String, Object?> plan,
    required List<Map<String, Object?>> origins,
  }) async {
    final result = await _call({
      'action': 'previewCachedProvider',
      'key': root.key,
      'kind': plan['kind'],
      'source': _ticket(root),
      'body': configuration,
      'parent': {'key': root.key},
      'uses': origins,
      'providerName': plan['name'],
    });
    final lease = result['materialLease'] as String?;
    try {
      if (!await requests.sourceCurrent(root)) {
        throw const RequestUnavailable('request_cancelled');
      }
      if (result['status'] == 'missing') return null;
      if (result['status'] != 'reused' ||
          result['bodyBase64'] is! String ||
          lease == null) {
        throw const RequestUnavailable('source_material_unavailable');
      }
      return base64Decode(result['bodyBase64'] as String);
    } finally {
      if (lease != null) {
        await _call({
          'action': 'releaseMaterial',
          'materialLease': lease,
          'source': _ticket(root),
        });
      }
    }
  }

  Future<List<int>> previewProvider({
    required RequestSource root,
    required String configuration,
    required Map<String, Object?> plan,
    required List<Map<String, Object?>> origins,
    required RequestMode mode,
    String? proxy,
    required Future<bool> Function() isCurrent,
    required void Function(RequestSession) onSession,
  }) async {
    final mapping = Map<String, Object?>.from(plan['mapping'] as Map);
    final key = 'review:${fingerprint([root.key, plan['key'], configuration])}';
    Future<List<int>> fetch(RequestSession? session) async {
      if (!await isCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
      final source = await requests.captureSource(key);
      final result = await _call({
        'action': 'previewProvider',
        'key': key,
        'kind': plan['kind'],
        'body': configuration,
        'parent': {'key': root.key},
        'uses': origins,
        'providerName': plan['name'],
        'source': _ticket(source),
        'session': ?session?.id,
      });
      if (result['status'] != 'downloaded' ||
          result['bodyBase64'] is! String ||
          !await isCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
      return base64Decode(result['bodyBase64'] as String);
    }

    if (mapping['type'] == 'file') return fetch(null);
    final target = mapping['proxy'] as String? ?? '';
    return requests.withSession(
      key: key,
      url: mapping['url'] as String,
      mode: target == 'DIRECT'
          ? RequestMode.direct
          : target.isNotEmpty
          ? RequestMode.proxy
          : mode,
      proxy: target.isNotEmpty && target != 'DIRECT' ? target : proxy,
      sourceIsCurrent: isCurrent,
      action: (session) {
        onSession(session);
        return fetch(session);
      },
    );
  }

  Future<AcceptedSourceRevision> review({
    required RequestSource source,
    required String identity,
    required Object settings,
    required String body,
    required String label,
    required String location,
    required String kind,
    String? entityKey,
    List<Map<String, Object?>> uses = const [],
    bool automatic = false,
    bool forceReview = false,
    bool fresh = false,
    List<int>? binaryBody,
    String? format,
    String? behavior,
    Map<String, Object?>? provider,
    Map<String, Object?>? parent,
    String? providerName,
    String? subscriptionKey,
    Map<String, Object?>? contextUse,
    String? contextMaterialHash,
    String? routing,
    Future<bool> Function()? isCurrent,
  }) async {
    final result = await _review(
      source: source,
      identity: identity,
      settings: settings,
      body: body,
      label: label,
      location: location,
      kind: kind,
      entityKey: entityKey,
      uses: uses,
      automatic: automatic,
      forceReview: forceReview,
      fresh: fresh,
      binaryBody: binaryBody,
      format: format,
      behavior: behavior,
      provider: provider,
      parent: parent,
      providerName: providerName,
      subscriptionKey: subscriptionKey,
      contextUse: contextUse,
      contextMaterialHash: contextMaterialHash,
      routing: routing,
      isCurrent: isCurrent,
    );
    return result.accepted ??
        (throw const RequestUnavailable('source_review_required'));
  }

  Future<SourceMaterialApproval> reviewMaterial({
    required RequestSource source,
    required String identity,
    required Object settings,
    required String body,
    required String label,
    required String location,
    required String kind,
    RequestSession? session,
    bool automatic = false,
    bool forceReview = false,
    bool fresh = false,
    Future<bool> Function()? isCurrent,
  }) async {
    final result = await _review(
      source: source,
      identity: identity,
      settings: settings,
      body: body,
      label: label,
      location: location,
      kind: kind,
      automatic: automatic,
      forceReview: forceReview,
      fresh: fresh,
      isCurrent: isCurrent,
      materialOperation: session == null ? 'local' : 'network',
      materialSession: session,
    );
    if (result.material != null) return result.material!;
    final accepted = result.accepted!;
    return SourceMaterialApproval._(
      requests: requests,
      key: source.key,
      materialHash: accepted.materialHash!,
      pending: false,
      call: (_, _) async => throw StateError('No deferred source permission'),
      project: () => project(source: source, identity: identity, body: body),
      release: accepted.release,
    );
  }

  Future<({AcceptedSourceRevision? accepted, SourceMaterialApproval? material})>
  _review({
    required RequestSource source,
    required String identity,
    required Object settings,
    required String body,
    required String label,
    required String location,
    required String kind,
    String? entityKey,
    List<Map<String, Object?>> uses = const [],
    bool automatic = false,
    bool forceReview = false,
    bool fresh = false,
    List<int>? binaryBody,
    String? format,
    String? behavior,
    Map<String, Object?>? provider,
    Map<String, Object?>? parent,
    String? providerName,
    String? subscriptionKey,
    Map<String, Object?>? contextUse,
    String? contextMaterialHash,
    String? routing,
    Future<bool> Function()? isCurrent,
    String? materialOperation,
    RequestSession? materialSession,
  }) async {
    Future<void> check() async {
      if (!await requests.sourceCurrent(source) ||
          isCurrent != null && !await isCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
    }

    await check();
    final bodyHash = sha256.convert(binaryBody ?? utf8.encode(body)).toString();
    if (kind == 'profile') {
      SourceReviewBatchStore.forRequests(requests).validateRoot(
        entityKey ?? source.key,
        identity,
        bodyHash,
        source.client,
      );
    }
    final input = <String, Object?>{
      'key': entityKey ?? source.key,
      'identity': identity,
      'settings': fingerprint(settings),
      'kind': kind,
      'source': _ticket(source),
      'routing': ?routing,
      'uses': uses,
      'forceReview': forceReview,
      'fresh': fresh,
      'materialOperation': ?materialOperation,
      'session': ?materialSession?.id,
      if (materialOperation == 'local') ...{
        'expectedState': {
          'epoch': (source.snapshot['state'] as Map?)?['processEpoch'],
          'revision': (source.snapshot['state'] as Map?)?['revision'],
        },
        'owner': source.snapshot['owner'],
        'operation': source.snapshot['operation'],
      },
      'format': ?format,
      'behavior': ?behavior,
      'provider': ?provider,
      'parent': ?parent,
      'providerName': ?providerName,
      'use': ?contextUse,
      'materialHash': ?contextMaterialHash,
    };
    var result = await _call({
      ...input,
      'action': 'review',
      if (binaryBody == null)
        'body': body
      else
        'bodyBase64': base64Encode(binaryBody),
    });
    var handedOff = false;
    var released = false;
    String? displayedCandidate;
    Future<void> release() async {
      final lease = result['materialLease'];
      if (released || lease is! String || lease.isEmpty) return;
      released = true;
      try {
        await _call({
          'action': 'releaseMaterial',
          'materialLease': lease,
          'source': _ticket(source),
        });
      } catch (_) {}
    }

    try {
      if (result['status'] == 'reviewRequired') {
        if (automatic || confirm == null) {
          throw const RequestUnavailable('source_review_required');
        }
        displayedCandidate = result['candidate'] as String?;
        final decision = await confirm!(
          SourceReview(
            source: source,
            subscriptionKey: subscriptionKey ?? parent?['key'] as String?,
            binaryMaterial: binaryBody == null
                ? null
                : List<int>.unmodifiable(binaryBody),
            key: entityKey ?? source.key,
            identity: identity,
            bodyHash: bodyHash,
            settingsHash: fingerprint(settings),
            settings: settings is Map
                ? Map<String, Object?>.from(settings)
                : const {},
            forceReview: forceReview,
            label: label,
            origin: displayOrigin(location),
            kind: kind,
            reasons: List<String>.from(result['reasons'] as List? ?? const []),
            routing: result['routing'] as String? ?? 'source',
            script: kind == 'script' ? body : null,
            material: kind == 'script' || binaryBody != null ? null : body,
            details: Map<String, Object?>.from(
              result['details'] as Map? ?? const {},
            ),
            previous: Map<String, Object?>.from(
              result['previous'] as Map? ?? const {},
            ),
            ruleTargets: [
              for (final slot
                  in (result['ruleContract'] as Map?)?['slots'] as List? ??
                      const [])
                if (slot is Map && slot['target'] is String)
                  slot['target'] as String,
            ],
          ),
        );
        if (decision == null) {
          throw const RequestUnavailable('source_review_required');
        }
        await check();
        if (decision.routing != result['routing']) {
          result = await _call({
            ...input,
            'action': 'review',
            if (binaryBody == null)
              'body': body
            else
              'bodyBase64': base64Encode(binaryBody),
            'routing': decision.routing,
          });
          if (result['status'] == 'reviewRequired') {
            displayedCandidate = result['candidate'] as String?;
          }
          await check();
        }
        if (result['status'] == 'reviewRequired') {
          result = await _call({
            ...input,
            'action': materialOperation == null ? 'accept' : 'approveMaterial',
            'candidate': result['candidate'],
            'automatic': decision.automatic,
            'routing': decision.routing,
            if (decision.automatic) 'rules': result['ruleContract'],
          });
        }
      }
      await check();
      if (result['status'] == 'approved' && materialOperation != null) {
        final candidate = result['candidate'] as String;
        final hash = result['materialHash'] as String;
        Future<Map<String, Object?>> call(String action, String? receipt) =>
            _call({
              'action': action,
              'key': entityKey ?? source.key,
              'kind': kind,
              'source': _ticket(source),
              'candidate': candidate,
              'materialHash': hash,
              'receipt': ?receipt,
            });
        final approval = SourceMaterialApproval._(
          requests: requests,
          key: entityKey ?? source.key,
          materialHash: hash,
          pending: true,
          call: call,
          project: () async {
            final projected = await call('projectMaterial', null);
            if (projected['status'] != 'projected' ||
                projected['document'] is! Map) {
              throw const RequestUnavailable('source_review_required');
            }
            return Map<String, dynamic>.from(projected['document'] as Map);
          },
          release: () async {
            await release();
            try {
              await call('releaseMaterialApproval', null);
            } catch (_) {}
          },
        );
        handedOff = true;
        return (accepted: null, material: approval);
      }
      if (result['status'] != 'accepted' || result['use'] is! Map) {
        throw const RequestUnavailable('source_review_required');
      }
      final accepted = AcceptedSourceRevision(
        use: Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(result['use'] as Map),
        ),
        routing: result['routing'] as String? ?? 'source',
        materialHash: result['materialHash'] as String?,
        releaseMaterial: release,
        providers: [
          for (final plan in result['providers'] as List? ?? const [])
            Map<String, Object?>.from(plan as Map),
        ],
        scriptPermit: kind == 'script'
            ? ScriptExecutionPermit._(
                sha256.convert(utf8.encode(body)).toString(),
                () async {
                  await check();
                  final checked = await _call({
                    ...input,
                    'action': 'checkCode',
                    'body': body,
                    'use': result['use'],
                  });
                  if (checked['status'] != 'accepted') {
                    throw const RequestUnavailable('source_review_required');
                  }
                  await check();
                },
              )
            : null,
      );
      handedOff = true;
      return (accepted: accepted, material: null);
    } finally {
      if (!handedOff) {
        if (displayedCandidate != null) {
          try {
            await _call({
              ...input,
              'action': 'discard',
              'candidate': displayedCandidate,
            });
          } catch (_) {}
        }
        await release();
      }
    }
  }

  Future<({AcceptedSourceRevision revision, RequestSource source})?>
  _reviewProviderOrigin({
    required Map<String, Object?> plan,
    required List<int> body,
    required bool automatic,
    required Future<bool> Function() isCurrent,
    bool forceReview = false,
  }) async {
    if (plan['origin'] is! Map) return null;
    final origin = Map<String, Object?>.from(plan['origin'] as Map);
    final mapping = Map<String, Object?>.from(plan['mapping'] as Map);
    final source = await requests.captureSource(origin['key'] as String);
    final revision = await review(
      source: source,
      identity: origin['identity'] as String,
      settings: mapping,
      body: '',
      binaryBody: body,
      format: mapping['format'] as String?,
      behavior: mapping['behavior'] as String?,
      label: plan['name'] as String,
      location: mapping['url'] as String? ?? '',
      kind: plan['kind'] as String,
      subscriptionKey: (plan['parent'] as Map)['key'] as String,
      automatic: automatic,
      forceReview: forceReview,
      isCurrent: isCurrent,
    );
    return (revision: revision, source: source);
  }

  Future<SourceProviderBundle> completeProviders({
    required AcceptedSourceRevision root,
    required List<Map<String, Object?>> dependencies,
    required RequestSource source,
    required bool automatic,
    required Future<bool> Function() isCurrent,
    bool reuseAccepted = false,
    bool acceptedOnly = false,
    bool allowBootstrap = false,
    bool reviewed = false,
    bool reuseReviewed = false,
    void Function(bool downloading)? onDownloading,
  }) async {
    final materials = <Map<String, Object?>>[];
    final uses = <Map<String, Object?>>[...dependencies];
    final sources = <RequestSource>[];
    final revisions = <AcceptedSourceRevision>[root];
    try {
      if (root.providers.isEmpty) {
        return SourceProviderBundle(
          root.use,
          materials,
          uses,
          sources,
          revisions,
        );
      }
      if (reuseAccepted && !reviewed) {
        final cached = await _call({
          'action': 'reuseCachedProviders',
          'key': root.use['key'],
          'kind': 'config',
          'source': _ticket(source),
          'use': root.use,
          'materialHash': root.materialHash,
        });
        if (cached['status'] == 'accepted') {
          var released = false;
          final leases = [
            if (cached['materialLease'] case final String lease) lease,
            ...List<String>.from(cached['materialLeases'] as List? ?? const []),
          ];
          revisions.add(
            AcceptedSourceRevision(
              use: Map<String, Object?>.from(cached['use'] as Map),
              routing: 'source',
              releaseMaterial: () async {
                if (released) return;
                released = true;
                for (final lease in leases) {
                  await _call({
                    'action': 'releaseMaterial',
                    'materialLease': lease,
                    'source': _ticket(source),
                  });
                }
              },
            ),
          );
          if (!await isCurrent()) {
            throw const RequestUnavailable('request_cancelled');
          }
          final cachedUses = [
            for (final use in cached['uses'] as List)
              Map<String, Object?>.from(use as Map),
          ];
          for (final key
              in cachedUses.map((use) => use['key'] as String).toSet()) {
            sources.add(await requests.captureSource(key));
          }
          if (!await isCurrent()) {
            throw const RequestUnavailable('request_cancelled');
          }
          return SourceProviderBundle(
            Map<String, Object?>.from(cached['use'] as Map),
            [
              for (final material in cached['providerMaterials'] as List)
                Map<String, Object?>.from(material as Map),
            ],
            cachedUses,
            sources,
            revisions,
          );
        }
        if (cached['status'] != 'missing') {
          throw const RequestUnavailable('source_review_required');
        }
      }
      for (final plan in root.providers) {
        if (!await isCurrent()) {
          throw const RequestUnavailable('request_cancelled');
        }
        final mapping = Map<String, Object?>.from(plan['mapping'] as Map);
        final key = plan['key'] as String;
        final kind = plan['kind'] as String;
        final name = plan['name'] as String;
        final location = mapping['type'] == 'http'
            ? mapping['url'] as String
            : 'file://${mapping['path']}';
        final proxy = mapping['proxy'] as String? ?? '';
        Future<Map<String, Object?>> fetchMaterial(
          Map<String, Object?> arguments,
        ) async {
          final downloading = mapping['type'] == 'http';
          if (downloading) onDownloading?.call(true);
          try {
            return await _call(arguments);
          } finally {
            if (downloading) onDownloading?.call(false);
          }
        }

        Future<
          ({AcceptedSourceRevision revision, Map<String, Object?>? origin})
        >
        acceptBody(RequestSource providerSource, List<int> body) async {
          final origin = await _reviewProviderOrigin(
            plan: plan,
            body: body,
            automatic: automatic,
            isCurrent: isCurrent,
          );
          if (origin != null) {
            revisions.add(origin.revision);
            sources.add(origin.source);
          }
          final accepted = await review(
            source: providerSource,
            identity: plan['declaration'] as String,
            settings: mapping,
            body: '',
            binaryBody: body,
            provider: mapping,
            parent: Map<String, Object?>.from(plan['parent'] as Map),
            providerName: name,
            contextUse: root.use,
            contextMaterialHash: root.materialHash,
            format: mapping['format'] as String?,
            behavior: mapping['behavior'] as String?,
            label: name,
            location: location,
            kind: kind,
            automatic: automatic,
            isCurrent: isCurrent,
          );
          revisions.add(accepted);
          sources.add(providerSource);
          return (revision: accepted, origin: origin?.revision.use);
        }

        ({AcceptedSourceRevision revision, Map<String, Object?>? origin})?
        accepted;
        final providerSource = await requests.captureSource(key);
        final reviewedBody = SourceReviewBatchStore.forRequests(requests)
            .material(
              (plan['parent'] as Map)['key'] as String,
              key,
              kind,
              mapping,
              providerSource.client,
            );
        if (reviewedBody != null) {
          accepted = await acceptBody(providerSource, reviewedBody);
        }
        if (accepted == null && reuseReviewed) {
          final reused = await _call({
            'action': 'reuseReviewedProvider',
            'key': key,
            'kind': kind,
            'source': _ticket(providerSource),
            'providerName': name,
            'use': root.use,
            'materialHash': root.materialHash,
          });
          final lease = reused['materialLease'] as String?;
          try {
            if (reused['status'] == 'reused' &&
                reused['bodyBase64'] is String &&
                lease != null) {
              accepted = await acceptBody(
                providerSource,
                base64Decode(reused['bodyBase64'] as String),
              );
            } else if (reused['status'] != 'missing') {
              throw const RequestUnavailable('source_review_required');
            }
          } finally {
            if (lease != null) {
              await _call({
                'action': 'releaseMaterial',
                'materialLease': lease,
                'source': _ticket(providerSource),
              });
            }
          }
        }
        if (accepted == null && reuseAccepted) {
          final providerSource = await requests.captureSource(key);
          final reused = await _call({
            'action': 'reuseCachedProvider',
            'key': key,
            'kind': kind,
            'source': _ticket(providerSource),
            'providerName': name,
            'use': root.use,
            'materialHash': root.materialHash,
          });
          final lease = reused['materialLease'] as String?;
          try {
            if (reused['status'] == 'reused') {
              if (lease == null || reused['bodyBase64'] is! String) {
                throw const RequestUnavailable(
                  'source_permissions_unavailable',
                );
              }
              if (!await isCurrent() ||
                  !await requests.configSourceCurrent(providerSource)) {
                throw const RequestUnavailable('request_cancelled');
              }
              accepted = await acceptBody(
                providerSource,
                base64Decode(reused['bodyBase64'] as String),
              );
            } else if (reused['status'] != 'missing') {
              throw const RequestUnavailable('source_review_required');
            }
          } finally {
            if (lease != null) {
              await _call({
                'action': 'releaseMaterial',
                'materialLease': lease,
                'source': _ticket(providerSource),
              });
            }
          }
        }
        if (accepted == null && acceptedOnly) {
          throw const RequestUnavailable('source_review_required');
        }
        if (accepted == null && mapping['type'] == 'file') {
          final providerSource = await requests.captureSource(key);
          final fetched = await fetchMaterial({
            'action': 'fetchProvider',
            'key': key,
            'kind': kind,
            'source': _ticket(providerSource),
            'providerName': name,
            'use': root.use,
            'materialHash': root.materialHash,
          });
          if (fetched['status'] != 'downloaded' ||
              fetched['bodyBase64'] is! String) {
            throw const RequestUnavailable('profile_download_failed');
          }
          accepted = await acceptBody(
            providerSource,
            base64Decode(fetched['bodyBase64'] as String),
          );
        }
        final material =
            accepted ??
            await requests.withSession<
              ({AcceptedSourceRevision revision, Map<String, Object?>? origin})
            >(
              key: key,
              url: location,
              mode: proxy == 'DIRECT'
                  ? RequestMode.direct
                  : proxy.isNotEmpty
                  ? RequestMode.proxy
                  : RequestMode.auto,
              proxy: proxy,
              automatic: automatic,
              allowBootstrap:
                  allowBootstrap &&
                  mapping['type'] == 'http' &&
                  (proxy.isEmpty || proxy == 'DIRECT'),
              label: '$name · ${displayOrigin(location)}',
              sourceIsCurrent: isCurrent,
              action: (session) async {
                final providerSource = await requests.captureSource(key);
                final fetched = await fetchMaterial({
                  'action': 'fetchProvider',
                  'key': key,
                  'kind': kind,
                  'source': _ticket(providerSource),
                  'session': session.id,
                  'providerName': name,
                  'use': root.use,
                  'materialHash': root.materialHash,
                });
                if (fetched['status'] != 'downloaded' ||
                    fetched['bodyBase64'] is! String) {
                  throw const RequestUnavailable('profile_download_failed');
                }
                final accepted = await acceptBody(
                  providerSource,
                  base64Decode(fetched['bodyBase64'] as String),
                );
                await session.check();
                return accepted;
              },
            );
        uses.add(material.revision.use);
        materials.add({
          'name': name,
          'kind': kind,
          'parent': plan['parent'],
          'declaration': plan['declaration'],
          'materialHash': material.revision.materialHash,
          'use': material.revision.use,
          'origin': ?material.origin,
        });
      }
      if (!await isCurrent()) {
        throw const RequestUnavailable('request_cancelled');
      }
      final bound = await _call({
        'action': 'bindProviders',
        'bundle':
            reviewed ||
            SourceReviewBatchStore.forRequests(requests).configuration(
                  (root.use['key'] as String).replaceFirst(
                    'config:',
                    'profile:',
                  ),
                  source.client,
                ) !=
                null,
        'key': root.use['key'],
        'kind': 'config',
        'source': _ticket(source),
        'use': root.use,
        'materialHash': root.materialHash,
        'providerMaterials': materials,
      });
      if (bound['status'] != 'accepted' ||
          bound['use'] is! Map ||
          bound['uses'] is! List) {
        throw const RequestUnavailable('source_review_required');
      }
      return SourceProviderBundle(
        Map<String, Object?>.from(bound['use'] as Map),
        materials,
        [
          for (final use in bound['uses'] as List)
            Map<String, Object?>.from(use as Map),
        ],
        sources,
        revisions,
      );
    } catch (_) {
      for (final revision in revisions) {
        await revision.release();
      }
      rethrow;
    }
  }

  Future<void> applyProvider({
    required String key,
    required String name,
    required String kind,
    List<int>? body,
    bool forceReview = false,
  }) async {
    if (!requests.requiresSourceAcceptance) {
      throw const RequestUnavailable('source_permissions_unavailable');
    }
    final source = await requests.captureSource(key);
    final inspected = await _call({
      'action': 'inspectProvider',
      'key': key,
      'kind': kind,
      'providerName': name,
      'source': _ticket(source),
    });
    if (inspected['status'] != 'provider' ||
        inspected['config'] is! Map ||
        inspected['providers'] is! List) {
      throw const RequestUnavailable('source_review_required');
    }
    final fence = Map<String, Object?>.from(inspected['config'] as Map);
    final plan = Map<String, Object?>.from(
      (inspected['providers'] as List).single as Map,
    );
    final mapping = Map<String, Object?>.from(plan['mapping'] as Map);
    Future<bool> current() async =>
        await requests.sourceCurrent(source) &&
        jsonEncode((await core.getConfigState()).fence) == jsonEncode(fence);
    final candidateBody =
        body ?? base64Decode(inspected['bodyBase64'] as String);
    final origin = await _reviewProviderOrigin(
      plan: plan,
      body: candidateBody,
      automatic: false,
      forceReview: forceReview,
      isCurrent: current,
    );
    AcceptedSourceRevision? accepted;
    try {
      accepted = await review(
        source: source,
        identity: plan['declaration'] as String,
        settings: mapping,
        body: '',
        binaryBody: candidateBody,
        format: mapping['format'] as String?,
        behavior: mapping['behavior'] as String?,
        provider: mapping,
        parent: Map<String, Object?>.from(plan['parent'] as Map),
        providerName: name,
        contextUse: Map<String, Object?>.from(plan['context'] as Map),
        contextMaterialHash: plan['contextMaterialHash'] as String,
        label: name,
        location: mapping['url'] as String? ?? '',
        kind: kind,
        forceReview: forceReview,
        isCurrent: current,
      );
      if (!await current()) throw const RequestUnavailable('request_cancelled');
      final applied = await _call({
        'action': 'adoptProvider',
        'key': key,
        'kind': kind,
        'providerName': name,
        'source': _ticket(source),
        'expectedConfig': fence,
        'materialHash': accepted.materialHash,
        'use': accepted.use,
      });
      if (applied['status'] != 'applied') {
        throw const RequestUnavailable('source_review_required');
      }
    } finally {
      await accepted?.release();
      await origin?.revision.release();
    }
  }

  Future<Map<String, Object?>> inspectMaterialRecovery({
    required RequestSource source,
    required List<Map<String, Object?>> rows,
  }) async {
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final result = await _call({
      'action': 'inspectMaterialRecovery',
      'key': 'application-config',
      'kind': 'config',
      'source': _ticket(source),
      'recovery': {'rows': rows},
    });
    if (result['status'] != 'recovery' || result['recovery'] is! Map) {
      throw const RequestUnavailable('request_commit_recovery_required');
    }
    return Map<String, Object?>.from(result['recovery'] as Map);
  }

  Future<void> recoverMaterialCommit({
    required RequestSource source,
    required Map<String, Object?> snapshot,
  }) async {
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final result = await _call({
      'action': 'recoverMaterialCommit',
      'key': 'application-config',
      'kind': 'config',
      'source': _ticket(source),
      'recovery': snapshot,
    });
    if (result['status'] != 'recovered') {
      throw const RequestUnavailable('request_commit_recovery_required');
    }
    requests.acceptMaterialRecovery();
  }

  Future<SourceReviewStatus> subscriptionStatus({
    required RequestSource source,
    required String identity,
    required Object settings,
    required String body,
  }) async {
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final result = await _call({
      'action': 'status',
      'key': source.key,
      'kind': 'profile',
      'identity': identity,
      'settings': fingerprint(settings),
      'body': body,
      'source': _ticket(source),
    });
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    return switch (result['status']) {
      'accepted' => SourceReviewStatus.ready,
      'reviewRequired' => SourceReviewStatus.required,
      _ => throw const RequestUnavailable('source_permissions_unavailable'),
    };
  }

  Future<({Map<String, String> picks, Map<String, dynamic> document})>
  approveLocalGroups({
    required RequestSource source,
    required int profileId,
    required ConfigFact expected,
    String body = '',
    required List<LocalProxyGroup> before,
    required List<LocalProxyGroup> after,
  }) async {
    if (!await requests.configSourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    late Map<String, Object?> result;
    try {
      result = await _call({
        'action': 'approveLocalGroups',
        'receipt': ?requests.activeReceiptId,
        'key': 'config:$profileId',
        'kind': 'config',
        'source': _ticket(source),
        'expectedConfig': expected.fence,
        'body': body,
        'localGroupsBefore': before.map((group) => group.toJson()).toList(),
        'localGroups': after.map((group) => group.toJson()).toList(),
      });
    } on RequestUnavailable catch (error) {
      if (error.code == 'source_review_required') {
        throw const RequestUnavailable('local_groups_source_unavailable');
      }
      rethrow;
    }
    if (!await requests.configSourceCurrent(source) ||
        result['status'] != 'localGroupsAccepted') {
      throw const RequestUnavailable('request_cancelled');
    }
    return (
      picks: Map<String, String>.from(
        result['selectedMap'] as Map? ?? const {},
      ),
      document: Map<String, dynamic>.from(result['document'] as Map),
    );
  }

  Future<List<SourcePermission>> permissions({
    required RequestSource source,
    required String kind,
    String? entityKey,
  }) async {
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final key = entityKey ?? source.key;
    final result = await _call({
      'action': 'inspect',
      'key': key,
      'kind': kind,
      'source': _ticket(source),
    });
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final grant = result['grant'];
    if (result['status'] != 'inspected') {
      throw const RequestUnavailable('source_review_required');
    }
    if (grant == null) return const [];
    if (grant is! Map ||
        grant['incarnation'] is! String ||
        grant['revision'] is! int ||
        grant['purposes'] is! Map) {
      throw const RequestUnavailable('source_review_required');
    }
    return [
      for (final entry in (grant['purposes'] as Map).entries)
        if (entry.value is Map)
          SourcePermission(
            source: source,
            key: key,
            kind: entry.key as String,
            incarnation: grant['incarnation'] as String,
            revision: grant['revision'] as int,
            automatic: entry.value['automatic'] == true,
            acceptedCount: (entry.value['accepted'] as List?)?.length ?? 0,
          ),
    ];
  }

  Future<void> withdraw(
    SourcePermission permission, {
    required bool stopUse,
  }) async {
    if (!await requests.sourceCurrent(permission.source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final result = await _call({
      'action': 'withdraw',
      'key': permission.key,
      'kind': permission.kind,
      'incarnation': permission.incarnation,
      'revision': permission.revision,
      'stopUse': stopUse,
      'source': _ticket(permission.source),
    });
    if (result['status'] != 'withdrawn') {
      throw const RequestUnavailable('source_review_required');
    }
  }

  Future<void> reset({List<String>? keys}) async {
    if (!requests.requiresSourceAcceptance) return;
    final source = await requests.captureSource('application-config');
    final result = await _call({
      'action': 'reset',
      'key': 'application-config',
      'kind': 'config',
      'source': _ticket(source),
      'keys': ?keys,
    });
    if (result['status'] != 'reset') {
      throw const RequestUnavailable('source_review_required');
    }
  }

  Future<Map<String, dynamic>> project({
    required RequestSource source,
    required String identity,
    required String body,
  }) async {
    if (!await requests.sourceCurrent(source)) {
      throw const RequestUnavailable('request_cancelled');
    }
    final result = await _call({
      'action': 'project',
      'key': source.key,
      'identity': identity,
      'body': body,
      'source': _ticket(source),
    });
    if (!await requests.sourceCurrent(source) || result['document'] is! Map) {
      throw const RequestUnavailable('request_cancelled');
    }
    return Map<String, dynamic>.from(result['document'] as Map);
  }
}
