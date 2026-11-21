import 'package:fl_clash/common/android_service_state.dart';
import 'package:fl_clash/common/application_activity.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/host_traffic.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/request_state.dart';
import 'package:fl_clash/views/application_connections.dart';
import 'package:fl_clash/views/host_traffic.dart';
import 'package:fl_clash/widgets/connection_exit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/application_activity.dart';
import '../helpers/test_app.dart';
import '../helpers/test_config_state.dart';

class _Core extends Fake implements CoreHandlerInterface {
  bool fail = false;
  String epoch = 'runtime-a';
  int reads = 0;

  @override
  Future<HostTrafficSnapshot> getHostTraffic() async {
    reads++;
    if (fail) throw StateError('unavailable');
    return HostTrafficSnapshot(epoch, [
      const HostTrafficRow('ip:192.0.2.1', 1, 2),
      if (epoch == 'runtime-a')
        const HostTrafficRow('host:example.test', 10, 12),
    ]);
  }
}

class _Activity extends ApplicationActivity {
  _Activity(this.activity);
  final ApplicationActivityState activity;
  @override
  ApplicationActivityState build() => activity;
}

void main() {
  testWidgets('sorts, searches and opens retained connections across apps', (
    tester,
  ) async {
    final core = _Core();
    final store = ApplicationActivityStore();
    store.setContext('runtime-a', observing: true, now: DateTime(2026));
    store
      ..addEvent(activityConnection('first', host: 'EXAMPLE.test.'))
      ..addEvent(activityConnection('second', package: 'test.app.b'));
    await tester.pumpWidget(
      TestApp(
        overrides: [
          configStateProvider.overrideWith(TestConfigState.new),
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          androidServiceStatusProvider.overrideWithValue(
            AndroidServiceStatus.vpnActive,
          ),
          applicationActivityProvider.overrideWith(
            () => _Activity(store.snapshot()),
          ),
          applicationCatalogueProvider.overrideWith(
            (_) async =>
                const ApplicationCatalogue(packages: [], accessible: false),
          ),
        ],
        child: const HostTrafficView(),
      ),
    );
    await tester.pumpAndSettle();
    final domain = find.text('example.test');
    final ip = find.text('192.0.2.1');
    expect(tester.getTopLeft(domain).dy, lessThan(tester.getTopLeft(ip).dy));
    expect(find.text('Total: 22B'), findsOneWidget);
    core.fail = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('Could not refresh'), findsOneWidget);
    expect(domain, findsOneWidget);
    core.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.textContaining('Could not refresh'), findsNothing);
    await tester.enterText(find.byType(EditableText), 'EXAMPLE');
    await tester.pumpAndSettle();
    expect(ip, findsNothing);
    await tester.tap(domain);
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationConnectionsView), findsOneWidget);
    expect(find.text('test.app.a'), findsOneWidget);
    expect(find.text('test.app.b'), findsOneWidget);
    expect(find.byType(ConnectionExitIcon), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retains last totals on stop and replaces them on Core restart', (
    tester,
  ) async {
    final core = _Core();
    var status = AndroidServiceStatus.vpnActive;
    final container = ProviderContainer(
      overrides: [
        configStateProvider.overrideWith(TestConfigState.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        androidServiceStatusProvider.overrideWith((_) => status),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: HostTrafficView()),
      ),
    );
    await tester.pumpAndSettle();
    final reads = core.reads;
    status = AndroidServiceStatus.stopped;
    container.invalidate(androidServiceStatusProvider);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(core.reads, reads);
    expect(find.text('example.test'), findsOneWidget);
    expect(find.textContaining('Forwarding is inactive'), findsOneWidget);
    core.epoch = 'runtime-b';
    status = AndroidServiceStatus.vpnActive;
    container.invalidate(androidServiceStatusProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(core.reads, greaterThan(reads));
    expect(find.text('example.test'), findsNothing);
    expect(find.text('192.0.2.1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
