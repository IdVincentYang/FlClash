import 'dart:convert';
import 'dart:io';

typedef ManagedTarget = ({String kind, String? group});
typedef ManagedDomainRoute = ({ManagedTarget target, String? dnsService});
typedef ManagedDomainRule = ({
  String id,
  String type,
  String value,
  ManagedDomainRoute route,
});
typedef ManagedIpRule = ({String id, String cidr, ManagedTarget target});
typedef ManagedDnsService = ({String protocol, String address, int port});
typedef ManagedProxy = ({
  String address,
  int port,
  bool udp,
  String? username,
  String? password,
});

final class ManagedPolicy {
  final List<ManagedDomainRule> domainRules;
  final ManagedDomainRoute domainDefault;
  final List<ManagedIpRule> ipRules;
  final ManagedTarget ipDefault;
  final Map<String, ManagedDnsService> dnsServices;
  final ManagedDnsService bootstrapDns;
  final Map<String, ManagedProxy> proxies;
  final Map<String, List<String>> groups;
  final int mixedPort;
  final int dnsPort;

  const ManagedPolicy._({
    required this.domainRules,
    required this.domainDefault,
    required this.ipRules,
    required this.ipDefault,
    required this.dnsServices,
    required this.bootstrapDns,
    required this.proxies,
    required this.groups,
    required this.mixedPort,
    required this.dnsPort,
  });

  factory ManagedPolicy.fromJson(Object? json) {
    final root = _Fields(json, 'policy', {
      'schemaVersion',
      'domainRules',
      'domainDefault',
      'ipRules',
      'ipDefault',
      'dnsServices',
      'bootstrapDns',
      'proxies',
      'groups',
      'listeners',
    });
    final version = root.required('schemaVersion');
    if (version is! int || version != 1) {
      _invalid('policy.schemaVersion', 'unsupported version');
    }
    final domains = <ManagedDomainRule>[];
    final domainIds = <String>{};
    for (final (index, value) in _list(root, 'domainRules').indexed) {
      final entry = _Fields(value, 'policy.domainRules[$index]', {
        'id',
        'type',
        'value',
        'target',
        'dnsService',
      });
      final id = _id(entry.required('id'), '${entry.path}.id');
      if (!domainIds.add(id)) _invalid('${entry.path}.id', 'duplicate ID');
      final type = entry.string('type');
      if (type != 'DOMAIN' && type != 'DOMAIN-SUFFIX') {
        _invalid('${entry.path}.type', 'unsupported domain condition');
      }
      domains.add((
        id: id,
        type: type,
        value: _domain(entry.string('value'), '${entry.path}.value'),
        route: _route(entry),
      ));
    }
    final addresses = <ManagedIpRule>[];
    final addressIds = <String>{};
    for (final (index, value) in _list(root, 'ipRules').indexed) {
      final entry = _Fields(value, 'policy.ipRules[$index]', {
        'id',
        'cidr',
        'target',
      });
      final id = _id(entry.required('id'), '${entry.path}.id');
      if (!addressIds.add(id)) _invalid('${entry.path}.id', 'duplicate ID');
      addresses.add((
        id: id,
        cidr: _cidr(entry.string('cidr'), '${entry.path}.cidr'),
        target: _target(entry.required('target'), '${entry.path}.target'),
      ));
    }
    final defaultRoute = _Fields(
      root.required('domainDefault'),
      'policy.domainDefault',
      {'target', 'dnsService'},
    );
    final listeners = _Fields(root.required('listeners'), 'policy.listeners', {
      'mixedPort',
      'dnsPort',
    });
    final mixedPort = listeners.port('mixedPort');
    final dnsPort = listeners.port('dnsPort');
    if (mixedPort == dnsPort) {
      _invalid(listeners.path, 'listener ports must differ');
    }
    return ManagedPolicy._(
      domainRules: List.unmodifiable(domains),
      domainDefault: _route(defaultRoute),
      ipRules: List.unmodifiable(addresses),
      ipDefault: _target(root.required('ipDefault'), 'policy.ipDefault'),
      dnsServices: _objects(root, 'dnsServices', _service),
      bootstrapDns: _service(
        root.required('bootstrapDns'),
        'policy.bootstrapDns',
      ),
      proxies: _objects(root, 'proxies', parseManagedProxy),
      groups: _objects(root, 'groups', parseManagedProxyGroup),
      mixedPort: mixedPort,
      dnsPort: dnsPort,
    );
  }
}

ManagedDomainRoute _route(_Fields entry) {
  final target = _target(entry.required('target'), '${entry.path}.target');
  final service = entry.values['dnsService'];
  if (target.kind == 'reject') {
    if (entry.values.containsKey('dnsService')) {
      _invalid(
        '${entry.path}.dnsService',
        'rejection cannot use a DNS service',
      );
    }
    return (target: target, dnsService: null);
  }
  return (target: target, dnsService: _id(service, '${entry.path}.dnsService'));
}

ManagedTarget _target(Object? value, String location) {
  final entry = _Fields(value, location, {'kind', 'group'});
  final kind = entry.string('kind');
  if (!{'direct', 'reject', 'proxy'}.contains(kind)) {
    _invalid('$location.kind', 'unsupported target');
  }
  if (kind == 'proxy') {
    return (kind: kind, group: _id(entry.required('group'), '$location.group'));
  }
  if (entry.values.containsKey('group')) {
    _invalid('$location.group', 'only a proxy target can name a group');
  }
  return (kind: kind, group: null);
}

ManagedDnsService _service(Object? value, String location) {
  final entry = _Fields(value, location, {'protocol', 'address', 'port'});
  final protocol = entry.string('protocol');
  if (!{'tls', 'udp', 'tcp'}.contains(protocol)) {
    _invalid(
      '$location.protocol',
      'unsupported DNS protocol (DoH is disabled)',
    );
  }
  final address = _address(entry.string('address'), '$location.address');
  final bytes = address.rawAddress;
  final local =
      address.isLoopback ||
      (bytes.length == 4 &&
          (bytes[0] == 10 ||
              (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
              (bytes[0] == 192 && bytes[1] == 168))) ||
      (bytes.length == 16 && bytes[0] & 0xfe == 0xfc);
  if (protocol != 'tls' && !local) {
    _invalid('$location.address', 'plaintext DNS requires a local address');
  }
  return (
    protocol: protocol,
    address: address.address,
    port: entry.port('port'),
  );
}

List<String> parseManagedProxyGroup(Object? value, String location) {
  if (value is! List || value.isEmpty) {
    _invalid(location, 'expected nonempty proxy member list');
  }
  final members = <String>[];
  for (final (index, member) in value.indexed) {
    final id = _id(member, '$location[$index]');
    if (members.contains(id)) _invalid(location, 'duplicate member');
    members.add(id);
  }
  return List<String>.unmodifiable(members);
}

ManagedProxy parseManagedProxy(Object? value, String location) {
  final entry = _Fields(value, location, {
    'type',
    'address',
    'port',
    'udp',
    'username',
    'password',
  });
  if (entry.string('type') != 'socks5') {
    _invalid('$location.type', 'only fixed SOCKS5 proxies are supported');
  }
  final udp = entry.required('udp');
  if (udp is! bool) _invalid('$location.udp', 'expected boolean');
  final hasUsername = entry.values.containsKey('username');
  final hasPassword = entry.values.containsKey('password');
  if (hasUsername != hasPassword) {
    _invalid(location, 'authentication must be supplied as a pair');
  }
  String? credential(String key) {
    if (!hasUsername) return null;
    final text = entry.string(key);
    final size = utf8.encode(text).length;
    if (size < 1 ||
        size > 255 ||
        text.runes.any(_control) ||
        utf8.decode(utf8.encode(text)) != text) {
      _invalid('$location.$key', 'invalid authentication text or byte length');
    }
    return text;
  }

  return (
    address: _address(entry.string('address'), '$location.address').address,
    port: entry.port('port'),
    udp: udp,
    username: credential('username'),
    password: credential('password'),
  );
}

bool _control(int rune) =>
    rune < 32 ||
    (rune >= 127 && rune <= 159) ||
    rune == 0x2028 ||
    rune == 0x2029;

InternetAddress _address(String text, String location) {
  final address = text.contains('%') ? null : InternetAddress.tryParse(text);
  if (address == null ||
      address.isMulticast ||
      address.rawAddress.every((b) => b == 0)) {
    _invalid(location, 'expected unicast IP address');
  }
  return address;
}

String _domain(String text, String location) {
  final domain = text.toLowerCase();
  final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  if (domain.length > 253 ||
      !domain.split('.').every(label.hasMatch) ||
      InternetAddress.tryParse(domain) != null) {
    _invalid(location, 'expected ASCII domain without wildcards');
  }
  return domain;
}

String _cidr(String text, String location) {
  final parts = text.split('/');
  if (parts.length != 2 || !RegExp(r'^\d{1,3}$').hasMatch(parts[1])) {
    _invalid(location, 'expected IP prefix');
  }
  final ip = InternetAddress.tryParse(parts[0]);
  final prefix = int.tryParse(parts[1]);
  if (ip == null ||
      parts[0].contains('%') ||
      prefix == null ||
      prefix < 0 ||
      prefix > ip.rawAddress.length * 8) {
    _invalid(location, 'invalid IP prefix');
  }
  final bytes = ip.rawAddress;
  for (var index = 0; index < bytes.length; index++) {
    final bits = (prefix - index * 8).clamp(0, 8);
    bytes[index] &= (0xff << (8 - bits)) & 0xff;
  }
  return '${InternetAddress.fromRawAddress(bytes).address}/$prefix';
}

String _id(Object? value, String location) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(value) ||
      {
        'DIRECT',
        'REJECT',
        'GLOBAL',
        'PASS',
        'REMATCH',
        'COMPATIBLE',
      }.contains(value.toUpperCase())) {
    _invalid(location, 'expected non-reserved stable ID');
  }
  return value;
}

List<dynamic> _list(_Fields entry, String key) {
  final value = entry.required(key);
  if (value is! List) _invalid('${entry.path}.$key', 'expected list');
  return value;
}

Map<String, T> _objects<T>(
  _Fields root,
  String key,
  T Function(Object?, String) parse,
) {
  final value = root.required(key);
  if (value is! Map) _invalid('${root.path}.$key', 'expected object');
  final result = <String, T>{};
  for (final item in value.entries) {
    final id = _id(item.key, '${root.path}.$key');
    result[id] = parse(item.value, '${root.path}.$key.$id');
  }
  return Map<String, T>.unmodifiable(result);
}

final class _Fields {
  final Map values;
  final String path;

  _Fields(Object? value, this.path, Set<String> allowed)
    : values = value is Map ? value : _invalid(path, 'expected object') {
    if (values.keys.any((key) => !allowed.contains(key))) {
      _invalid(path, 'unexpected field');
    }
  }

  Object? required(String key) {
    if (!values.containsKey(key)) _invalid('$path.$key', 'required field');
    return values[key];
  }

  String string(String key) {
    final value = required(key);
    if (value is! String) _invalid('$path.$key', 'expected string');
    return value;
  }

  int port(String key) {
    final value = required(key);
    if (value is! int || value < 1 || value > 65535) {
      _invalid('$path.$key', 'expected port from 1 to 65535');
    }
    return value;
  }
}

Never _invalid(String location, String reason) =>
    throw FormatException('$location: $reason');
