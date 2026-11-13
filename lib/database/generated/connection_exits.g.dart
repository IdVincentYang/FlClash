// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../connection_exits.dart';

// ignore_for_file: type=lint
class $ExitMeasurementsTable extends ExitMeasurements
    with TableInfo<$ExitMeasurementsTable, ExitMeasurement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExitMeasurementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityMeta = const VerificationMeta(
    'identity',
  );
  @override
  late final GeneratedColumn<String> identity = GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIpMeta = const VerificationMeta(
    'entryIp',
  );
  @override
  late final GeneratedColumn<String> entryIp = GeneratedColumn<String>(
    'entry_ip',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exitIpMeta = const VerificationMeta('exitIp');
  @override
  late final GeneratedColumn<String> exitIp = GeneratedColumn<String>(
    'exit_ip',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countryMeta = const VerificationMeta(
    'country',
  );
  @override
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
    'country',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    identity,
    entryIp,
    exitIp,
    country,
    checkedAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exit_measurements';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExitMeasurement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('entry_ip')) {
      context.handle(
        _entryIpMeta,
        entryIp.isAcceptableOrUnknown(data['entry_ip']!, _entryIpMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIpMeta);
    }
    if (data.containsKey('exit_ip')) {
      context.handle(
        _exitIpMeta,
        exitIp.isAcceptableOrUnknown(data['exit_ip']!, _exitIpMeta),
      );
    } else if (isInserting) {
      context.missing(_exitIpMeta);
    }
    if (data.containsKey('country')) {
      context.handle(
        _countryMeta,
        country.isAcceptableOrUnknown(data['country']!, _countryMeta),
      );
    } else if (isInserting) {
      context.missing(_countryMeta);
    }
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_checkedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identity, entryIp};
  @override
  ExitMeasurement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExitMeasurement(
      identity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      entryIp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_ip'],
      )!,
      exitIp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exit_ip'],
      )!,
      country: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country'],
      )!,
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $ExitMeasurementsTable createAlias(String alias) {
    return $ExitMeasurementsTable(attachedDatabase, alias);
  }
}

class ExitMeasurement extends DataClass implements Insertable<ExitMeasurement> {
  final String identity;
  final String entryIp;
  final String exitIp;
  final String country;
  final DateTime checkedAt;
  final DateTime expiresAt;
  const ExitMeasurement({
    required this.identity,
    required this.entryIp,
    required this.exitIp,
    required this.country,
    required this.checkedAt,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity'] = Variable<String>(identity);
    map['entry_ip'] = Variable<String>(entryIp);
    map['exit_ip'] = Variable<String>(exitIp);
    map['country'] = Variable<String>(country);
    map['checked_at'] = Variable<DateTime>(checkedAt);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    return map;
  }

  ExitMeasurementsCompanion toCompanion(bool nullToAbsent) {
    return ExitMeasurementsCompanion(
      identity: Value(identity),
      entryIp: Value(entryIp),
      exitIp: Value(exitIp),
      country: Value(country),
      checkedAt: Value(checkedAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory ExitMeasurement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExitMeasurement(
      identity: serializer.fromJson<String>(json['identity']),
      entryIp: serializer.fromJson<String>(json['entryIp']),
      exitIp: serializer.fromJson<String>(json['exitIp']),
      country: serializer.fromJson<String>(json['country']),
      checkedAt: serializer.fromJson<DateTime>(json['checkedAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identity': serializer.toJson<String>(identity),
      'entryIp': serializer.toJson<String>(entryIp),
      'exitIp': serializer.toJson<String>(exitIp),
      'country': serializer.toJson<String>(country),
      'checkedAt': serializer.toJson<DateTime>(checkedAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  ExitMeasurement copyWith({
    String? identity,
    String? entryIp,
    String? exitIp,
    String? country,
    DateTime? checkedAt,
    DateTime? expiresAt,
  }) => ExitMeasurement(
    identity: identity ?? this.identity,
    entryIp: entryIp ?? this.entryIp,
    exitIp: exitIp ?? this.exitIp,
    country: country ?? this.country,
    checkedAt: checkedAt ?? this.checkedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  ExitMeasurement copyWithCompanion(ExitMeasurementsCompanion data) {
    return ExitMeasurement(
      identity: data.identity.present ? data.identity.value : this.identity,
      entryIp: data.entryIp.present ? data.entryIp.value : this.entryIp,
      exitIp: data.exitIp.present ? data.exitIp.value : this.exitIp,
      country: data.country.present ? data.country.value : this.country,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExitMeasurement(')
          ..write('identity: $identity, ')
          ..write('entryIp: $entryIp, ')
          ..write('exitIp: $exitIp, ')
          ..write('country: $country, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(identity, entryIp, exitIp, country, checkedAt, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExitMeasurement &&
          other.identity == this.identity &&
          other.entryIp == this.entryIp &&
          other.exitIp == this.exitIp &&
          other.country == this.country &&
          other.checkedAt == this.checkedAt &&
          other.expiresAt == this.expiresAt);
}

class ExitMeasurementsCompanion extends UpdateCompanion<ExitMeasurement> {
  final Value<String> identity;
  final Value<String> entryIp;
  final Value<String> exitIp;
  final Value<String> country;
  final Value<DateTime> checkedAt;
  final Value<DateTime> expiresAt;
  final Value<int> rowid;
  const ExitMeasurementsCompanion({
    this.identity = const Value.absent(),
    this.entryIp = const Value.absent(),
    this.exitIp = const Value.absent(),
    this.country = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExitMeasurementsCompanion.insert({
    required String identity,
    required String entryIp,
    required String exitIp,
    required String country,
    required DateTime checkedAt,
    required DateTime expiresAt,
    this.rowid = const Value.absent(),
  }) : identity = Value(identity),
       entryIp = Value(entryIp),
       exitIp = Value(exitIp),
       country = Value(country),
       checkedAt = Value(checkedAt),
       expiresAt = Value(expiresAt);
  static Insertable<ExitMeasurement> custom({
    Expression<String>? identity,
    Expression<String>? entryIp,
    Expression<String>? exitIp,
    Expression<String>? country,
    Expression<DateTime>? checkedAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identity != null) 'identity': identity,
      if (entryIp != null) 'entry_ip': entryIp,
      if (exitIp != null) 'exit_ip': exitIp,
      if (country != null) 'country': country,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExitMeasurementsCompanion copyWith({
    Value<String>? identity,
    Value<String>? entryIp,
    Value<String>? exitIp,
    Value<String>? country,
    Value<DateTime>? checkedAt,
    Value<DateTime>? expiresAt,
    Value<int>? rowid,
  }) {
    return ExitMeasurementsCompanion(
      identity: identity ?? this.identity,
      entryIp: entryIp ?? this.entryIp,
      exitIp: exitIp ?? this.exitIp,
      country: country ?? this.country,
      checkedAt: checkedAt ?? this.checkedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identity.present) {
      map['identity'] = Variable<String>(identity.value);
    }
    if (entryIp.present) {
      map['entry_ip'] = Variable<String>(entryIp.value);
    }
    if (exitIp.present) {
      map['exit_ip'] = Variable<String>(exitIp.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExitMeasurementsCompanion(')
          ..write('identity: $identity, ')
          ..write('entryIp: $entryIp, ')
          ..write('exitIp: $exitIp, ')
          ..write('country: $country, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ExitCacheDatabase extends GeneratedDatabase {
  _$ExitCacheDatabase(QueryExecutor e) : super(e);
  $ExitCacheDatabaseManager get managers => $ExitCacheDatabaseManager(this);
  late final $ExitMeasurementsTable exitMeasurements = $ExitMeasurementsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [exitMeasurements];
}

typedef $$ExitMeasurementsTableCreateCompanionBuilder =
    ExitMeasurementsCompanion Function({
      required String identity,
      required String entryIp,
      required String exitIp,
      required String country,
      required DateTime checkedAt,
      required DateTime expiresAt,
      Value<int> rowid,
    });
typedef $$ExitMeasurementsTableUpdateCompanionBuilder =
    ExitMeasurementsCompanion Function({
      Value<String> identity,
      Value<String> entryIp,
      Value<String> exitIp,
      Value<String> country,
      Value<DateTime> checkedAt,
      Value<DateTime> expiresAt,
      Value<int> rowid,
    });

class $$ExitMeasurementsTableFilterComposer
    extends Composer<_$ExitCacheDatabase, $ExitMeasurementsTable> {
  $$ExitMeasurementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryIp => $composableBuilder(
    column: $table.entryIp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exitIp => $composableBuilder(
    column: $table.exitIp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExitMeasurementsTableOrderingComposer
    extends Composer<_$ExitCacheDatabase, $ExitMeasurementsTable> {
  $$ExitMeasurementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryIp => $composableBuilder(
    column: $table.entryIp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exitIp => $composableBuilder(
    column: $table.exitIp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExitMeasurementsTableAnnotationComposer
    extends Composer<_$ExitCacheDatabase, $ExitMeasurementsTable> {
  $$ExitMeasurementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  GeneratedColumn<String> get entryIp =>
      $composableBuilder(column: $table.entryIp, builder: (column) => column);

  GeneratedColumn<String> get exitIp =>
      $composableBuilder(column: $table.exitIp, builder: (column) => column);

  GeneratedColumn<String> get country =>
      $composableBuilder(column: $table.country, builder: (column) => column);

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$ExitMeasurementsTableTableManager
    extends
        RootTableManager<
          _$ExitCacheDatabase,
          $ExitMeasurementsTable,
          ExitMeasurement,
          $$ExitMeasurementsTableFilterComposer,
          $$ExitMeasurementsTableOrderingComposer,
          $$ExitMeasurementsTableAnnotationComposer,
          $$ExitMeasurementsTableCreateCompanionBuilder,
          $$ExitMeasurementsTableUpdateCompanionBuilder,
          (
            ExitMeasurement,
            BaseReferences<
              _$ExitCacheDatabase,
              $ExitMeasurementsTable,
              ExitMeasurement
            >,
          ),
          ExitMeasurement,
          PrefetchHooks Function()
        > {
  $$ExitMeasurementsTableTableManager(
    _$ExitCacheDatabase db,
    $ExitMeasurementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExitMeasurementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExitMeasurementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExitMeasurementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> identity = const Value.absent(),
                Value<String> entryIp = const Value.absent(),
                Value<String> exitIp = const Value.absent(),
                Value<String> country = const Value.absent(),
                Value<DateTime> checkedAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExitMeasurementsCompanion(
                identity: identity,
                entryIp: entryIp,
                exitIp: exitIp,
                country: country,
                checkedAt: checkedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String identity,
                required String entryIp,
                required String exitIp,
                required String country,
                required DateTime checkedAt,
                required DateTime expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => ExitMeasurementsCompanion.insert(
                identity: identity,
                entryIp: entryIp,
                exitIp: exitIp,
                country: country,
                checkedAt: checkedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExitMeasurementsTableProcessedTableManager =
    ProcessedTableManager<
      _$ExitCacheDatabase,
      $ExitMeasurementsTable,
      ExitMeasurement,
      $$ExitMeasurementsTableFilterComposer,
      $$ExitMeasurementsTableOrderingComposer,
      $$ExitMeasurementsTableAnnotationComposer,
      $$ExitMeasurementsTableCreateCompanionBuilder,
      $$ExitMeasurementsTableUpdateCompanionBuilder,
      (
        ExitMeasurement,
        BaseReferences<
          _$ExitCacheDatabase,
          $ExitMeasurementsTable,
          ExitMeasurement
        >,
      ),
      ExitMeasurement,
      PrefetchHooks Function()
    >;

class $ExitCacheDatabaseManager {
  final _$ExitCacheDatabase _db;
  $ExitCacheDatabaseManager(this._db);
  $$ExitMeasurementsTableTableManager get exitMeasurements =>
      $$ExitMeasurementsTableTableManager(_db, _db.exitMeasurements);
}
