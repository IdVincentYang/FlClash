import 'package:fl_clash/models/managed_policy.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

String managedProxyName(String id) => 'fc-managed-proxy-$id';

String managedGroupName(String id) => 'fc-managed-group-$id';

String compileManagedProfile(ManagedPolicy policy) {
  String targetName(ManagedTarget target, String location) {
    if (target.kind != 'proxy') return target.kind.toUpperCase();
    if (!policy.groups.containsKey(target.group)) {
      throw FormatException('$location: unknown proxy group');
    }
    return managedGroupName(target.group!);
  }

  for (final group in policy.groups.entries) {
    for (final member in group.value) {
      if (!policy.proxies.containsKey(member)) {
        throw FormatException(
          'policy.groups.${group.key}: unknown proxy member',
        );
      }
    }
  }
  String server(ManagedDnsService service, String target) {
    final host = service.address.contains(':')
        ? '[${service.address}]'
        : service.address;
    return '${service.protocol}://$host:${service.port}#$target';
  }

  String routeServer(ManagedDomainRoute route, String location) {
    if (route.target.kind == 'reject') return 'rcode://refused';
    final target = targetName(route.target, '$location.target');
    final service = policy.dnsServices[route.dnsService];
    if (service == null) {
      throw FormatException('$location.dnsService: unknown DNS service');
    }
    if (service.protocol == 'udp' &&
        route.target.kind == 'proxy' &&
        policy.groups[route.target.group]!.any(
          (id) => !policy.proxies[id]!.udp,
        )) {
      throw FormatException(
        '$location.dnsService: proxy group cannot carry UDP DNS',
      );
    }
    return server(service, target);
  }

  final providers = <String, Object?>{};
  final domainRules = <String>[];
  final dnsPolicy = <String, Object?>{};
  void provider(String name, String condition) {
    providers[name] = {
      'type': 'inline',
      'behavior': 'classical',
      'payload': [condition],
    };
  }

  // Separate providers preserve order; ordinary DNS keys are merged into a trie.
  for (final (index, entry) in policy.domainRules.indexed) {
    final location = 'policy.domainRules[$index]';
    final name = 'fc-managed-domain-${entry.id}';
    provider(name, '${entry.type},${entry.value}');
    domainRules.add(
      'RULE-SET,$name,${targetName(entry.route.target, '$location.target')}',
    );
    dnsPolicy['rule-set:$name'] = [routeServer(entry.route, location)];
  }
  // DirectResolver has its own fallback, so its policy must cover the default too.
  const defaultProvider = 'fc-managed-default-domain';
  provider(defaultProvider, 'DOMAIN-REGEX,^.+\$');
  final defaultServer = routeServer(
    policy.domainDefault,
    'policy.domainDefault',
  );
  dnsPolicy['rule-set:$defaultProvider'] = [defaultServer];
  domainRules.add(
    'MATCH,${targetName(policy.domainDefault.target, 'policy.domainDefault.target')}',
  );
  final bootstrap = server(policy.bootstrapDns, 'DIRECT');
  final config = <String, Object?>{
    'mixed-port': policy.mixedPort,
    'bind-address': '127.0.0.1',
    'allow-lan': false,
    'mode': 'rule',
    'ipv6': true,
    'log-level': 'error',
    'find-process-mode': 'off',
    'external-controller': '',
    'external-controller-tls': '',
    'external-controller-unix': '',
    'external-controller-pipe': '',
    'external-ui': '',
    'geo-auto-update': false,
    'tun': {'enable': false},
    'iptables': {'enable': false},
    'ntp': {'enable': false},
    'sniffer': {'enable': false},
    'hosts': <String, Object?>{},
    'profile': {'store-selected': false, 'store-fake-ip': false},
    'proxies': [
      for (final entry in policy.proxies.entries)
        {
          'name': managedProxyName(entry.key),
          'type': 'socks5',
          'server': entry.value.address,
          'port': entry.value.port,
          'udp': entry.value.udp,
          if (entry.value.username != null) 'username': entry.value.username,
          if (entry.value.password != null) 'password': entry.value.password,
        },
    ],
    'proxy-groups': [
      for (final entry in policy.groups.entries)
        {
          'name': managedGroupName(entry.key),
          'type': 'select',
          'proxies': entry.value.map(managedProxyName).toList(),
        },
    ],
    'rule-providers': providers,
    'rules': [
      'SUB-RULE,(DOMAIN-REGEX,^.+\$),fc-managed-domain',
      'SUB-RULE,(NOT,((DOMAIN-REGEX,^.+\$))),fc-managed-ip',
      'MATCH,REJECT',
    ],
    'sub-rules': {
      'fc-managed-domain': domainRules,
      'fc-managed-ip': [
        for (final (index, entry) in policy.ipRules.indexed)
          '${entry.cidr.contains(':') ? 'IP-CIDR6' : 'IP-CIDR'},${entry.cidr},${targetName(entry.target, 'policy.ipRules[$index].target')},no-resolve',
        'MATCH,${targetName(policy.ipDefault, 'policy.ipDefault')}',
      ],
    },
    'dns': {
      'enable': true,
      'listen': '127.0.0.1:${policy.dnsPort}',
      'ipv6': true,
      'enhanced-mode': 'redir-host',
      'respect-rules': false,
      'prefer-h3': false,
      'use-hosts': false,
      'use-system-hosts': false,
      'nameserver': [defaultServer],
      'nameserver-policy': dnsPolicy,
      'default-nameserver': [bootstrap],
      'direct-nameserver': [bootstrap],
      'direct-nameserver-follow-policy': true,
      'proxy-server-nameserver': [bootstrap],
      'proxy-server-nameserver-policy': <String, Object?>{},
      'fallback': <String>[],
      'fallback-filter': {
        'geoip': false,
        'geosite': <String>[],
        'ipcidr': <String>[],
        'domain': <String>[],
      },
    },
  };
  final yaml = YamlWriter().convert(config);
  final YamlMap decoded;
  try {
    decoded = loadYaml(yaml) as YamlMap;
  } on YamlException {
    throw const FormatException(
      'policy.proxies: text cannot be serialized as YAML',
    );
  }
  final proxies = decoded['proxies'] as YamlList;
  for (final (index, expected) in policy.proxies.values.indexed) {
    final actual = proxies[index] as YamlMap;
    if (actual['username'] != expected.username ||
        actual['password'] != expected.password) {
      throw const FormatException(
        'policy.proxies: authentication cannot be serialized losslessly',
      );
    }
  }
  return yaml;
}
