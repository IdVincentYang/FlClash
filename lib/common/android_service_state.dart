import '../models/config_state.dart';

enum AndroidServiceStatus {
  applying,
  stopping,
  suspended,
  stopped,
  vpnActive,
  proxyOnly,
  unavailable,
}

bool androidRunRequested(Map<String, Object?> state) =>
    state['intentRunning'] == true &&
    state['reason'] != 'exiting' &&
    const {
      'preparing',
      'starting',
      'started',
      'stopping',
      'stopped',
    }.contains(state['phase']);

AndroidServiceStatus androidServiceStatus(
  Map<String, Object?> state,
  ConfigFact fact,
) {
  final phase = state['phase'];
  final service = state['serviceId'];
  final protection = state['protectPhase'];
  if (phase == 'failed' || state['reason'] == 'exiting') {
    return AndroidServiceStatus.unavailable;
  }
  if (phase == 'preparing' || phase == 'starting') {
    return AndroidServiceStatus.applying;
  }
  if (phase == 'stopping') return AndroidServiceStatus.stopping;
  if (phase == 'stopped') {
    if (service is! String || protection is! String) {
      return AndroidServiceStatus.unavailable;
    }
    if (service.isNotEmpty || protection != 'none') {
      return AndroidServiceStatus.stopping;
    }
    if (fact.businessActive) return AndroidServiceStatus.unavailable;
    if (state['paused'] == true && state['intentRunning'] == true) {
      return AndroidServiceStatus.suspended;
    }
    return state['intentRunning'] == false
        ? AndroidServiceStatus.stopped
        : AndroidServiceStatus.unavailable;
  }
  if (phase != 'started' || service is! String || service.isEmpty) {
    return AndroidServiceStatus.unavailable;
  }
  if (fact.phase == 'parsing' || fact.phase == 'installed') {
    return AndroidServiceStatus.applying;
  }
  if (fact.phase != 'ready' ||
      !fact.businessActive ||
      state['intentRunning'] != true ||
      state['paused'] != false) {
    return AndroidServiceStatus.unavailable;
  }
  final generation = state['protectGeneration'];
  if (protection == 'ready' && generation is int && generation > 0) {
    return AndroidServiceStatus.vpnActive;
  }
  return protection == 'none'
      ? AndroidServiceStatus.proxyOnly
      : AndroidServiceStatus.unavailable;
}
