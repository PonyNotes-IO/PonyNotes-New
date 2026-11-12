import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// File IO completes outside the widget test's virtual clock.
Future<void> settleArtifactFiles(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }
  await tester.pump();
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}
