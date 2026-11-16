import 'package:fl_clash/common/request_versions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cold versions and all indices remain bounded beside active holders',
    () {
      final versions = RequestVersions();
      final hold = versions.retain('held');
      expect(versions.advance('held'), hold.version + 1);
      for (var i = 0; i < requestHistoryLimit * 3; i++) {
        versions.ensure('icon:localhost/$i');
        expect(versions.length, lessThanOrEqualTo(requestHistoryLimit + 1));
        expect(versions.coldLength, lessThanOrEqualTo(requestHistoryLimit));
      }
      expect(versions.read('held'), hold.version + 1);
      versions.clearCold();
      expect(versions.length, 1);
      hold.release();
      hold.release();
      versions.clearCold();
      expect(versions.length, 0);
      expect(versions.coldLength, 0);
      expect(versions.ensure('held'), greaterThan(hold.version + 2));
    },
  );

  test('cancelling absent keys creates no historical tombstones', () {
    final versions = RequestVersions();
    for (var i = 0; i < requestHistoryLimit * 3; i++) {
      versions.advance('retired:$i');
    }
    expect(versions.length, 0);
  });

  test('intent replacement and old release preserve the latest begin', () {
    final versions = RequestVersions();
    final hold = versions.retain('same');
    final first = versions.beginIntent('same');
    final second = versions.beginIntent('same');
    versions.endIntent('same', first);
    expect(versions.intentCurrent('same', first), isFalse);
    expect(versions.intentCurrent('same', second), isTrue);
    versions.advance('same', keepIntent: true);
    expect(versions.intentCurrent('same', second), isTrue);
    versions.advance('same');
    expect(versions.intentCurrent('same', second), isFalse);
    hold.release();
  });

  for (final action in ['birth', 'successor']) {
    test(
      'exhausted $action rejects old qualification but releases all state',
      () {
        final versions = RequestVersions(
          initialVersion: requestVersionLimit - 2,
        );
        final hold = versions.retain('last');
        expect(hold.version, requestVersionLimit);
        if (action == 'birth') {
          expect(versions.ensure('new'), 0);
        } else {
          expect(versions.advance('last'), 0);
        }
        expect(versions.exhausted, isTrue);
        expect(versions.read('last'), 0);
        expect(versions.ensure('retry'), 0);
        hold.release();
        versions.clearCold();
        expect(versions.length, 0);
        expect(versions.coldLength, 0);
      },
    );
  }
}
