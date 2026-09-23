import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/startup/startup_gate.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(667, 320),
    const Size(1280, 720),
  ]) {
    testWidgets('startup retry reachable at $size with large text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var retries = 0;
      await tester.pumpWidget(
        StartupGate(
          initialStatus: FirebaseStatus.unavailable,
          retry: () async {
            retries++;
            return FirebaseStatus.ready;
          },
          appBuilder: (_) => const MaterialApp(home: Text('ready')),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Tekrar dene'));
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(find.text('ready'), findsOneWidget);
    });
  }
}
