import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/widgets/save_status_banner.dart';

/// İŞ PAKETİ 4 / DİLİM D — kayıt hatası GÖRÜNÜR olmalı.
///
/// Eskiden hata yalnız hiçbir yerde izlenmeyen global bir provider'a
/// düşüyordu: kullanıcı değişikliğinin kaydedilmediğini HİÇ öğrenemiyordu.
void main() {
  Widget host({
    required SaveState state,
    VoidCallback? onRetry,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    double width = 320,
  }) {
    return MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SaveStatusBanner(state: state, onRetry: onRetry),
        ),
      ),
    );
  }

  testWidgets('hata KALICI olarak görünür ve Tekrar Dene sunar', (t) async {
    await t.pumpWidget(
      host(
        state: const SaveFailed('Değişiklik kaydedilemedi.'),
        onRetry: () {},
      ),
    );
    expect(find.text('Değişiklik kaydedilemedi.'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    // Renk TEK BAŞINA anlam taşımasın: ikon da olmalı.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('Tekrar Dene aksiyonu çalışır', (t) async {
    var tapped = 0;
    await t.pumpWidget(
      host(state: const SaveFailed('hata'), onRetry: () => tapped++),
    );
    await t.tap(find.text('Tekrar Dene'));
    await t.pump();
    expect(tapped, 1);
  });

  testWidgets('liveRegion semantics taşır', (t) async {
    await t.pumpWidget(host(state: const SaveFailed('hata'), onRetry: () {}));
    final semantics = t.getSemantics(find.byType(SaveStatusBanner));
    expect(
      semantics.flagsCollection.isLiveRegion,
      isTrue,
      reason: 'ekran okuyucu hatayı duyurmalı',
    );
  });

  testWidgets('idle durumda gürültü YAPMAZ', (t) async {
    await t.pumpWidget(host(state: const SaveIdle()));
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Tekrar Dene'), findsNothing);
  });

  testWidgets('saving durumunda sakin gösterge verir', (t) async {
    await t.pumpWidget(host(state: const SaveInProgress()));
    expect(find.text('Kaydediliyor…'), findsOneWidget);
  });

  testWidgets('dar ekran + textScale 1.3 taşma yapmaz', (t) async {
    await t.pumpWidget(
      host(
        state: const SaveFailed(
          'Değişiklik kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
        ),
        onRetry: () {},
        textScale: 1.3,
        width: 320,
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('dark theme taşma/crash yapmaz', (t) async {
    await t.pumpWidget(
      host(
        state: const SaveFailed('Değişiklik kaydedilemedi.'),
        onRetry: () {},
        brightness: Brightness.dark,
      ),
    );
    expect(t.takeException(), isNull);
  });
}
