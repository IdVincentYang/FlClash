import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/models/models.dart';
import 'package:path/path.dart' as p;

part 'generated/connection_exits.g.dart';

class ExitMeasurements extends Table {
  TextColumn get identity => text()();
  TextColumn get entryIp => text()();
  TextColumn get exitIp => text()();
  TextColumn get country => text()();
  DateTimeColumn get checkedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {identity, entryIp};
}

@DriftDatabase(tables: [ExitMeasurements])
class ExitCacheDatabase extends _$ExitCacheDatabase {
  ExitCacheDatabase([QueryExecutor? executor])
    : super(
        executor ??
            LazyDatabase(() async {
              final file = File(
                p.join(await appPath.homeDirPath, 'connection-exits.sqlite'),
              );
              return NativeDatabase.createInBackground(file);
            }),
      );

  static const lifetime = Duration(days: 7);
  static const capacity = 256;
  Future<void>? _cleaning;

  @override
  int get schemaVersion => 1;

  Future<IpInfo?> lookup(String identity, String entryIp, DateTime now) async {
    final row =
        await (select(exitMeasurements)..where(
              (row) =>
                  row.identity.equals(identity) &
                  row.entryIp.equals(entryIp) &
                  row.expiresAt.isBiggerThanValue(now) &
                  row.checkedAt.isSmallerOrEqualValue(now),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : IpInfo(
            ip: row.exitIp,
            countryCode: row.country,
            checkedAt: row.checkedAt.toUtc(),
          );
  }

  Future<void> save(String identity, String entryIp, IpInfo value) async {
    final checkedAt = value.checkedAt!.toUtc();
    await transaction(() async {
      final record = ExitMeasurementsCompanion.insert(
        identity: identity,
        entryIp: entryIp,
        exitIp: value.ip,
        country: value.countryCode,
        checkedAt: checkedAt,
        expiresAt: checkedAt.add(lifetime),
      );
      await into(exitMeasurements).insert(
        record,
        onConflict: DoUpdate(
          (old) => record,
          where: (old) => old.checkedAt.isSmallerOrEqualValue(checkedAt),
        ),
      );
      await _trim();
    });
  }

  Future<void> cleanExpired(DateTime now) =>
      _cleaning ??= transaction(() async {
        await (delete(exitMeasurements)..where(
              (row) =>
                  row.expiresAt.isSmallerOrEqualValue(now) |
                  row.checkedAt.isBiggerThanValue(now),
            ))
            .go();
        await _trim();
      }).whenComplete(() => _cleaning = null);

  Future<void> _trim() => customStatement(
    'DELETE FROM exit_measurements WHERE rowid IN '
    '(SELECT rowid FROM exit_measurements '
    'ORDER BY checked_at DESC, identity, entry_ip LIMIT -1 OFFSET $capacity)',
  );
}
