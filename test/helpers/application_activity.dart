import 'package:fl_clash/models/models.dart';

TrackerInfo activityConnection(
  String id, {
  String epoch = 'runtime-a',
  String package = 'test.app.a',
  int uid = 10001,
  String host = 'example.test',
  String ip = '192.0.2.1',
  String exit = 'node-a',
  String input = 'input-a',
  DateTime? start,
  int upload = 0,
  String status = 'known',
  List<String>? candidates,
}) => TrackerInfo(
  id: id,
  start: start ?? DateTime.utc(2026, 11, 11, 1),
  metadata: Metadata(network: 'tcp', host: host, destinationIP: ip),
  chains: [exit, 'Proxy'],
  rule: 'Domain',
  rulePayload: host,
  upload: upload,
  observation: ConnectionObservation(
    runtimeEpoch: epoch,
    application: ApplicationIdentity(
      status: status,
      uid: uid,
      userScope: 'current',
      packages: candidates ?? [package],
      method: 'androidUid',
    ),
    capture: const ConnectionCapture(
      status: 'vpn',
      serviceId: 'vpn-a',
      generation: 1,
    ),
    configuration: ConnectionConfiguration(
      status: 'known',
      inputId: input,
      mode: 'rule',
    ),
  ),
);
