import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/startup/startup_gate.dart';

/// PR-RELEASE-1A / P0-1 — StartupGate GERÇEK ROOT olarak render edilir.
///
/// Production'da `runApp(StartupGate(...))` çağrılır: yukarıda MaterialApp,
/// WidgetsApp ya da Directionality YOKTUR. Önceki test kapıyı dışarıdan
/// MaterialApp ile sarıyordu ve bu hatayı maskeliyordu.
void main() {
  testWidgets('unavailable ekranı ROOT\'ta çökmeden açılır', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var appBuilt = false;

    // DIŞARIDAN HİÇBİR SARMALAYICI YOK — production kök ağacının aynısı.
    await tester.pumpWidget(
      StartupGate(
        initialStatus: FirebaseStatus.unavailable,
        retry: () async => FirebaseStatus.unavailable,
        appBuilder: (_) {
          appBuilt = true;
          return const MaterialApp(home: Scaffold(body: Text('GERÇEK APP')));
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Karar Koçum\'a bağlanılamadı'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(appBuilt, isFalse, reason: 'gerçek uygulama kurulmamalı');
  });

  testWidgets('ready → appBuilder\'ın kendi MaterialApp\'i, NESTED yok',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      StartupGate(
        initialStatus: FirebaseStatus.ready,
        retry: () async => FirebaseStatus.ready,
        appBuilder: (_) =>
            const MaterialApp(home: Scaffold(body: Text('GERÇEK APP'))),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('GERÇEK APP'), findsOneWidget);
    expect(
      find.byType(MaterialApp),
      findsOneWidget,
      reason: 'ready dalında iç içe MaterialApp olmamalı',
    );
  });

  testWidgets('ROOT\'ta retry başarılı → gerçek uygulamaya geçer',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      StartupGate(
        initialStatus: FirebaseStatus.unavailable,
        retry: () async => FirebaseStatus.ready,
        appBuilder: (_) =>
            const MaterialApp(home: Scaffold(body: Text('GERÇEK APP'))),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('GERÇEK APP'), findsOneWidget);
  });
}
