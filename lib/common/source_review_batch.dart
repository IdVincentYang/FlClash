part of 'source_acceptance.dart';

class SourceReviewBatchEntry {
  SourceReviewBatchEntry({
    required this.review,
    required this.keys,
    this.body,
    this.settingsByKey = const {},
  });
  final SourceReview review;
  final Set<String> keys;
  final Map<String, String> settingsByKey;
  final List<int>? body;
  final Set<String> _consumed = {};

  bool matches(SourceReview candidate) =>
      keys.contains(candidate.key) &&
      candidate.kind == review.kind &&
      candidate.bodyHash == review.bodyHash &&
      candidate.settingsHash ==
          (settingsByKey[candidate.key] ?? review.settingsHash);
}

class SourceReviewBatchStore {
  static final _stores = Expando<SourceReviewBatchStore>();
  static SourceReviewBatchStore forRequests(Request requests) =>
      _stores[requests] ??= SourceReviewBatchStore();

  SourceReview? _root;
  SourceReviewDecision? _decision;
  List<SourceReviewBatchEntry> _entries = const [];
  Stopwatch? _age;
  bool get isEmpty =>
      _root == null ||
      _age == null ||
      _age!.elapsed >= const Duration(minutes: 5);

  void clear() {
    _root = null;
    _decision = null;
    _entries = const [];
    _age = null;
  }

  bool _current(String? client) =>
      _root != null &&
      _root!.source?.client == client &&
      _age != null &&
      _age!.elapsed < const Duration(minutes: 5);

  SourceReview? configuration(String rootKey, String? client) {
    if (!_current(client) || _root!.key != rootKey) return null;
    for (final entry in _entries) {
      if (entry.review.kind == 'config') return entry.review;
    }
    return null;
  }

  bool hasPending(String? client) => _current(client);

  void validateRoot(String key, String identity, String hash, String? client) {
    if (_root != null &&
        (_root!.key != key ||
            _root!.identity != identity ||
            _root!.bodyHash != hash ||
            !_current(client))) {
      clear();
    }
  }

  void accept(
    SourceReview root,
    List<SourceReviewBatchEntry> entries,
    SourceReviewDecision decision,
  ) {
    _root = root;
    _entries = List.of(entries);
    _decision = decision;
    _age = Stopwatch()..start();
  }

  SourceReviewDecision? decision(SourceReview candidate) {
    if (!_current(candidate.source?.client) || candidate.forceReview) {
      return null;
    }
    for (final entry in _entries) {
      if (entry.matches(candidate) && entry._consumed.add(candidate.key)) {
        return SourceReviewDecision(
          automatic: _decision!.automatic,
          routing: candidate.routing,
        );
      }
    }
    return null;
  }

  List<int>? material(
    String rootKey,
    String key,
    String kind,
    Map<String, Object?> mapping,
    String? client,
  ) {
    if (!_current(client) || _root!.key != rootKey) return null;
    for (final entry in _entries) {
      if (entry.body != null &&
          entry.keys.contains(key) &&
          entry.review.kind == kind &&
          (entry.settingsByKey[key] ?? entry.review.settingsHash) ==
              SourceAcceptance.fingerprint(mapping)) {
        return entry.body;
      }
    }
    return null;
  }
}
