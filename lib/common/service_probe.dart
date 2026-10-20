import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

const directOutbound = 'DIRECT';
const routedOutbound = '';

/// [id] must match the checker name registered in core/service_check.go.
enum ServiceTarget {
  google('google', 'Google', 'google'),
  github('github', 'GitHub', 'github'),
  youtube('youtube', 'YouTube', 'youtube'),
  chatgpt('chatgpt', 'ChatGPT', 'openai'),
  claude('claude', 'Claude', 'claude'),
  gemini('gemini', 'Gemini', 'gemini'),
  netflix('netflix', 'Netflix', 'netflix'),
  disneyPlus('disney-plus', 'Disney+', 'disneyplus'),
  primeVideo('prime-video', 'Prime Video', 'primevideo'),
  spotify('spotify', 'Spotify', 'spotify'),
  tiktok('tiktok', 'TikTok', 'tiktok'),
  bilibili('bilibili', 'bilibili', 'bilibili');

  const ServiceTarget(this.id, this.label, this.icon);

  final String id;
  final String label;
  final String icon;

  static ServiceTarget? byId(String id) {
    for (final target in values) {
      if (target.id == id) return target;
    }
    return null;
  }
}

enum ServiceProbePurpose { basic, advanced }

typedef ServiceProbeKey = ({ServiceTarget target, ServiceProbePurpose purpose});

extension ServiceProbeTargets on ServiceTarget {
  ServiceProbeKey get basic =>
      (target: this, purpose: ServiceProbePurpose.basic);
  ServiceProbeKey get advanced =>
      (target: this, purpose: ServiceProbePurpose.advanced);
  bool get hasAdvanced =>
      this != ServiceTarget.google && this != ServiceTarget.github;

  List<String> get advancedRecipients => switch (this) {
    ServiceTarget.chatgpt => [
      'ios.chat.openai.com',
      'chat.openai.com',
      'api.openai.com',
    ],
    ServiceTarget.netflix => ['api.fast.com', 'www.netflix.com'],
    ServiceTarget.disneyPlus => ['disney.api.edge.bamgrid.com'],
    ServiceTarget.bilibili => ['api.bilibili.com'],
    ServiceTarget.youtube => ['www.youtube.com'],
    ServiceTarget.claude => ['claude.ai'],
    ServiceTarget.gemini => ['gemini.google.com'],
    ServiceTarget.primeVideo => ['www.primevideo.com'],
    ServiceTarget.spotify => ['www.spotify.com'],
    ServiceTarget.tiktok => ['www.tiktok.com'],
    _ => [],
  };
}

enum ServiceProbeStatus {
  redirected('redirected'),
  httpResponse('http-response'),
  observed('observed'),
  available('available'),
  unavailable('unavailable'),
  restricted('restricted'),
  disallowedIsp('disallowed-isp'),
  blocked('blocked'),
  unsupportedRegion('unsupported-region'),
  originalsOnly('originals-only'),
  comingSoon('coming-soon'),
  timeout('timeout'),
  failed('failed');

  const ServiceProbeStatus(this.id);

  final String id;

  static ServiceProbeStatus byId(String id) {
    for (final status in values) {
      if (status.id == id) return status;
    }
    return ServiceProbeStatus.failed;
  }
}

List<ServiceTarget> orderServiceTargets(List<String> order) {
  return {
    for (final id in order) ?ServiceTarget.byId(id),
    ...ServiceTarget.values,
  }.toList();
}

class ServiceCheck {
  const ServiceCheck(
    this.status, {
    this.purpose = ServiceProbePurpose.basic,
    this.reason = '',
    this.httpStatus = 0,
    this.elapsed = 0,
    this.steps = const [],
    this.delay,
    this.chains = const [],
    this.region,
    this.checkedAt,
    this.coreEpoch = 0,
    this.picksVersion = 0,
  });

  factory ServiceCheck.of(ServiceCheckItem item) {
    return ServiceCheck(
      ServiceProbeStatus.byId(item.status),
      purpose: item.purpose == 'advanced'
          ? ServiceProbePurpose.advanced
          : ServiceProbePurpose.basic,
      reason: item.reason,
      httpStatus: item.httpStatus,
      elapsed: item.elapsed,
      steps: item.steps,
      delay: item.delay > 0 ? item.delay : null,
      chains: item.chains,
      region: item.region.isEmpty ? null : item.region,
      checkedAt: item.checkedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(item.checkedAt)
          : null,
      coreEpoch: item.coreEpoch,
      picksVersion: item.picksVersion,
    );
  }

  final ServiceProbeStatus status;
  final ServiceProbePurpose purpose;
  final String reason;
  final int httpStatus;
  final int elapsed;
  final List<ServiceCheckStep> steps;
  final int? delay;
  final List<String> chains;
  final String? region;
  final DateTime? checkedAt;
  final int coreEpoch;
  final int picksVersion;

  String? get node => chains.firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is ServiceCheck &&
      other.status == status &&
      other.purpose == purpose &&
      other.reason == reason &&
      other.httpStatus == httpStatus &&
      other.elapsed == elapsed &&
      listEquals(other.steps, steps) &&
      other.delay == delay &&
      listEquals(other.chains, chains) &&
      other.region == region &&
      other.checkedAt == checkedAt &&
      other.coreEpoch == coreEpoch &&
      other.picksVersion == picksVersion;

  @override
  int get hashCode => Object.hash(
    status,
    purpose,
    reason,
    httpStatus,
    elapsed,
    Object.hashAll(steps),
    delay,
    Object.hashAll(chains),
    region,
    checkedAt,
    coreEpoch,
    picksVersion,
  );

  @override
  String toString() =>
      'ServiceCheck(${status.id}, delay: $delay, node: $node, region: $region)';
}

/// An empty [proxyName] uses the accepted rules; no targets means no requests.
Future<Map<ServiceTarget, ServiceCheck>> checkServices(
  CoreController core, {
  String proxyName = '',
  ServiceProbePurpose purpose = ServiceProbePurpose.basic,
  List<ServiceTarget> targets = const [],
  Duration timeout = probeTimeoutDuration,
}) async {
  if (targets.isEmpty) return const {};
  final items = await core.serviceCheck(
    ServiceCheckParams(
      purpose: purpose.name,
      proxyName: proxyName,
      names: targets.map((target) => target.id).toList(),
      timeout: timeout.inMilliseconds,
    ),
  );
  return {
    for (final item in items)
      if (item.purpose == purpose.name &&
          targets.any((target) => target.id == item.name))
        ?ServiceTarget.byId(item.name): ServiceCheck.of(item),
  };
}

IpInfo Function(String) _json(IpInfo Function(Map<String, dynamic>) parse) {
  return (body) => parse(jsonDecode(body) as Map<String, dynamic>);
}

final Map<String, IpInfo Function(String)> ipInfoSources = {
  'https://www.cloudflare.com/cdn-cgi/trace': IpInfo.fromCloudflareTrace,
  'https://api.ip.sb/geoip': _json(IpInfo.fromIpSbJson),
  'https://ipinfo.io/json': _json(IpInfo.fromIpInfoIoJson),
  'https://ipwho.is': _json(IpInfo.fromIpWhoIsJson),
  'http://ip-api.com/json': _json(IpInfo.fromIpAPIJson),
  'https://get.geojs.io/v1/ip/geo.json': _json(IpInfo.fromGeoJsJson),
  'https://api.country.is': _json(IpInfo.fromCountryIsJson),
  'https://api.ipquery.io/?format=json': _json(IpInfo.fromIpQueryJson),
  'https://ident.me/json': _json(IpInfo.fromIdentMeJson),
};

/// Raw so the route stamp survives; [parseOutboundIp] reads the address.
Future<OutboundIpResult?> lookupOutboundIp(
  CoreController core,
  String proxyName, {
  Duration timeout = outboundIpTimeoutDuration,
}) {
  return core.outboundIp(
    OutboundIpParams(
      proxyName: proxyName,
      urls: ipInfoSources.keys.toList(),
      timeout: timeout.inMilliseconds,
    ),
  );
}

IpInfo? parseOutboundIp(OutboundIpResult? result) {
  if (result == null || result.error != null || result.body.isEmpty) {
    return null;
  }
  final parse = ipInfoSources[result.url];
  if (parse == null) return null;
  try {
    return parse(result.body);
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
