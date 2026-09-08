import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/startup/startup_gate.dart';

/// İŞ PAKETİ 4 / DİLİM E — startup zaman aşımı ve retry sözleşmesi.
///
/// Eski davranış: retry'ın kendi Future'ı asla dönmezse spinner SONSUZA
/// kadar açık kalıyordu ve kullanıcı uygulamada mahsur kalıyordu. Geç
/// tamamlanan bir başlatmanın state'i bozup bozmadığı da test edilmiyordu.
void main() {
  Widget gate({
    required FirebaseStatus initial,
    required Future<FirebaseStatus> Function() retry,
    Duration timeout = const Duration(milliseconds: 50),
    VoidCallback? onAppBuilt,
  }) =>
      StartupGate(
        initialStatus: initial,
        retry: retry,
        retryTimeout: timeout,
        appBuilder: (_) {
          onAppBuilt?.call();
          return const MaterialApp(home: Scaffold(body: Text('GERÇEK APP')));
        },
      );

  testWidgets('retry ZAMAN AŞIMI: spinner kapanır, buton yeniden aktif olur',
      (t) async {
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () => Completer<FirebaseStatus>().future, // asla dönmez
      ),
    );
    await t.tap(find.text('Tekrar dene'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await t.pump(const Duration(milliseconds: 60));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('GERÇEK APP'), findsNothing);
  });

  testWidgets('ÇİFT DOKUNMA tek bootstrap başlatır', (t) async {
    var calls = 0;
    final completer = Completer<FirebaseStatus>();
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () {
          calls++;
          return completer.future;
        },
        timeout: const Duration(seconds: 5),
      ),
    );
    await t.tap(find.text('Tekrar dene'));
    await t.pump();
    // İkinci dokunuş: buton devre dışı olduğu için de, guard nedeniyle de
    // ikinci başlatma OLMAMALI.
    final button = find.byType(ElevatedButton);
    if (tester(button)) await t.tap(button, warnIfMissed: false);
    await t.pump();

    expect(calls, 1);
    completer.complete(FirebaseStatus.unavailable);
    await t.pumpAndSettle();
  });

  testWidgets('zaman aşımından SONRA geç tamamlanma UI\'ı bozmaz', (t) async {
    final completer = Completer<FirebaseStatus>();
    var built = 0;
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () => completer.future,
        onAppBuilt: () => built++,
      ),
    );
    await t.tap(find.text('Tekrar dene'));
    await t.pump(const Duration(milliseconds: 60)); // timeout

    // Geç tamamlanma: ready dese bile UI'ı arkadan değiştirmemeli.
    completer.complete(FirebaseStatus.ready);
    await t.pump(const Duration(milliseconds: 10));

    expect(built, 0);
    expect(find.text('Tekrar dene'), findsOneWidget);
  });

  testWidgets('sonraki retry ready dönerse gerçek app TAM BİR KEZ kurulur',
      (t) async {
    var built = 0;
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () async => FirebaseStatus.ready,
        onAppBuilt: () => built++,
      ),
    );
    await t.tap(find.text('Tekrar dene'));
    await t.pumpAndSettle();

    expect(find.text('GERÇEK APP'), findsOneWidget);
    expect(built, 1);
    // Nested MaterialApp OLUŞMAMALI.
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('parent yeni initialStatus verirse gate GÜNCELLENİR', (t) async {
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () async => FirebaseStatus.unavailable,
      ),
    );
    expect(find.text('GERÇEK APP'), findsNothing);

    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.ready,
        retry: () async => FirebaseStatus.ready,
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('GERÇEK APP'), findsOneWidget);
  });

  testWidgets('unavailable dalında gerçek appBuilder HİÇ çağrılmaz', (t) async {
    var built = 0;
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () async => FirebaseStatus.unavailable,
        onAppBuilt: () => built++,
      ),
    );
    await t.tap(find.text('Tekrar dene'));
    await t.pumpAndSettle();
    expect(built, 0);
  });

  testWidgets('retry exception fırlatırsa güvenli unavailable kalır',
      (t) async {
    await t.pumpWidget(
      gate(
        initial: FirebaseStatus.unavailable,
        retry: () async => throw StateError('firebase init failed'),
      ),
    );
    await t.tap(find.text('Tekrar dene'));
    await t.pumpAndSettle();

    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.textContaining('firebase init failed'), findsNothing);
  });
}

bool tester(Finder f) => f.evaluate().isNotEmpty;
