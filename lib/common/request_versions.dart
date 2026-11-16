const requestHistoryLimit = 4096;
const requestVersionLimit = 0x1fffffffffffff;

class _RequestVersionEntry {
  _RequestVersionEntry(this.version);
  int version;
  int pins = 0;
  Object? intent;
}

class RequestVersionHold {
  RequestVersionHold(this.version, this.release);
  final int version;
  final void Function() release;
}

class RequestVersions {
  RequestVersions({int initialVersion = 0}) : _highWater = initialVersion;

  final _entries = <String, _RequestVersionEntry>{};
  final _cold = <String, _RequestVersionEntry>{};
  int _highWater;
  bool exhausted = false;

  int get length => _entries.length;
  int get coldLength => _cold.length;

  int read(String key) {
    if (exhausted) return 0;
    final entry = _entries[key];
    if (entry == null) return 0;
    if (_cold.remove(key) != null) _cold[key] = entry;
    return entry.version;
  }

  int ensure(String key) {
    final existing = read(key);
    if (existing != 0) return existing;
    if (exhausted || _highWater > requestVersionLimit - 2) {
      exhausted = true;
      return 0;
    }
    // Skip the successor reserved for one material invalidation.
    _highWater += 2;
    final entry = _RequestVersionEntry(_highWater);
    _entries[key] = entry;
    _cold[key] = entry;
    _trim();
    return entry.version;
  }

  Object beginIntent(String key) {
    final intent = Object();
    _entries[key]!.intent = intent;
    return intent;
  }

  bool intentCurrent(String key, Object intent) =>
      !exhausted && identical(_entries[key]?.intent, intent);

  void endIntent(String key, Object intent) {
    if (identical(_entries[key]?.intent, intent)) {
      _entries[key]!.intent = null;
    }
  }

  int advance(String key, {bool create = false, bool keepIntent = false}) {
    if (!keepIntent) _entries[key]?.intent = null;
    final version = read(key);
    if (version == 0) return create ? ensure(key) : 0;
    if (version == requestVersionLimit) {
      exhausted = true;
      return 0;
    }
    final next = _entries[key]!.version = version + 1;
    if (next > _highWater) _highWater = next;
    return next;
  }

  RequestVersionHold retain(String key) {
    final version = ensure(key);
    if (version == 0) return RequestVersionHold(0, () {});
    final entry = _entries[key]!;
    _cold.remove(key);
    entry.pins++;
    var released = false;
    return RequestVersionHold(version, () {
      if (released) return;
      released = true;
      entry.pins--;
      if (entry.pins == 0) {
        _cold[key] = entry;
        _trim();
      }
    });
  }

  void _trim() {
    while (_cold.length > requestHistoryLimit) {
      final key = _cold.keys.first;
      _cold.remove(key);
      _entries.remove(key);
    }
  }

  void clearCold() {
    for (final key in _cold.keys) {
      _entries.remove(key);
    }
    _cold.clear();
  }
}
