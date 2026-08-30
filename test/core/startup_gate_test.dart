import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/startup/startup_gate.dart';

/// PR-RELEASE-1 — release başlangıç kapısı.
///
/// `unavailable` durumunda gerçek uygulama/router HİÇ kurulmaz: kullanıcı
/// sahte veriyle dolu bir Home görmez, açık bir "bağlanılamadı" ekranı görür.
/// pumpAndSettle KULLANILMAZ (retry spinner'ı sürerken sonsuz beklerdi).
void main() {
  Future<void> pumpGate(
    WidgetTester tester, {
    required FirebaseStatus initial,
    required Future<FirebaseStatus> Function() onRetry,
    required WidgetBuilder appBuilder,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StartupGate(
            initialStatus: initial,
            retry: onRetry,
            appBuilder: appBuilder,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Widget realApp(BuildContext _) =>
      const Scaffold(body: Text('GERÇEK UYGULAMA'));

  testWidgets('unavailable → güvenli hata ekranı, gerçek uygulama YOK',
      (tester) async {
    await pumpGate(
      tester,
      initial: FirebaseStatus.unavailable,
      onRetry: () async => FirebaseStatus.unavailable,
      appBuilder: realApp,
    );

    expect(find.text('Karar Koçum\'a bağlanılamadı'), findsOneWidget);
    expect(
      find.textContaining('Kararların bu sırada değişmedi'),
      findsOneWidget,
    );
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('GERÇEK UYGULAMA'), findsNothing);
  });

  testWidgets('ready → doğrudan gerçek uygulama', (tester) async {
    await pumpGate(
      tester,
      initial: FirebaseStatus.ready,
      onRetry: () async => FirebaseStatus.ready,
      appBuilder: realApp,
    );
    expect(find.text('GERÇEK UYGULAMA'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsNothing);
  });

  testWidgets('localMode → gerçek uygulama (geliştirme UX bozulmaz)',
      (tester) async {
    await pumpGate(
      tester,
      initial: FirebaseStatus.localMode,
      onRetry: () async => FirebaseStatus.localMode,
      appBuilder: realApp,
    );
    expect(find.text('GERÇEK UYGULAMA'), findsOneWidget);
  });

  testWidgets('retry BAŞARILI → normal uygulama açılır', (tester) async {
    await pumpGate(
      tester,
      initial: FirebaseStatus.unavailable,
      onRetry: () async => FirebaseStatus.ready,
      appBuilder: realApp,
    );

    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('GERÇEK UYGULAMA'), findsOneWidget);
  });

  testWidgets('retry BAŞARISIZ → ekran kalır, spinner kapanır', (tester) async {
    await pumpGate(
      tester,
      initial: FirebaseStatus.unavailable,
      onRetry: () async => FirebaseStatus.unavailable,
      appBuilder: realApp,
    );

    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Karar Koçum\'a bağlanılamadı'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('GERÇEK UYGULAMA'), findsNothing);
  });

  testWidgets('hızlı çift dokunuş → TEK başlatma çağrısı', (tester) async {
    var calls = 0;
    await pumpGate(
      tester,
      initial: FirebaseStatus.unavailable,
      onRetry: () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return FirebaseStatus.unavailable;
      },
      appBuilder: realApp,
    );

    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();
    // Spinner sürerken ikinci dokunuş yutulmalı.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, 1);
  });

  testWidgets('hata ekranında mock veri / Home / AI CTA yok', (tester) async {
    await pumpGate(
      tester,
      initial: FirebaseStatus.unavailable,
      onRetry: () async => FirebaseStatus.unavailable,
      appBuilder: realApp,
    );

    for (final forbidden in [
      'Yeni karar',
      'Kararlarım',
      'Analiz et',
      'kredi',
      'Home',
    ]) {
      expect(
        find.textContaining(forbidden, findRichText: true),
        findsNothing,
        reason: '"$forbidden" hata ekranında görünmemeli',
      );
    }
  });
}
