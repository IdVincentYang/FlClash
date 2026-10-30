import 'dart:convert';

const bootRecoveryThreshold = 2;

enum AppExitReason {
  unknown,
  exitSelf,
  signaled,
  lowMemory,
  crash,
  crashNative,
  anr,
  initializationFailure,
  permissionChange,
  excessiveResourceUsage,
  userRequested,
  userStopped,
  dependencyDied,
  other,
  freezer,
  packageStateChange,
  packageUpdated;

  static AppExitReason fromCode(Object? code) => switch (code) {
    1 => exitSelf,
    2 => signaled,
    3 => lowMemory,
    4 => crash,
    5 => crashNative,
    6 => anr,
    7 => initializationFailure,
    8 => permissionChange,
    9 => excessiveResourceUsage,
    10 => userRequested,
    11 => userStopped,
    12 => dependencyDied,
    13 => other,
    14 => freezer,
    15 => packageStateChange,
    16 => packageUpdated,
    _ => unknown,
  };

  bool get isCrash => switch (this) {
    crash || crashNative || anr || initializationFailure => true,
    _ => false,
  };

  bool get isExternalStop => switch (this) {
    exitSelf ||
    signaled ||
    lowMemory ||
    permissionChange ||
    excessiveResourceUsage ||
    userRequested ||
    userStopped ||
    dependencyDied ||
    freezer ||
    packageStateChange ||
    packageUpdated => true,
    _ => false,
  };
}

class AppExitInfo {
  final AppExitReason reason;
  final int timestamp;
  final String? description;
  final int? pid;
  final String? processName;

  const AppExitInfo({
    required this.reason,
    required this.timestamp,
    this.description,
    this.pid,
    this.processName,
  });

  static AppExitInfo? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final timestamp = json['timestamp'];
    if (timestamp is! int || timestamp < 0) {
      return null;
    }
    final description = json['description'];
    return AppExitInfo(
      reason: AppExitReason.fromCode(json['reason']),
      timestamp: timestamp,
      description: description is String ? description : null,
      pid: json['pid'] is int ? json['pid'] as int : null,
      processName: json['processName'] is String
          ? json['processName'] as String
          : null,
    );
  }

  @override
  String toString() => 'AppExitInfo(${reason.name}, $timestamp)';
}

enum BootStage { starting, running, closed }

enum BootPhase { bootstrap, recovery, core, setup }

enum BootRecordHealth { missing, valid, damaged, newer }

class BootContext {
  final int pid;
  final String processName, processEpoch, attempt;
  final int processStartedAt;

  const BootContext({
    required this.pid,
    required this.processName,
    required this.processEpoch,
    required this.attempt,
    required this.processStartedAt,
  });

  static BootContext? fromJson(Map<String, Object?> value) {
    final pid = value['pid'];
    final name = value['processName'];
    final epoch = value['processEpoch'];
    final attempt = value['attempt'];
    final startedAt = value['processStartedAt'];
    if (pid is! int ||
        pid <= 0 ||
        name is! String ||
        name.isEmpty ||
        epoch is! String ||
        epoch.isEmpty ||
        attempt is! String ||
        attempt.isEmpty ||
        startedAt is! int ||
        startedAt <= 0) {
      return null;
    }
    return BootContext(
      pid: pid,
      processName: name,
      processEpoch: epoch,
      attempt: attempt,
      processStartedAt: startedAt,
    );
  }
}

class BootRecordRead {
  final BootRecordHealth health;
  final BootRecord? record;

  const BootRecordRead(this.health, [this.record]);

  factory BootRecordRead.decode(String? raw, {bool malformed = false}) {
    if (malformed || raw != null && utf8.encode(raw).length > 8192) {
      return const BootRecordRead(BootRecordHealth.damaged);
    }
    if (raw == null) return const BootRecordRead(BootRecordHealth.missing);
    try {
      final value = json.decode(raw);
      if (value is Map && value['version'] is int && value['version'] > 1) {
        return const BootRecordRead(BootRecordHealth.newer);
      }
      final record = BootRecord.fromJson(value);
      return record == null
          ? const BootRecordRead(BootRecordHealth.damaged)
          : BootRecordRead(BootRecordHealth.valid, record);
    } on FormatException {
      return const BootRecordRead(BootRecordHealth.damaged);
    }
  }
}

class BootRecord {
  final BootStage? stage;
  final int? profileId;
  final int startedAt;
  final int failureCount;
  final int? lastFailedProfileId;
  final int handledExitAt;
  final int version;
  final BootPhase phase;
  final int? pid;
  final String? processEpoch, attempt;

  const BootRecord({
    this.stage = BootStage.closed,
    this.profileId,
    this.startedAt = 0,
    this.failureCount = 0,
    this.lastFailedProfileId,
    this.handledExitAt = 0,
    this.version = 0,
    this.phase = BootPhase.bootstrap,
    this.pid,
    this.processEpoch,
    this.attempt,
  });

  static BootRecord? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final version = json['version'] ?? 0;
    if (version is! int || version < 0 || version > 1) return null;
    final rawStage = json['stage'];
    final stage = rawStage == null && version == 0
        ? BootStage.closed
        : BootStage.values.where((value) => value.name == rawStage).firstOrNull;
    final phase = version == 0
        ? BootPhase.bootstrap
        : BootPhase.values
              .where((value) => value.name == json['phase'])
              .firstOrNull;
    for (final key in ['startedAt', 'failureCount', 'handledExitAt']) {
      if (json[key] is! int || (json[key] as int) < 0) return null;
    }
    for (final key in ['profileId', 'lastFailedProfileId']) {
      if (json[key] != null && (json[key] is! int || (json[key] as int) < 0)) {
        return null;
      }
    }
    if (stage == null ||
        phase == null ||
        stage == BootStage.starting && json['startedAt'] == 0) {
      return null;
    }
    if (version == 1 &&
        (json['pid'] is! int ||
            (json['pid'] as int) <= 0 ||
            json['processEpoch'] is! String ||
            (json['processEpoch'] as String).isEmpty ||
            json['attempt'] is! String ||
            (json['attempt'] as String).isEmpty ||
            (json['failureCount'] as int) > bootRecoveryThreshold)) {
      return null;
    }
    return BootRecord(
      stage: stage,
      profileId: json['profileId'] as int?,
      startedAt: json['startedAt'] as int,
      failureCount: (json['failureCount'] as int).clamp(
        0,
        bootRecoveryThreshold,
      ),
      lastFailedProfileId: json['lastFailedProfileId'] as int?,
      handledExitAt: json['handledExitAt'] as int,
      version: version,
      phase: phase,
      pid: version == 1 ? json['pid'] as int : null,
      processEpoch: version == 1 ? json['processEpoch'] as String : null,
      attempt: version == 1 ? json['attempt'] as String : null,
    );
  }

  Map<String, Object?> toJson() => {
    'stage': stage?.name,
    'profileId': profileId,
    'startedAt': startedAt,
    'failureCount': failureCount,
    'lastFailedProfileId': lastFailedProfileId,
    'handledExitAt': handledExitAt,
    if (version != 0) ...{
      'version': version,
      'phase': phase.name,
      'pid': pid,
      'processEpoch': processEpoch,
      'attempt': attempt,
    },
  };

  BootRecord withStage(BootStage stage, {BootPhase? phase}) => BootRecord(
    stage: stage,
    phase: phase ?? this.phase,
    profileId: profileId,
    startedAt: startedAt,
    failureCount: stage == BootStage.starting ? failureCount : 0,
    lastFailedProfileId: lastFailedProfileId,
    handledExitAt: handledExitAt,
    version: version,
    pid: pid,
    processEpoch: processEpoch,
    attempt: attempt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BootRecord &&
          other.stage == stage &&
          other.profileId == profileId &&
          other.startedAt == startedAt &&
          other.failureCount == failureCount &&
          other.lastFailedProfileId == lastFailedProfileId &&
          other.handledExitAt == handledExitAt &&
          other.version == version &&
          other.phase == phase &&
          other.pid == pid &&
          other.processEpoch == processEpoch &&
          other.attempt == attempt;

  @override
  int get hashCode => Object.hash(
    stage,
    profileId,
    startedAt,
    failureCount,
    lastFailedProfileId,
    handledExitAt,
    version,
    phase,
    pid,
    processEpoch,
    attempt,
  );

  @override
  String toString() =>
      'BootRecord(${stage?.name ?? 'closed'}, profile: $profileId, '
      'failures: $failureCount)';
}

enum BootRecovery {
  none,
  skipAutoSetup,
  repeated,
  damagedRecord,
  newerRecord,
  unavailable,
}

class BootDecision {
  final BootRecovery recovery;
  final int failureCount;
  final int? failedProfileId;
  final bool crashConfirmed;
  final AppExitReason? exitReason;
  final BootPhase? failedPhase;
  final int handledExitAt;

  const BootDecision({
    this.recovery = BootRecovery.none,
    this.failureCount = 0,
    this.failedProfileId,
    this.crashConfirmed = false,
    this.exitReason,
    this.failedPhase,
    this.handledExitAt = 0,
  });

  bool get isDegraded => recovery != BootRecovery.none;

  @override
  String toString() =>
      'BootDecision(${recovery.name}, failures: $failureCount, '
      'profile: $failedProfileId, confirmed: $crashConfirmed, '
      'exit: ${exitReason?.name ?? '-'})';
}

BootDecision resolveBootDecision({
  required BootRecord? record,
  required AppExitInfo? exitInfo,
  required BootContext context,
  required int? profileId,
}) {
  if (record == null || record.stage != BootStage.starting) {
    return const BootDecision();
  }
  final sameProcess = record.processEpoch == context.processEpoch;
  final matchesLastRun =
      exitInfo != null &&
      !sameProcess &&
      record.pid != null &&
      exitInfo.pid == record.pid &&
      exitInfo.processName == context.processName &&
      exitInfo.timestamp > record.handledExitAt &&
      exitInfo.timestamp >= record.startedAt &&
      exitInfo.timestamp <= context.processStartedAt;
  final reason = matchesLastRun ? exitInfo.reason : null;
  if (reason != null && reason.isExternalStop) {
    return BootDecision(exitReason: reason, handledExitAt: exitInfo!.timestamp);
  }
  final failureCount = record.profileId != profileId
      ? 0
      : (record.failureCount + (sameProcess ? 0 : 1)).clamp(
          0,
          bootRecoveryThreshold,
        );
  return BootDecision(
    recovery: failureCount >= bootRecoveryThreshold
        ? BootRecovery.repeated
        : BootRecovery.skipAutoSetup,
    failureCount: failureCount,
    failedProfileId: record.profileId,
    crashConfirmed: reason?.isCrash ?? false,
    exitReason: reason,
    failedPhase: record.phase,
    handledExitAt: matchesLastRun ? exitInfo.timestamp : 0,
  );
}
