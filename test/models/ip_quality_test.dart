import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classification preserves unknown fields and observation identity', () {
    const value = IpQuality(ip: '1.1.1.1', source: IpQualitySource.proxyCheck);
    expect(value.type, isNull);
    expect(value.isProxy, isNull);
    expect(value.checkedAt, isNull);
    final checked = value.copyWith(
      type: IpType.hosting,
      isProxy: false,
      checkedAt: DateTime(2026),
    );
    expect(checked.ip, value.ip);
    expect(checked.source, value.source);
    expect(checked.isProxy, isFalse);
  });
}
