part of 'database.dart';

@DataClassName('RawRule')
@TableIndex(name: 'idx_rule_target', columns: {#ruleTarget})
class Rules extends Table {
  @override
  String get tableName => 'rules';

  IntColumn get id => integer()();

  TextColumn get ruleAction => textEnum<RuleAction>()();

  TextColumn get content => text().nullable()();

  TextColumn get ruleTarget => text().nullable()();

  TextColumn get ruleProvider => text().nullable()();

  TextColumn get subRule => text().nullable()();

  BoolColumn get noResolve => boolean().withDefault(const Constant(false))();

  BoolColumn get src => boolean().withDefault(const Constant(false))();

  TextColumn get hostBinding => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftAccessor(tables: [Rules, ProfileRuleLinks])
class RulesDao extends DatabaseAccessor<Database> with _$RulesDaoMixin {
  RulesDao(super.attachedDatabase);

  Future<List<Rule>> hostRules() async {
    final records = await select(rules).get();
    final links = await select(profileRuleLinks).get();
    final result = <Rule>[];
    for (final row in records) {
      final rule = row.toRule();
      final disabled = [
        for (final link in links)
          if (link.ruleId == row.id &&
              link.scene == RuleScene.disabled &&
              link.profileId != null)
            link.profileId!,
      ];
      if (rule.hostBinding != null) {
        result.add(
          rule.copyWith(
            hostBinding: rule.hostBinding!.copyWith(disabledProfiles: disabled),
          ),
        );
      } else if (!rule.src &&
          const {
            RuleAction.DOMAIN,
            RuleAction.IP_CIDR,
            RuleAction.IP_CIDR6,
          }.contains(rule.ruleAction)) {
        for (final link in links.where(
          (l) =>
              l.ruleId == row.id &&
              (l.profileId == null || l.scene == RuleScene.added),
        )) {
          result.add(
            rule.copyWith(
              hostBinding: HostRuleBinding(
                profileId: link.profileId,
                legacy: true,
                disabledProfiles: disabled,
              ),
            ),
          );
        }
      }
    }
    return result;
  }

  Selectable<Rule> queryGlobalAddedRules() {
    return _query();
  }

  Selectable<Rule> queryProfileAddedRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.added);
  }

  Selectable<Rule> queryProfileDisabledRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.disabled);
  }

  Selectable<Rule> queryProfileCustomRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.custom);
  }

  Selectable<int> profileCustomRulesCount(int profileId) {
    final query = _getSelectStatement(
      profileId: profileId,
      scene: RuleScene.custom,
    );
    return query.count;
  }

  Selectable<Rule> queryAddedRules(int profileId) {
    final disabledIdsQuery = selectOnly(profileRuleLinks)
      ..addColumns([profileRuleLinks.ruleId])
      ..where(
        profileRuleLinks.profileId.equals(profileId) &
            profileRuleLinks.scene.equalsValue(RuleScene.disabled),
      );

    final query = select(rules).join([
      innerJoin(profileRuleLinks, profileRuleLinks.ruleId.equalsExp(rules.id)),
    ]);

    query.where(
      (profileRuleLinks.profileId.isNull() |
              (profileRuleLinks.profileId.equals(profileId) &
                  profileRuleLinks.scene.equalsValue(RuleScene.added))) &
          profileRuleLinks.ruleId.isNotInQuery(disabledIdsQuery),
    );
    query.where(rules.hostBinding.isNull());

    query.orderBy([
      OrderingTerm.asc(
        profileRuleLinks.profileId.isNull().caseMatch<int>(
          when: {const Constant(true): const Constant(1)},
          orElse: const Constant(0),
        ),
      ),
      OrderingTerm.asc(profileRuleLinks.order),
    ]);

    return query.map((row) {
      final ruleData = row.readTable(rules);
      final order = row.read(profileRuleLinks.order);
      return ruleData.toRule(order);
    });
  }

  Future<void> resetOrders() async {
    final stmt = profileRuleLinks.select();

    stmt.orderBy([
      (t) => OrderingTerm.asc(t.scene),
      (t) => OrderingTerm.desc(t.order),
      (t) => OrderingTerm.desc(t.id),
    ]);

    final links = await stmt.map((item) => item.toLink()).get();
    final keys = indexing.generateNKeys(links.length);
    await batch((b) {
      b.insertAllOnConflictUpdate(
        profileRuleLinks,
        links.mapIndexed((index, item) => item.toCompanion(keys[index])),
      );
    });
  }

  void _putRulesWithBatch(Batch batch, Iterable<Rule> rules) {
    batch.insertAllOnConflictUpdate(
      this.rules,
      rules.map((item) => item.toCompanion()),
    );
  }

  void _putLinksWithBatch(Batch batch, Iterable<ProfileRuleLink> links) {
    final keys = indexing.generateNKeys(links.length);
    batch.insertAllOnConflictUpdate(
      profileRuleLinks,
      links.mapIndexed((index, item) => item.toCompanion(keys[index])),
    );
  }

  void mergeWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<ProfileRuleLink> links,
  ) {
    _putRulesWithBatch(batch, rules);
    _putLinksWithBatch(batch, links);
  }

  void restoreWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<ProfileRuleLink> links,
  ) {
    batch.deleteAll(profileRuleLinks);
    batch.deleteAll(this.rules);
    mergeWithBatch(batch, rules, links);
  }

  Future<void> delRules(Iterable<int> ruleIds) {
    return _delAll(ruleIds);
  }

  Future<void> putGlobalRule(Rule rule) {
    return _put(rule);
  }

  Future<void> putProfileAddedRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.added);
  }

  Future<void> putProfileCustomRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.custom);
  }

  Future<void> putProfileDisabledRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.disabled);
  }

  void setCustomRulesWithBatch(int profileId, Batch b, Iterable<Rule> rules) {
    _setWithBatch(b, rules, profileId: profileId, scene: RuleScene.custom);
  }

  Future<void> _touchHost(int ruleId) async {
    final row = await (select(
      rules,
    )..where((t) => t.id.equals(ruleId))).getSingleOrNull();
    if (row?.hostBinding != null) {
      await attachedDatabase.writeApplicationRouting(
        await attachedDatabase.readApplicationRouting(),
      );
    }
  }

  Future<int> putDisabledLink(int profileId, int ruleId) =>
      transaction(() async {
        final result = await profileRuleLinks.insertOnConflictUpdate(
          ProfileRuleLink(
            ruleId: ruleId,
            profileId: profileId,
            scene: RuleScene.disabled,
          ).toCompanion(),
        );
        await _touchHost(ruleId);
        return result;
      });

  Future<bool> delDisabledLink(int profileId, int ruleId) =>
      transaction(() async {
        final result = await profileRuleLinks.deleteOne(
          ProfileRuleLink(
            profileId: profileId,
            ruleId: ruleId,
            scene: RuleScene.disabled,
          ).toCompanion(),
        );
        if (result) await _touchHost(ruleId);
        return result;
      });

  Future<int> orderGlobalRule({
    required int ruleId,
    required String order,
  }) async {
    return _order(ruleId: ruleId, order: order);
  }

  Future<int> orderProfileAddedRule(
    int profileId, {
    required int ruleId,
    required String order,
  }) async {
    return _order(
      ruleId: ruleId,
      order: order,
      profileId: profileId,
      scene: RuleScene.added,
    );
  }

  Future<int> orderProfileCustomRule(
    int profileId, {
    required int ruleId,
    required String order,
  }) async {
    return _order(
      ruleId: ruleId,
      order: order,
      profileId: profileId,
      scene: RuleScene.custom,
    );
  }

  Future<int> renameCustomRuleTarget(
    int profileId, {
    required String oldName,
    required String newName,
  }) {
    final stmt = rules.update()
      ..where((t) => t.ruleTarget.equals(oldName))
      ..where(
        (t) => t.id.isInQuery(
          selectOnly(profileRuleLinks)
            ..addColumns([profileRuleLinks.ruleId])
            ..where(
              profileRuleLinks.profileId.equals(profileId) &
                  profileRuleLinks.scene.equalsValue(RuleScene.custom),
            ),
        ),
      );
    return stmt.write(RulesCompanion(ruleTarget: Value(newName)));
  }

  Future<int> renameCustomRuleProvider(
    Iterable<int> profileIds, {
    required String oldName,
    required String newName,
  }) async {
    if (profileIds.isEmpty) {
      return 0;
    }
    final stmt = rules.update()
      ..where(
        (t) =>
            t.ruleAction.equalsValue(RuleAction.RULE_SET) &
            t.ruleProvider.equals(oldName),
      )
      ..where(
        (t) => t.id.isInQuery(
          selectOnly(profileRuleLinks)
            ..addColumns([profileRuleLinks.ruleId])
            ..where(
              profileRuleLinks.profileId.isIn(profileIds) &
                  profileRuleLinks.scene.equalsValue(RuleScene.custom),
            ),
        ),
      );
    return stmt.write(RulesCompanion(ruleProvider: Value(newName)));
  }

  Future<Set<int>> profileIdsUsingCustomRuleProvider(String provider) async {
    final query =
        selectOnly(rules, distinct: true).join([
            innerJoin(
              profileRuleLinks,
              profileRuleLinks.ruleId.equalsExp(rules.id),
              useColumns: false,
            ),
          ])
          ..addColumns([profileRuleLinks.profileId])
          ..where(
            rules.ruleAction.equalsValue(RuleAction.RULE_SET) &
                rules.ruleProvider.equals(provider) &
                profileRuleLinks.scene.equalsValue(RuleScene.custom) &
                profileRuleLinks.profileId.isNotNull(),
          );
    return {
      for (final row in await query.get())
        row.read(profileRuleLinks.profileId)!,
    };
  }

  JoinedSelectStatement<HasResultSet, dynamic> _getSelectStatement({
    int? profileId,
    RuleScene? scene,
  }) {
    final query = select(rules).join([
      innerJoin(profileRuleLinks, profileRuleLinks.ruleId.equalsExp(rules.id)),
    ]);

    query.where(
      profileId == null
          ? profileRuleLinks.profileId.isNull()
          : profileRuleLinks.profileId.equals(profileId) &
                profileRuleLinks.scene.equalsValue(scene),
    );

    query.orderBy([OrderingTerm.asc(profileRuleLinks.order)]);

    return query;
  }

  Selectable<Rule> _query({int? profileId, RuleScene? scene}) {
    final query = _getSelectStatement(profileId: profileId, scene: scene);

    return query.map((row) {
      return row.readTable(rules).toRule(row.read(profileRuleLinks.order));
    });
  }

  Future<int> _order({
    required int ruleId,
    required String order,
    int? profileId,
    RuleScene? scene,
  }) async {
    final stmt = profileRuleLinks.update();
    stmt.where((t) {
      return (profileId == null
              ? t.profileId.isNull()
              : t.profileId.equals(profileId)) &
          t.ruleId.equals(ruleId) &
          t.scene.equalsValue(scene);
    });
    return stmt.write(ProfileRuleLinksCompanion(order: Value(order)));
  }

  Future<int> _put(Rule rule, {int? profileId, RuleScene? scene}) async {
    return transaction(() async {
      final row = await rules.insertOnConflictUpdate(rule.toCompanion());
      if (row == 0) {
        return 0;
      }
      final linked = await profileRuleLinks.insertOnConflictUpdate(
        ProfileRuleLink(
          ruleId: rule.id,
          profileId: profileId,
          scene: scene,
          order: rule.order,
        ).toCompanion(),
      );
      if (rule.hostBinding != null) {
        await attachedDatabase.writeApplicationRouting(
          await attachedDatabase.readApplicationRouting(),
        );
      }
      return linked;
    });
  }

  Future<void> _delAll(Iterable<int> ruleIds) {
    final ids = ruleIds.toSet();
    return transaction(() async {
      final hasHost =
          (await (select(rules)
                    ..where((t) => t.id.isIn(ids) & t.hostBinding.isNotNull()))
                  .get())
              .isNotEmpty;
      await batch((b) {
        rules.deleteInChunks(b, ids, (t, chunk) => t.id.isIn(chunk));
      });
      if (hasHost) {
        await attachedDatabase.writeApplicationRouting(
          await attachedDatabase.readApplicationRouting(),
        );
      }
    });
  }

  Future<void> delUnlinkedRules() {
    return rules.remove(_isUnlinked);
  }

  Expression<bool> _isUnlinked(Rules rule) {
    final linkedIds = selectOnly(profileRuleLinks)
      ..addColumns([profileRuleLinks.ruleId]);
    return rule.id.isNotInQuery(linkedIds);
  }

  void _setWithBatch(
    Batch b,
    Iterable<Rule> rules, {
    int? profileId,
    RuleScene? scene,
  }) async {
    b.insertAllOnConflictUpdate(
      this.rules,
      rules.map((item) => item.toCompanion()),
    );

    b.deleteWhere(
      profileRuleLinks,
      (t) =>
          (profileId == null
              ? t.profileId.isNull()
              : t.profileId.equals(profileId)) &
          (scene == null ? const Constant(true) : t.scene.equalsValue(scene)),
    );

    final keys = indexing.generateNKeys(rules.length);

    b.insertAllOnConflictUpdate(
      profileRuleLinks,
      rules.mapIndexed(
        (index, item) => ProfileRuleLink(
          ruleId: item.id,
          profileId: profileId,
          scene: scene,
        ).toCompanion(keys[index]),
      ),
    );

    b.deleteWhere(this.rules, _isUnlinked);
  }
}

extension RawRuleExt on RawRule {
  Rule toRule([String? order]) {
    return Rule(
      id: id,
      ruleAction: ruleAction,
      content: content,
      ruleTarget: ruleTarget,
      ruleProvider: ruleProvider,
      subRule: subRule,
      noResolve: noResolve,
      src: src,
      order: order,
      hostBinding: hostBinding == null
          ? null
          : HostRuleBinding.fromJson(
              Map<String, dynamic>.from(jsonDecode(hostBinding!) as Map),
            ),
    );
  }
}

extension RulesCompanionExt on Rule {
  RulesCompanion toCompanion() {
    return RulesCompanion.insert(
      id: Value(id),
      ruleAction: ruleAction,
      content: Value(content),
      ruleTarget: Value(ruleTarget),
      ruleProvider: Value(ruleProvider),
      subRule: Value(subRule),
      noResolve: Value(noResolve),
      src: Value(src),
      hostBinding: Value(hostBinding == null ? null : jsonEncode(hostBinding)),
    );
  }
}
