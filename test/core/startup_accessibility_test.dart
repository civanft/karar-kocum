import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/startup/startup_gate.dart';

/// Bağlanılamadı ekranı, uygulamanın PRODUCTION KÖKÜ olabildiği için
/// erişilebilirlik burada isteğe bağlı değildir: kullanıcının uygulamaya
/// girebildiği tek etkileşim bu ekrandaki "Tekrar dene" düğmesidir.
void main() {
  Widget gate({
    required Future<FirebaseStatus> Function() retry,
  }) =>
      StartupGate(
        initialStatus: FirebaseStatus.unavailable,
        retry: retry,
        appBuilder: (_) => const MaterialApp(home: Text('ready')),
      );

  group('küçük ekran ve büyük metinde taşma yok', () {
    for (final size in [
      const Size(320, 568),
      const Size(667, 320),
      const Size(1280, 720),
    ]) {
      testWidgets('retry $size boyutunda ulaşılabilir', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        var retries = 0;
        await tester.pumpWidget(
          gate(
            retry: () async {
              retries++;
              return FirebaseStatus.ready;
            },
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
  });

  group('ekran okuyucu sözleşmesi', () {
    testWidgets('başlık BAŞLIK ve CANLI BÖLGE olarak işaretli', (t) async {
      final handle = t.ensureSemantics();

      await t.pumpWidget(gate(retry: () async => FirebaseStatus.unavailable));

      final header = t.getSemantics(find.text('Karar Koçum\'a bağlanılamadı'));
      expect(header.label, 'Karar Koçum\'a bağlanılamadı');
      expect(
        header.flagsCollection.isHeader,
        isTrue,
        reason: 'ekran okuyucu başlıkla gezinebilmeli',
      );
      expect(
        header.flagsCollection.isLiveRegion,
        isTrue,
        reason: 'ekran açılışta sessizce belirir; duyurulmalı',
      );
      handle.dispose();
    });

    testWidgets('retry düğmesinin ERİŞİLEBİLİR ADI ve düğme rolü var',
        (t) async {
      final handle = t.ensureSemantics();

      await t.pumpWidget(gate(retry: () async => FirebaseStatus.unavailable));

      final button = t.getSemantics(find.text('Tekrar dene'));
      expect(button.label, 'Tekrar dene');
      expect(button.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('spinner SESSİZ değildir: durum değişimi duyurulur', (t) async {
      final handle = t.ensureSemantics();

      await t.pumpWidget(
        gate(
          retry: () => Future<FirebaseStatus>.delayed(
            const Duration(milliseconds: 80),
            () => FirebaseStatus.ready,
          ),
        ),
      );
      await t.tap(find.text('Tekrar dene'));
      await t.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Meşgulken düğmenin metni yoktur; etiket olmazsa ekran okuyucu
      // hiçbir şey okumaz ve kullanıcı ekranın donduğunu sanar.
      final busy = t.getSemantics(find.byType(CircularProgressIndicator));
      expect(busy.label, 'Yeniden deneniyor');
      expect(
        busy.flagsCollection.isLiveRegion,
        isTrue,
        reason: 'durum değişimi duyurulmalı',
      );
      expect(find.text('Tekrar dene'), findsNothing);

      await t.pumpAndSettle();
      expect(find.text('ready'), findsOneWidget);
      handle.dispose();
    });
  });
}
