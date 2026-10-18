import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../models/config_state.dart';
import 'request.dart';

class ConfigInput {
  const ConfigInput(this.id, this.sources, this.markerName, this.home);
  final String id, markerName, home;
  final List<RequestSource> sources;

  Map<String, Object?> toRequest({
    int? requestId,
    bool active = false,
    Map<String, Object?>? expectedConfig,
  }) => {
    'inputId': id,
    'requestId': ?requestId,
    'active': active,
    'expectedConfig': ?expectedConfig,
    'source': {
      'client': sources.firstOrNull?.client ?? '',
      'dataset': sources.firstOrNull?.snapshot['dataset'] ?? 0,
      'sources': {
        for (final source in sources)
          source.key: source.snapshot['sourceRevision'] ?? 0,
      },
    },
  };

  Future<void> releaseMarker() async {
    final marker = File(path.join(home, 'config-inputs', markerName));
    if (await marker.exists()) await marker.delete();
  }

  static bool sameAcceptedInput(ConfigFact a, ConfigFact b) =>
      const {'ready', 'installed'}.contains(a.phase) &&
      const {'ready', 'installed'}.contains(b.phase) &&
      a.runtimeEpoch == b.runtimeEpoch &&
      a.owner == b.owner &&
      a.token == b.token &&
      a.inputId == b.inputId &&
      a.profileId == b.profileId;

  static Future<Set<String>?> acceptedDependencies({
    required String home,
    required ConfigFact accepted,
    required Future<ConfigFact> Function() readFact,
  }) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(accepted.inputId) ||
        !sameAcceptedInput(accepted, await readFact())) {
      return null;
    }
    try {
      final buffered = BytesBuilder(copy: false);
      await for (final chunk in File(
        path.join(home, 'config-inputs', '${accepted.inputId}.json'),
      ).openRead()) {
        if (buffered.length + chunk.length > 4 * 1024 * 1024) return null;
        buffered.add(chunk);
      }
      final bytes = buffered.takeBytes();
      if (sha256.convert(bytes).toString() != accepted.inputId) return null;
      final manifest = json.decode(utf8.decode(bytes));
      if (manifest is! Map ||
          manifest['version'] != 1 ||
          manifest['profileId'] != accepted.profileId ||
          manifest['dependencies'] is! List) {
        return null;
      }
      final dependencies = <String>{};
      for (final item in manifest['dependencies'] as List) {
        if (item is! String ||
            item.isEmpty ||
            item.length > 256 ||
            RegExp(r'[\x00-\x20\x7f]').hasMatch(item)) {
          return null;
        }
        dependencies.add(item);
      }
      return sameAcceptedInput(accepted, await readFact())
          ? Set.unmodifiable(dependencies)
          : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<ConfigInput> write({
    required String home,
    required String yaml,
    required String runtimeEpoch,
    required int profileId,
    required String profileName,
    required Map<String, String> selectedMap,
    required String testUrl,
    required List<RequestSource> sources,
    Map<String, Object?>? managedPolicy,
  }) async {
    if (yaml.trim().isEmpty) throw StateError('Configuration is empty');
    final directory = Directory(path.join(home, 'config-inputs'));
    await directory.create(recursive: true);
    final yamlBytes = utf8.encode(yaml);
    final yamlHash = sha256.convert(yamlBytes).toString();
    final manifest = utf8.encode(
      json.encode({
        'version': 1,
        'yamlSha256': yamlHash,
        'profileId': profileId,
        'profileName': profileName,
        'dependencies': [for (final source in sources) source.key],
        'selectedMap': Map<String, String>.of(selectedMap),
        'testUrl': testUrl,
        'acceptedOverrides': <String, Object?>{},
        'managedPolicy': ?managedPolicy,
      }),
    );
    final id = sha256.convert(manifest).toString();
    final random = Random.secure();
    final nonce = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final markerName = '$id.$nonce.candidate';
    final marker = File(path.join(directory.path, markerName));
    await marker.writeAsString(
      json.encode({
        'yamlSha256': yamlHash,
        'runtimeEpoch': runtimeEpoch,
        'client': sources.firstOrNull?.client ?? '',
      }),
      flush: true,
    );

    Future<void> writeObject(String name, List<int> bytes) async {
      final target = File(path.join(directory.path, name));
      if (await target.exists()) {
        if (sha256.convert(await target.readAsBytes()).toString() !=
            sha256.convert(bytes).toString()) {
          throw StateError('Configuration input digest mismatch');
        }
        return;
      }
      final temporary = await File(
        path.join(directory.path, '.$name.$nonce.pending'),
      ).writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }

    try {
      await writeObject('$yamlHash.yaml', yamlBytes);
      await writeObject('$id.json', manifest);
      return ConfigInput(id, List.unmodifiable(sources), markerName, home);
    } catch (_) {
      if (await marker.exists()) await marker.delete();
      rethrow;
    }
  }
}
