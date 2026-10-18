class ConfigFact {
  const ConfigFact({
    this.runtimeEpoch = '',
    this.version = 0,
    this.token = 0,
    this.owner = 0,
    this.inputId = '',
    this.yamlSha256 = '',
    this.profileId,
    this.profileName = '',
    this.phase = 'unknown',
    this.businessActive = false,
    this.replayEligible = false,
    this.policyVersion = 0,
    this.policySha256 = '',
    this.maintenanceProxy = '',
    this.mixedPort = 0,
    this.routeEpoch = 0,
    this.picksVersion = 0,
  });

  final String runtimeEpoch, inputId, yamlSha256, profileName, phase;
  final int version, token, owner;
  final int? profileId;
  final bool businessActive, replayEligible;
  final int policyVersion, mixedPort, routeEpoch, picksVersion;
  final String policySha256, maintenanceProxy;

  bool get isManaged => policyVersion != 0;

  Map<String, Object?> get fence => {
    'runtimeEpoch': runtimeEpoch,
    'version': version,
    'owner': owner,
    'token': token,
    'inputId': inputId,
    'routeEpoch': routeEpoch,
    'picksVersion': picksVersion,
  };

  factory ConfigFact.fromJson(Map<String, Object?> json) => ConfigFact(
    runtimeEpoch: json['runtimeEpoch'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 0,
    token: (json['token'] as num?)?.toInt() ?? 0,
    owner: (json['owner'] as num?)?.toInt() ?? 0,
    inputId: json['inputId'] as String? ?? '',
    yamlSha256: json['yamlSha256'] as String? ?? '',
    profileId: (json['profileId'] as num?)?.toInt(),
    profileName: json['profileName'] as String? ?? '',
    phase: json['phase'] as String? ?? 'unknown',
    businessActive: json['businessActive'] == true,
    replayEligible: json['replayEligible'] == true,
    policyVersion: (json['policyVersion'] as num?)?.toInt() ?? 0,
    policySha256: json['policySha256'] as String? ?? '',
    maintenanceProxy: json['maintenanceProxy'] as String? ?? '',
    mixedPort: (json['mixedPort'] as num?)?.toInt() ?? 0,
    routeEpoch: (json['routeEpoch'] as num?)?.toInt() ?? 0,
    picksVersion: (json['picksVersion'] as num?)?.toInt() ?? 0,
  );
}

class ConfigApplyResult {
  ConfigApplyResult.fromJson(Map<String, Object?> json)
    : status = json['status'] as String? ?? 'unknown',
      message = json['message'] as String? ?? '',
      receipt = Map.unmodifiable(
        Map<String, Object?>.from(json['receipt'] as Map? ?? const {}),
      ),
      fact = ConfigFact.fromJson(
        Map<String, Object?>.from(json['fact'] as Map? ?? const {}),
      );

  final String status, message;
  final Map<String, Object?> receipt;
  final ConfigFact fact;
  bool get succeeded => status == 'activated' || status == 'installedInactive';
}
