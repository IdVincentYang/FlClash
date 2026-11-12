import 'dart:async';

import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/common/source_review_loading.dart';
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
    'subscription batch loads related snapshots before one acceptance',
    (tester) async {
      final ready = Completer<List<SourceReview>>();
      SourceReviewDecision? decision;
      await tester.pumpWidget(
        TestApp(
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => const Size(1000, 900)),
          ],
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showDialog<SourceReviewDecision>(
                    context: context,
                    builder: (_) => SourceReviewDialog(
                      review: review,
                      loadRelated: (_) => ready.future,
                    ),
                  ).then((value) => decision = value),
                ),
                child: const Text('Open batch'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open batch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Review subscription'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Accept this revision'),
            )
            .onPressed,
        isNull,
      );
      ready.complete(const [
        SourceReview(
          label: 'First rules',
          origin: 'https://first.example.test',
          kind: 'provider-rule',
          reasons: [],
          routing: 'source',
          details: {'rules': 16},
        ),
        SourceReview(
          label: 'Second rules',
          origin: 'https://second.example.test',
          kind: 'provider-rule',
          reasons: [],
          routing: 'source',
          details: {'rules': 28},
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Associated sources: 2'), findsOneWidget);
      expect(find.textContaining('First rules'), findsOneWidget);
      expect(find.textContaining('Second rules'), findsOneWidget);
      await tester.tap(find.text('Accept this revision'));
      await tester.pumpAndSettle();
      expect(decision, isNotNull);
      expect(find.byType(SourceReviewDialog), findsNothing);
    },
  );

  testWidgets(
    'shows every source while loading and retries a failed row only',
    (tester) async {
      final loading = SourceReviewLoading();
      final gates = {for (var i = 0; i < 4; i++) '$i': Completer<void>()};
      final calls = <String, int>{};
      SourceReviewDecision? decision;
      await tester.pumpWidget(
        TestApp(
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => const Size(1000, 900)),
          ],
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showDialog<SourceReviewDecision>(
                    context: context,
                    builder: (_) => SourceReviewDialog(
                      review: review,
                      loading: loading,
                      loadRelated: (_) async {
                        await loading.load(
                          [
                            for (var i = 0; i < 4; i++)
                              SourceReviewLoadItem(
                                key: '$i',
                                label: 'Source $i',
                                kind: 'provider-rule',
                              ),
                          ],
                          (key, progress) async {
                            calls[key] = (calls[key] ?? 0) + 1;
                            await gates[key]!.future;
                            if (key == '0' && calls[key] == 1) {
                              throw StateError('source zero failed');
                            }
                            return SourceReviewBatchEntry(
                              keys: {key},
                              review: SourceReview(
                                label: 'Source $key',
                                origin: '',
                                kind: 'provider-rule',
                                reasons: const [],
                                routing: 'source',
                              ),
                            );
                          },
                        );
                        return [];
                      },
                    ),
                  ).then((value) => decision = value),
                ),
                child: const Text('Open progress'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open progress'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Associated sources: 4'), findsOneWidget);
      expect(find.textContaining('Source 3'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Accept this revision'),
            )
            .onPressed,
        isNull,
      );
      for (final gate in gates.values) {
        gate.complete();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('retry:0')), findsOneWidget);
      expect(find.text('Ready: 3/4'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('retry:0')));
      await tester.tap(find.byKey(const ValueKey('retry:0')));
      await tester.pumpAndSettle();
      expect(calls, {'0': 2, '1': 1, '2': 1, '3': 1});
      expect(find.text('Ready: 4/4'), findsOneWidget);
      await tester.tap(find.text('Accept this revision'));
      await tester.pumpAndSettle();
      expect(decision, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      loading.dispose();
    },
  );

  testWidgets('final configuration review is distinct from source review', (
    tester,
  ) async {
    await open(
      tester,
      const SourceReview(
        label: 'Final fixture',
        origin: '',
        kind: 'config',
        reasons: ['first_use'],
        routing: 'source',
      ),
      (_) {},
    );
    expect(find.text('Final configuration'), findsOneWidget);
    expect(find.text('Review source'), findsNothing);
    expect(find.text('Use source routing rules'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
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
  for (final choice in [
    SourceImportChoice.savePending,
    SourceImportChoice.loadedNodes,
  ]) {
    testWidgets('partial import waits for every attempt then returns $choice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final loading = SourceReviewLoading();
      addTearDown(loading.dispose);
      final gates = {for (var i = 0; i < 5; i++) '$i': Completer<void>()};
      final calls = <String>[];
      SourceReviewDecision? decision;
      await tester.pumpWidget(
        TestApp(
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 900)),
          ],
          child: Scaffold(
            body: SourceReviewDialog(
              review: review,
              loading: loading,
              allowPartialImport: true,
              canUseLoadedNodes: () => true,
              onDecision: (value) => decision = value,
              loadRelated: (_) async {
                await loading.load(
                  [
                    for (var i = 0; i < 5; i++)
                      SourceReviewLoadItem(
                        key: '$i',
                        label: '$i',
                        kind: 'provider-rule',
                      ),
                  ],
                  (key, _) async {
                    calls.add(key);
                    await gates[key]!.future;
                    if (key == '0') throw StateError('synthetic failure');
                    return SourceReviewBatchEntry(keys: {key}, review: review);
                  },
                );
                return [];
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, ['0', '1', '2']);
      gates['0']!.complete();
      await tester.pump();
      expect(calls, ['0', '1', '2', '3']);
      expect(loading.settled, isFalse);
      expect(find.text('Save for later review'), findsNothing);
      expect(find.text('Review loaded nodes only'), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Accept this revision'),
            )
            .onPressed,
        isNull,
      );
      for (final gate in gates.values) {
        if (!gate.isCompleted) gate.complete();
      }
      await tester.pumpAndSettle();
      expect(calls, ['0', '1', '2', '3', '4']);
      expect(loading.settled, isTrue);
      expect(find.text('Save for later review'), findsOneWidget);
      expect(find.text('Review loaded nodes only'), findsOneWidget);
      expect(find.text('Accept this revision'), findsNothing);
      final text = choice == SourceImportChoice.savePending
          ? 'Save for later review'
          : 'Review loaded nodes only';
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      expect(decision?.importChoice, choice);
      expect(decision?.automatic, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
