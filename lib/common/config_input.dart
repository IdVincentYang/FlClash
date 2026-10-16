import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'request.dart';

class ConfigInput {
  const ConfigInput(this.id, this.sources, this.markerName, this.home);
  final String id, markerName, home;
  final List<RequestSource> sources;

  Map<String, Object?> toRequest({int? requestId, bool active = false}) => {
    'inputId': id,
    'requestId': ?requestId,
    'active': active,
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

  static Future<ConfigInput> write({
    required String home,
    required String yaml,
    required String runtimeEpoch,
    required int profileId,
    required String profileName,
    required Map<String, String> selectedMap,
    required String testUrl,
    required List<RequestSource> sources,
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
