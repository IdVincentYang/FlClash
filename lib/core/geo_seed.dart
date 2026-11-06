import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class GeoSeedReference {
  static const manifestAsset = 'assets/data/geo_manifest.json';
  static const acceptedManifestDigest =
      'f721cff1e61a5b72c0d38ae57005d6064df33b7a2ba3dc8cdda7607b2ca85f30';

  static const _expected = {
    MMDB: (role: 'MMDB', asset: 'geoip.metadb', format: 'maxmind-meta-country'),
    ASN: (role: 'ASN', asset: 'GeoLite2-ASN.mmdb', format: 'maxmind-asn'),
    GEOIP: (role: 'GEOIP', asset: 'geoip.dat', format: 'v2ray-geoip'),
    GEOSITE: (role: 'GEOSITE', asset: 'geosite.dat', format: 'v2ray-geosite'),
  };
  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  final Map<String, ({int size, String digest})> _files;

  GeoSeedReference._(this._files);

  factory GeoSeedReference.fromAsset(ByteData data) {
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length > 64 << 10 ||
        sha256.convert(bytes).toString() != acceptedManifestDigest) {
      throw const FormatException('Geo seed manifest baseline mismatch');
    }
    return GeoSeedReference._parse(bytes);
  }

  @visibleForTesting
  factory GeoSeedReference.parseForTesting(List<int> bytes) =>
      GeoSeedReference._parse(bytes);

  static GeoSeedReference _parse(List<int> bytes) {
    dynamic value;
    try {
      value = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('Invalid Geo seed manifest JSON');
    }
    if (bytes.length > 64 << 10 ||
        value is! Map<String, dynamic> ||
        value['version'] is! int ||
        value['version'] != 1 ||
        !_hasKeys(value, const {
          'version',
          'publisher',
          'release_commit',
          'release_id',
          'published_at',
          'evidence',
          'history',
          'resources',
        }) ||
        value['resources'] is! List ||
        (value['resources'] as List).length != _expected.length) {
      throw const FormatException('Invalid Geo seed manifest schema');
    }
    final files = <String, ({int size, String digest})>{};
    for (final entry in value['resources'] as List) {
      if (entry is! Map<String, dynamic> ||
          !_hasKeys(entry, const {
            'role',
            'filename',
            'asset_name',
            'format',
            'asset_id',
            'size',
            'sha256',
            'source_url',
          })) {
        throw const FormatException('Invalid Geo seed resource schema');
      }
      final expected = _expected[entry['filename']];
      final size = entry['size'];
      final digest = entry['sha256'];
      if (expected == null ||
          files.containsKey(entry['filename']) ||
          entry['role'] != expected.role ||
          entry['asset_name'] != expected.asset ||
          entry['format'] != expected.format ||
          size is! int ||
          size <= 0 ||
          digest is! String ||
          !_digest.hasMatch(digest)) {
        throw const FormatException('Invalid Geo seed resource mapping');
      }
      files[entry['filename'] as String] = (size: size, digest: digest);
    }
    return GeoSeedReference._(Map.unmodifiable(files));
  }

  static bool _hasKeys(Map<String, dynamic> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  Uint8List verifiedBytes(String filename, ByteData data) {
    final expected = _files[filename];
    if (expected == null) {
      throw const FormatException('Unknown Geo seed resource');
    }
    if (data.lengthInBytes != expected.size) {
      throw FormatException('Geo seed length mismatch: $filename');
    }
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    if (sha256.convert(bytes).toString() != expected.digest) {
      throw FormatException('Geo seed digest mismatch: $filename');
    }
    return bytes;
  }
}
