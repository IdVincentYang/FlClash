import 'dart:async';

import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/source_acceptance.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/widgets/source_review.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';

class _Native extends Mock implements Service {}

void main() {
  for (final action in [
    (
      label: 'Stop automatic maintenance',
      value: SourcePermissionAction.stopAutomatic,
    ),
    (label: 'Stop using this content', value: SourcePermissionAction.stopUse),
  ]) {
    testWidgets('returns the exact purpose for ${action.label}', (
      tester,
    ) async {
      final requests = Request.scoped(native: _Native(), isAndroid: false);
      addTearDown(requests.detach);
      final permission = SourcePermission(
        source: await requests.captureSource('profile:7'),
        key: 'profile:7',
        kind: 'profile',
        incarnation: 'a' * 48,
        revision: 3,
        automatic: true,
        acceptedCount: 2,
      );
      SourcePermissionChoice? choice;
      await tester.pumpWidget(
        TestApp(
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => const Size(1000, 900)),
          ],
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showDialog<SourcePermissionChoice>(
                    context: context,
                    builder: (_) => SourcePermissionsDialog(
                      label: 'Local fixture',
                      permissions: [permission],
                    ),
                  ).then((value) => choice = value),
                ),
                child: const Text('Open fixture'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open fixture'));
      await tester.pumpAndSettle();
      expect(find.text('Profile content'), findsOneWidget);
      expect(find.text('Accepted revisions: 2'), findsOneWidget);
      expect(
        find.textContaining('closes affected connections'),
        findsOneWidget,
      );
      await tester.tap(find.text(action.label));
      await tester.pumpAndSettle();
      expect(choice?.action, action.value);
      expect(identical(choice?.permission, permission), isTrue);
    });
  }
}
