import 'dart:async';

import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/widgets/source_review.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  const review = SourceReview(
    label: 'Local fixture',
    origin: 'https://source.example.test',
    kind: 'profile',
    reasons: ['dns_changed'],
    routing: 'source',
    material: 'password: synthetic-secret',
    details: {
      'nodes': 2,
      'rules': 3,
      'protocols': ['socks5'],
      'features': ['udp', 'skip-cert-verify'],
      'dns': ['tcp://127.0.0.1:19053'],
      'defaultTarget': 'Pool',
    },
    previous: {
      'protocols': ['http'],
      'features': ['udp'],
      'dns': ['tcp://127.0.0.1:19054'],
    },
    ruleTargets: ['Pool'],
  );

  Future<void> open(
    WidgetTester tester,
    SourceReview model,
    ValueChanged<SourceReviewDecision?> onDecision,
  ) async {
    await tester.pumpWidget(
      TestApp(
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1000, 900)),
        ],
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(
                  showDialog<SourceReviewDecision>(
                    context: context,
                    builder: (_) => SourceReviewDialog(review: model),
                  ).then(onDecision),
                );
              },
              child: const Text('Open fixture'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open fixture'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows concrete changes and returns the selected scope', (
    tester,
  ) async {
    SourceReviewDecision? decision;
    await open(tester, review, (value) => decision = value);
    expect(find.text('DNS services or their policy changed.'), findsOneWidget);
    expect(find.textContaining('127.0.0.1:19053'), findsOneWidget);
    expect(find.textContaining('127.0.0.1:19054'), findsOneWidget);
    expect(find.text('Accepted node protocols: http'), findsOneWidget);
    expect(find.text('Accepted declared capabilities: udp'), findsOneWidget);
    expect(
      find.text('Declared capabilities: udp, skip-cert-verify'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic-secret'), findsNothing);
    await tester.ensureVisible(find.text('Use source routing rules'));
    await tester.tap(find.text('Use source routing rules'));
    await tester.ensureVisible(
      find.text('Allow maintenance within this scope'),
    );
    await tester.tap(find.text('Allow maintenance within this scope'));
    await tester.tap(find.text('Accept this revision'));
    await tester.pumpAndSettle();
    expect(decision?.routing, 'own');
    expect(decision?.automatic, isTrue);
  });

  testWidgets('rejecting leaves no acceptance decision', (tester) async {
    var completed = false;
    SourceReviewDecision? decision;
    await open(tester, review, (value) {
      completed = true;
      decision = value;
    });
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(decision, isNull);
  });

  testWidgets(
    'binary rule material has unknown count and no default exit claim',
    (tester) async {
      await open(
        tester,
        const SourceReview(
          label: 'Binary fixture',
          origin: '',
          kind: 'provider-rule',
          reasons: ['first_use'],
          routing: 'source',
          details: {
            'binary': true,
            'features': ['mrs', 'domain'],
          },
        ),
        (_) {},
      );
      expect(find.textContaining('The rule count is unknown'), findsOneWidget);
      expect(find.textContaining('Source default exit:'), findsNothing);
      expect(find.text('Source material: 0 nodes, 0 rules'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('script review has exact code and no future-code delegation', (
    tester,
  ) async {
    SourceReviewDecision? decision;
    await open(
      tester,
      const SourceReview(
        label: 'Script fixture',
        origin: '',
        kind: 'script',
        reasons: ['script_code_changed'],
        routing: 'source',
        script: 'function main(config) { return config; }',
      ),
      (value) => decision = value,
    );
    expect(find.text('Review script'), findsOneWidget);
    expect(find.textContaining('function main('), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Accept this revision'));
    await tester.pumpAndSettle();
    expect(decision?.automatic, isFalse);
  });
}
