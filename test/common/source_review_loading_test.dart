import 'dart:async';

import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/source_review_loading.dart';
import 'package:flutter_test/flutter_test.dart';

SourceReviewBatchEntry entry(String key) => SourceReviewBatchEntry(
  keys: {key},
  review: SourceReview(
    key: key,
    label: key,
    origin: '',
    kind: 'provider-rule',
    reasons: const [],
    routing: 'source',
  ),
);

void main() {
  test(
    'loads at most three sources and retries only the failed source',
    () async {
      final loading = SourceReviewLoading();
      addTearDown(loading.dispose);
      final gates = {for (var i = 0; i < 4; i++) '$i': Completer<void>()};
      final calls = <String, int>{};
      var active = 0;
      var maximum = 0;
      final batch = loading.load(
        [
          for (var i = 0; i < 4; i++)
            SourceReviewLoadItem(key: '$i', label: '$i', kind: 'provider-rule'),
        ],
        (key, progress) async {
          calls[key] = (calls[key] ?? 0) + 1;
          active++;
          if (active > maximum) maximum = active;
          try {
            await gates[key]!.future;
            progress(SourceReviewLoadPhase.parsing);
            if (key == '0' && calls[key] == 1) {
              throw StateError('synthetic failure');
            }
            return entry(key);
          } finally {
            active--;
          }
        },
      );
      expect(loading.settled, isFalse);
      expect(calls.keys, ['0', '1', '2']);
      expect(loading.items.last.phase, SourceReviewLoadPhase.queued);
      gates['0']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(loading.items.first.phase, SourceReviewLoadPhase.failed);
      expect(loading.settled, isFalse);
      expect(calls.keys, ['0', '1', '2', '3']);
      for (final gate in gates.values) {
        if (!gate.isCompleted) gate.complete();
      }
      await batch;
      expect(loading.ready, isFalse);
      expect(loading.settled, isTrue);
      expect(loading.items.first.phase, SourceReviewLoadPhase.failed);
      expect(loading.items.skip(1).every((item) => item.entry != null), isTrue);
      final retry = loading.retry('0');
      expect(loading.settled, isFalse);
      await retry;
      expect(loading.ready, isTrue);
      expect(calls, {'0': 2, '1': 1, '2': 1, '3': 1});
      expect(maximum, 3);
    },
  );

  test('replacing or closing a load ignores late completions', () async {
    final loading = SourceReviewLoading();
    final late = Completer<void>();
    final old = loading.load(
      [SourceReviewLoadItem(key: 'old', label: 'old', kind: 'provider-rule')],
      (key, progress) async {
        await late.future;
        progress(SourceReviewLoadPhase.parsing);
        return entry(key);
      },
    );
    await loading.load([
      SourceReviewLoadItem(key: 'new', label: 'new', kind: 'provider-rule'),
    ], (key, _) async => entry(key));
    expect(loading.ready, isTrue);
    late.complete();
    await old;
    await Future<void>.delayed(Duration.zero);
    expect(loading.items.single.key, 'new');
    loading.dispose();
  });
}
