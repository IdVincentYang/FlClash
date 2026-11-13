import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/database/connection_exits.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final checked = DateTime.utc(2026, 11, 13, 12);
  IpInfo value({DateTime? time, String country = 'HK'}) =>
      IpInfo(ip: '1.1.1.1', countryCode: country, checkedAt: time ?? checked);

  test(
    'a real SQLite file survives closing and reopening for seven days',
    () async {
      final directory = await Directory.systemTemp.createTemp('exit-cache-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final first = ExitCacheDatabase(NativeDatabase.createInBackground(file));
      await first.save('identity', '8.8.8.8', value());
      await first.close();
      final reopened = ExitCacheDatabase(
        NativeDatabase.createInBackground(file),
      );
      addTearDown(reopened.close);
      expect(
        await reopened.latest(
          'identity',
          checked.add(const Duration(days: 7) - const Duration(seconds: 1)),
        ),
        value(),
      );
      expect(
        await reopened.latest('identity', checked.add(const Duration(days: 7))),
        isNull,
      );
    },
  );

  test(
    'entry IP and connection identity isolate shared-entry accounts',
    () async {
      final db = ExitCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.save('one', '8.8.8.8', value());
      await db.save('two', '8.8.8.8', value(country: 'TW'));
      expect((await db.latest('one', checked))?.countryCode, 'HK');
      expect((await db.latest('two', checked))?.countryCode, 'TW');
      expect(
        (await db.select(db.exitMeasurements).get())
            .map((row) => row.entryIp)
            .toSet(),
        {'8.8.8.8'},
      );
    },
  );

  test(
    'cleanup coalesces and deletes expired or future records only',
    () async {
      final db = ExitCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.save(
        'expired',
        '8.8.8.8',
        value(time: checked.subtract(const Duration(days: 7))),
      );
      await db.save('valid', '8.8.8.8', value());
      await db.save(
        'future',
        '8.8.8.8',
        value(time: checked.add(const Duration(days: 1))),
      );
      final first = db.cleanExpired(checked);
      expect(identical(first, db.cleanExpired(checked)), true);
      await first;
      expect(
        (await db.select(db.exitMeasurements).get()).map((row) => row.identity),
        ['valid'],
      );
    },
  );

  test(
    'successful refresh replaces one measurement without clearing others',
    () async {
      final db = ExitCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.save('one', '8.8.8.8', value());
      await db.save('two', '9.9.9.9', value());
      await db.save('one', '8.8.8.8', value(country: 'MO'));
      expect((await db.latest('one', checked))?.countryCode, 'MO');
      expect((await db.latest('two', checked))?.countryCode, 'HK');
    },
  );
  test(
    'an older completion cannot overwrite a newer stored measurement',
    () async {
      final db = ExitCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final latest = value(
        time: checked.add(const Duration(seconds: 10)),
        country: 'TW',
      );
      await db.save('one', '8.8.8.8', latest);
      await db.save('one', '8.8.8.8', value());
      expect(await db.latest('one', latest.checkedAt!), latest);
    },
  );
  test(
    'the newest valid measurement is shared across a node entry pool',
    () async {
      final db = ExitCacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.save('one', '8.8.8.8', value());
      final newer = value(
        time: checked.add(const Duration(seconds: 10)),
        country: 'TW',
      );
      await db.save('one', '9.9.9.9', newer);
      expect(await db.latest('one', newer.checkedAt!), newer);
      expect(
        (await db.select(db.exitMeasurements).get())
            .map((row) => row.entryIp)
            .toSet(),
        {'8.8.8.8', '9.9.9.9'},
      );
      expect(await db.latest('another-account', newer.checkedAt!), isNull);
    },
  );
}
