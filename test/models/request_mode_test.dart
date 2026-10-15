import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old object JSON defaults to Auto and unknown modes are rejected', () {
    const profile = Profile(id: 1, autoUpdateDuration: Duration.zero);
    final profileJson =
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>;
    profileJson.remove('requestMode');
    expect(Profile.fromJson(profileJson).requestMode, RequestMode.auto);
    profileJson['requestMode'] = 'unknown-strict-mode';
    expect(() => Profile.fromJson(profileJson), throwsArgumentError);
    final script = Script(
      id: 2,
      label: 'synthetic',
      lastUpdateTime: DateTime(2026),
    );
    final scriptJson = script.toJson()..remove('requestMode');
    expect(Script.fromJson(scriptJson).requestMode, RequestMode.auto);
    scriptJson['requestMode'] = 'unknown-strict-mode';
    expect(() => Script.fromJson(scriptJson), throwsArgumentError);
    final davJson = const DAVProps(
      uri: 'http://127.0.0.1',
      user: 'synthetic',
      password: 'synthetic',
      fileName: 'synthetic.zip',
    ).toJson()..remove('requestMode');
    expect(DAVProps.fromJson(davJson).requestMode, RequestMode.auto);
    davJson['requestMode'] = 'unknown-strict-mode';
    expect(() => DAVProps.fromJson(davJson), throwsArgumentError);
  });

  test(
    'schema 11 persists object route and rejects unknown database modes',
    () async {
      final db = Database(NativeDatabase.memory());
      addTearDown(db.close);
      const profile = Profile(
        id: 1,
        autoUpdateDuration: Duration.zero,
        requestMode: RequestMode.proxy,
        requestProxy: 'synthetic-node',
      );
      await db.profiles.put(profile.toCompanion());
      final saved = (await db.profilesDao.query().get()).single;
      expect(db.schemaVersion, 11);
      expect(saved.requestMode, RequestMode.proxy);
      expect(saved.requestProxy, 'synthetic-node');
      await db.customStatement(
        "UPDATE profiles SET request_mode = 'unknown-strict-mode'",
      );
      await expectLater(
        db.profilesDao.query().get(),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
