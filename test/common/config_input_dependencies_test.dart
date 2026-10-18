import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/config_input.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ConfigFact fact;
  late String id;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('accepted-dependencies-');
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'profileId': 1,
        'dependencies': ['profile:1', 'profile:2'],
      }),
    );
    id = sha256.convert(bytes).toString();
    final file = File('${root.path}/config-inputs/$id.json');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    fact = ConfigFact(
      runtimeEpoch: 'fixture',
      owner: 2,
      token: 3,
      inputId: id,
      profileId: 1,
      phase: 'ready',
    );
  });
  tearDown(() => root.delete(recursive: true));
  Future<Set<String>?> read({
    ConfigFact? accepted,
    Future<ConfigFact> Function()? fresh,
  }) => ConfigInput.acceptedDependencies(
    home: root.path,
    accepted: accepted ?? fact,
    readFact: fresh ?? () async => fact,
  );

  test('reads exact accepted manifest dependencies', () async {
    expect(await read(), {'profile:1', 'profile:2'});
  });
  test(
    'missing, hash-mismatched and oversized manifests are unknown, not empty',
    () async {
      final file = File('${root.path}/config-inputs/$id.json');
      await file.writeAsString('{}');
      expect(await read(), isNull);
      await file.writeAsBytes(List.filled(4 * 1024 * 1024 + 1, 32));
      expect(await read(), isNull);
      await file.delete();
      expect(await read(), isNull);
    },
  );
  test('rejects malformed input identifiers and pending inputs', () async {
    for (final value in ['../fixture', '0' * 63, 'g' * 64]) {
      final invalid = ConfigFact(inputId: value, phase: 'ready');
      expect(await read(accepted: invalid, fresh: () async => invalid), isNull);
    }
    final pending = ConfigFact(
      runtimeEpoch: 'fixture',
      owner: 2,
      token: 3,
      inputId: id,
      profileId: 1,
      phase: 'parsing',
    );
    expect(await read(accepted: pending, fresh: () async => pending), isNull);
  });
  for (final change in ['owner', 'input', 'token', 'epoch']) {
    test('rejects $change replacement during the read', () async {
      var calls = 0;
      expect(
        await read(
          fresh: () async {
            if (++calls == 1) return fact;
            return ConfigFact(
              runtimeEpoch: change == 'epoch' ? 'new' : 'fixture',
              owner: change == 'owner' ? 4 : 2,
              token: change == 'token' ? 4 : 3,
              inputId: change == 'input' ? 'f' * 64 : id,
              profileId: 1,
              phase: 'ready',
            );
          },
        ),
        isNull,
      );
    });
  }
  test(
    'rejects version, profile and dependency type mismatches despite a valid digest',
    () async {
      for (final manifest in [
        {
          'version': 2,
          'profileId': 1,
          'dependencies': ['profile:1'],
        },
        {
          'version': 1,
          'profileId': 2,
          'dependencies': ['profile:1'],
        },
        {
          'version': 1,
          'profileId': 1,
          'dependencies': [1],
        },
      ]) {
        final bytes = utf8.encode(jsonEncode(manifest));
        final hash = sha256.convert(bytes).toString();
        await File('${root.path}/config-inputs/$hash.json').writeAsBytes(bytes);
        final wrong = ConfigFact(
          runtimeEpoch: 'fixture',
          owner: 2,
          token: 3,
          inputId: hash,
          profileId: 1,
          phase: 'ready',
        );
        expect(await read(accepted: wrong, fresh: () async => wrong), isNull);
      }
    },
  );
}
