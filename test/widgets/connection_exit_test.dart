import 'dart:async';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/config_state.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/connection_exits.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/widgets/connection_exit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../helpers/application_activity.dart';
import '../helpers/test_app.dart';
import '../helpers/exit_groups.dart';
import '../helpers/test_config_state.dart';

class _Cache extends ConnectionExits {
  final queried = <String>[];
  final watching = <ConnectionExitTarget, int>{};
  int forced = 0;
  bool releasedDuringManualCheck = false;
  void show(ConnectionExitTarget target, ConnectionExitEntry value) =>
      state = {...state, target: value};
  @override
  Map<ConnectionExitTarget, ConnectionExitEntry> build() => const {};
  @override
  bool isExpired(ConnectionExitTarget target) => false;
  @override
  void watch(ConnectionExitTarget target, {required bool automatic}) {
    watching[target] = (watching[target] ?? 0) + 1;
    if (automatic && !queried.contains(target.node)) {
      queried.add(target.node);
      state = {
        ...state,
        target: ConnectionExitEntry(
          ProbePhase.fresh,
          value: IpInfo(
            ip: '8.210.0.1',
            countryCode: 'HK',
            checkedAt: DateTime(2026, 11, 13),
          ),
        ),
      };
    }
  }

  @override
  void unwatch(ConnectionExitTarget target, {required bool automatic}) {
    final count = watching[target] ?? 0;
    if (count <= 1) {
      if (forced > 0) releasedDuringManualCheck = true;
      watching.remove(target);
    } else {
      watching[target] = count - 1;
    }
  }

  @override
  ExitRefreshResult refresh(ConnectionExitTarget target) {
    forced++;
    return ExitRefreshResult.accepted;
  }
}

void main() {
  late _Cache cache;
  late ProviderContainer container;
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    cache = _Cache();
    container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWith(
          () => TestExitGroups(List.generate(30, (index) => 'Node $index')),
        ),
        connectionExitsProvider.overrideWith(() => cache),
        configStateProvider.overrideWith(
          () => TestConfigState(const ConfigFact(inputId: 'input-a')),
        ),
        appVisibleProvider.overrideWithBuild((_, _) => true),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> pump(
    WidgetTester tester, {
    bool? active = true,
    int count = 30,
  }) async {
    tester.view.physicalSize = const Size(400, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Scaffold(
            body: ListView.builder(
              itemCount: count,
              scrollCacheExtent: const ScrollCacheExtent.pixels(640),
              itemExtent: 80,
              itemBuilder: (context, index) => ListTile(
                title: Text('App $index'),
                leading: ConnectionExitIcon(
                  info: activityConnection('$index', exit: 'Node $index')
                      .copyWith(
                        metadata: const Metadata(
                          network: 'tcp',
                          host: 'example.test',
                          remoteDestination: '8.8.8.8',
                        ),
                      ),
                  active: active,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('only visible rows request exits; prefetched children do not', (
    tester,
  ) async {
    await pump(tester);
    await settle(tester);
    expect(cache.queried, isNotEmpty);
    expect(
      cache.queried.every((name) => int.parse(name.split(' ').last) < 6),
      true,
    );
    expect(cache.queried, isNot(contains('Node 10')));
    expect(
      find.byType(ConnectionExitIcon, skipOffstage: false).evaluate().length,
      greaterThan(cache.queried.length),
    );
  });

  testWidgets('fast scrolling does not start checks for transient rows', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pump();
    expect(cache.queried, isEmpty);
    await settle(tester);
    expect(cache.queried, isNot(contains('Node 0')));
  });

  for (final active in [false, null]) {
    testWidgets('inactive or unconfirmed rows do not auto check: $active', (
      tester,
    ) async {
      await pump(tester, active: active, count: 1);
      await settle(tester);
      expect(cache.queried, isEmpty);
      expect(cache.watching, hasLength(1));
      await tester.tap(find.byType(IconButton).last);
      await tester.pump();
      expect(cache.forced, 1);
    });
  }

  testWidgets(
    'becoming automatically eligible does not cancel a manual check already in flight',
    (tester) async {
      await pump(tester, count: 1);
      await tester.tap(find.byType(IconButton).last);
      await tester.pump();
      expect(cache.forced, 1);
      await settle(tester);
      expect(cache.releasedDuringManualCheck, false);
    },
  );

  testWidgets('covered routes release all visible interests', (tester) async {
    await pump(tester, count: 1);
    await settle(tester);
    expect(cache.watching, isNotEmpty);
    final context = tester.element(find.byType(ConnectionExitIcon));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Details')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cache.watching, isEmpty);
    Navigator.of(context).pop();
    await settle(tester);
    expect(cache.queried, ['Node 0']);
  });

  testWidgets('refresh overlays the corner while preserving the cached flag', (
    tester,
  ) async {
    await pump(tester, count: 1);
    await settle(tester);
    final target = cache.watching.keys.single;
    final previous = container.read(connectionExitsProvider)[target];
    cache.show(
      target,
      ConnectionExitEntry.pending(ProbePhase.probing, previous),
    );
    await tester.pump();
    expect(find.text('🇭🇰'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(CircularProgressIndicator)).width, 10);
    cache.show(
      target,
      ConnectionExitEntry(ProbePhase.failed, value: previous!.value),
    );
    await tester.pumpAndSettle();
    expect(find.text('🇭🇰'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'ended connections can display a stored flag without an automatic check',
    (tester) async {
      await pump(tester, active: false, count: 1);
      await settle(tester);
      final target = cache.watching.keys.single;
      cache.show(
        target,
        ConnectionExitEntry(
          ProbePhase.fresh,
          value: IpInfo(
            ip: '1.1.1.1',
            countryCode: 'HK',
            checkedAt: DateTime(2026, 11, 13),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('🇭🇰'), findsOneWidget);
      expect(cache.queried, isEmpty);
    },
  );

  testWidgets(
    'backgrounding detaches demand until foreground and visible again',
    (tester) async {
      await pump(tester, count: 1);
      await settle(tester);
      container.read(appVisibleProvider.notifier).value = false;
      await tester.pump();
      expect(cache.watching, isEmpty);
      container.read(appVisibleProvider.notifier).value = true;
      await settle(tester);
      expect(cache.queried, ['Node 0']);
    },
  );
}
