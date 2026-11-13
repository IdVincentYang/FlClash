import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/models/models.dart';

String? connectionProxyServerIp(TrackerInfo info) {
  if (info.chains.isEmpty ||
      const {
        'DIRECT',
        'COMPATIBLE',
        'REJECT',
        'REJECT-DROP',
        'PASS',
      }.contains(info.chains.first.toUpperCase())) {
    return null;
  }
  final ip = publicIp(info.metadata.remoteDestination)?.address;
  if (ip == publicIp(info.metadata.destinationIP)?.address ||
      ip == publicIp(info.metadata.host)?.address) {
    return null;
  }
  return ip;
}
