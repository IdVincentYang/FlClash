import 'package:fl_clash/common/android_service_state.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const running = <String, Object?>{
    'phase': 'started',
    'intentRunning': true,
    'paused': false,
    'reason': 'none',
    'serviceId': 'owned-service',
    'protectPhase': 'ready',
    'protectGeneration': 4,
  };
  const active = ConfigFact(phase: 'ready', businessActive: true);

  test('installed configuration is not an active VPN without both owners', () {
    expect(
      androidServiceStatus(running, const ConfigFact(phase: 'ready')),
      AndroidServiceStatus.unavailable,
    );
    expect(
      androidServiceStatus({...running, 'serviceId': ''}, active),
      AndroidServiceStatus.unavailable,
    );
    expect(
      androidServiceStatus(running, active),
      AndroidServiceStatus.vpnActive,
    );
    expect(
      androidServiceStatus({...running, 'protectPhase': 'none'}, active),
      AndroidServiceStatus.proxyOnly,
    );
    expect(
      androidServiceStatus({
        ...running,
        'protectGeneration': 'unknown',
      }, active),
      AndroidServiceStatus.unavailable,
    );
  });

  test(
    'pause retains Stop control before cleanup and only then says suspended',
    () {
      final pausing = {...running, 'paused': true, 'phase': 'stopping'};
      expect(androidRunRequested(pausing), true);
      expect(
        androidServiceStatus(pausing, active),
        AndroidServiceStatus.stopping,
      );
      final stopped = {...pausing, 'phase': 'stopped'};
      expect(
        androidServiceStatus(stopped, const ConfigFact()),
        AndroidServiceStatus.stopping,
      );
      final cleared = {...stopped, 'serviceId': '', 'protectPhase': 'none'};
      expect(
        androidServiceStatus(cleared, const ConfigFact()),
        AndroidServiceStatus.suspended,
      );
      expect(androidRunRequested(cleared), true);
      expect(
        androidServiceStatus(cleared, active),
        AndroidServiceStatus.unavailable,
      );
    },
  );

  test(
    'failed cleanup, revoke and unknown facts never claim stopped or active',
    () {
      for (final reason in ['setupFailed', 'vpnRevoked', 'serviceLost']) {
        final failed = {...running, 'phase': 'failed', 'reason': reason};
        expect(
          androidServiceStatus(failed, active),
          AndroidServiceStatus.unavailable,
        );
        expect(androidRunRequested(failed), false);
      }
      expect(
        androidServiceStatus({}, active),
        AndroidServiceStatus.unavailable,
      );
      expect(androidRunRequested({}), false);
      expect(androidRunRequested({...running, 'phase': 'starting'}), true);
    },
  );

  test('a stopped request is distinct from a preserved paused intent', () {
    final stopped = {
      ...running,
      'phase': 'stopped',
      'intentRunning': false,
      'paused': true,
      'serviceId': '',
      'protectPhase': 'none',
    };
    expect(
      androidServiceStatus(stopped, const ConfigFact()),
      AndroidServiceStatus.stopped,
    );
    expect(androidRunRequested(stopped), false);
  });
}
