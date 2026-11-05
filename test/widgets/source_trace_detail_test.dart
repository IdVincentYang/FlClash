import 'package:fl_clash/features/connection/tracker_info_item.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  TrackerInfo tracker(Map<String, Object?> provenance) => TrackerInfo(
    id: 'synthetic',
    start: DateTime(2026),
    metadata: const Metadata(network: 'tcp', host: 'controlled.test'),
    chains: const ['DIRECT'],
    rule: 'RuleSet',
    rulePayload: 'accepted',
    provenance: provenance,
  );

  Future<void> show(
    WidgetTester tester,
    Map<String, Object?> provenance,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestApp(
        child: Scaffold(
          body: TrackerInfoDetailView(trackerInfo: tracker(provenance)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'connection detail renders captured source and exact applied revision',
    (tester) async {
      await show(tester, {
        'known': true,
        'origin': 'profile:7',
        'label': 'Accepted fixture',
        'appliedRevision':
            '123456789abc'
            'def0123456789abc',
        'ruleSets': [
          {'name': 'accepted', 'revision': 'abcdef0123456789'},
        ],
      });
      expect(find.text('Rule source'), findsOneWidget);
      expect(find.text('Accepted fixture'), findsOneWidget);
      expect(find.text('123456789abc'), findsOneWidget);
      expect(find.text('accepted @ abcdef012345'), findsOneWidget);
    },
  );

  testWidgets('uncertain source displays Unknown without inventing an author', (
    tester,
  ) async {
    await show(tester, {
      'known': false,
      'candidates': ['profile:7', 'script:9'],
    });
    expect(find.text('Unknown'), findsNWidgets(2));
    expect(find.text('profile:7'), findsNothing);
    expect(find.text('script:9'), findsNothing);
  });
}
