import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/policy_core_bridge.dart';

class _Native extends Mock implements Service {}

class _Core extends CoreHandlerInterface {
  _Core(this.bridge);
  final PolicyCoreBridge bridge;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<T?> invokeMethod<T>({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async {
    if (method != CoreMethod.outboundIp) throw UnsupportedError(method.name);
    return Map<String, dynamic>.from(await bridge.call('outbound', arguments))
        as T;
  }
}

class _Probe extends OutboundIpProbe {
  _Probe(this.client);
  final Request client;
  @override
  Request get requestClient => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final executable = Platform.environment['FLCLASH_IP_BRIDGE'];
  late PolicyCoreBridge bridge;
  late Request client;
  late ProviderContainer container;
  late _Probe probe;
  late Directory temporary;
  Future<void> until(Future<bool> Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('local consumer did not reach expected state');
  }

  setUpAll(() async {
    if (executable == null) return;
    temporary = await Directory.systemTemp.createTemp('ip-bridge-');
    AppPath.supportDirectory = () async => temporary;
    AppPath.temporaryDirectory = () async => temporary;
    AppPath.cacheDirectory = () async => temporary;
  });
  tearDownAll(() async {
    if (executable != null) await temporary.delete(recursive: true);
  });
  setUp(() async {
    if (executable == null) return;
    bridge = PolicyCoreBridge(
      await Process.start(
        executable,
        [r'-test.run=^TestIPLookupBridge$'],
        workingDirectory: Directory('core').absolute.path,
        environment: {'FLCLASH_IP_BRIDGE': '1'},
      ),
    );
    final native = _Native();
    when(() => native.requestControl(any())).thenAnswer(
      (call) => bridge.call('control', call.positionalArguments.first),
    );
    when(native.getRequestState).thenAnswer((_) => bridge.call('state'));
    client = Request.scoped(native: native, isAndroid: true);
    probe = _Probe(client);
    final route = await bridge.call('route');
    container = ProviderContainer(
      overrides: [
        outboundIpProbeProvider.overrideWith(() => probe),
        coreHandlerProvider.overrideWithValue(
          CoreController.scoped(_Core(bridge)),
        ),
        routeTrackerProvider.overrideWithBuild(
          (_, _) => RouteState(
            coreEpoch: (route['core-epoch'] as num).toInt(),
            picksVersion: (route['picks-version'] as num).toInt(),
            hostEpoch: 1,
            proxied: true,
            synced: true,
            live: true,
          ),
        ),
      ],
    );
    container.listen(outboundIpProbeProvider, (_, _) {});
    client.attach(container);
    await client.ready();
    probe.watch('diagnostic-node', automatic: false);
  });
  tearDown(() async {
    if (executable == null) return;
    await client.detach();
    container.dispose();
    await bridge.close();
  });
  test(
    'real Dart begin and Core interface scope reach the actual Go HTTPS consumer',
    () async {
      probe.refresh(['diagnostic-node']);
      await until(
        () async =>
            container
                .read(outboundIpProbeProvider)
                .valueOf('diagnostic-node') !=
            null,
      );
      expect(
        container.read(outboundIpProbeProvider).valueOf('diagnostic-node')?.ip,
        '1.1.1.1',
      );
      expect((await bridge.call('counts'))['received'], 1);
    },
    skip: executable == null,
  );
  test(
    'closing while actual Go reads cancels the HTTP connection and drops result',
    () async {
      await bridge.call('hold', true);
      probe.refresh(['diagnostic-node']);
      await until(() async => (await bridge.call('counts'))['received'] == 1);
      probe.unwatch('diagnostic-node', automatic: false);
      await until(() async => (await bridge.call('counts'))['cancelled'] == 1);
      expect(
        container.read(outboundIpProbeProvider).valueOf('diagnostic-node'),
        isNull,
      );
    },
    skip: executable == null,
  );
  test(
    'revoked native capability never reaches the Go outbound source',
    () async {
      await bridge.call('control', {'action': 'block'});
      probe.refresh(['diagnostic-node']);
      await pumpEventQueue();
      expect((await bridge.call('counts'))['received'], 0);
    },
    skip: executable == null,
  );
}
