import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/results/presentation/widgets/result_rank_tile.dart';

/// Görsel Dilim 3 — ResultRankTile bileşen testleri.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    int rank = 1,
    String title = 'iPhone 16',
    double score = 78,
    bool isWinner = false,
    bool isChosen = false,
    bool isTiedLeader = false,
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ResultRankTile(
                rank: rank,
                title: title,
                score: score,
                isWinner: isWinner,
                isChosen: isChosen,
                isTiedLeader: isTiedLeader,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('rank + başlık + N/100 görünür', (tester) async {
    await pump(tester, rank: 2, title: 'Samsung S24', score: 33);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Samsung S24'), findsOneWidget);
    expect(find.text('33/100'), findsOneWidget);
  });

  testWidgets('normal seçenek: durum etiketi yok', (tester) async {
    await pump(tester);
    expect(find.text('Önerilen'), findsNothing);
    expect(find.text('Seçildi'), findsNothing);
  });

  testWidgets('winner: "Önerilen" etiketi + yıldız ikon', (tester) async {
    await pump(tester, isWinner: true);
    expect(find.text('Önerilen'), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
  });

  testWidgets('chosen: "Seçildi" etiketi + check ikon', (tester) async {
    await pump(tester, isChosen: true);
    expect(find.text('Seçildi'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('winner + chosen birlikte: iki etiket de görünür',
      (tester) async {
    await pump(tester, isWinner: true, isChosen: true);
    expect(find.text('Önerilen'), findsOneWidget);
    expect(find.text('Seçildi'), findsOneWidget);
  });

  testWidgets('Semantics label rank, başlık, skor ve durumu içerir',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, rank: 1, title: 'iPhone 16', score: 78, isWinner: true);
    expect(
      find.bySemanticsLabel(
        RegExp('Sıra 1.*iPhone 16.*78 bölü 100 puan.*önerilen'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('tied leader: "Eşit puan" + balance ikon; "Önerilen" yok',
      (tester) async {
    await pump(tester, isTiedLeader: true);
    expect(find.text('Eşit puan'), findsOneWidget);
    expect(find.byIcon(Icons.balance_outlined), findsOneWidget);
    expect(find.text('Önerilen'), findsNothing);
    expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
  });

  testWidgets('tied leader + chosen: her iki etiket görünür', (tester) async {
    await pump(tester, isTiedLeader: true, isChosen: true);
    expect(find.text('Eşit puan'), findsOneWidget);
    expect(find.text('Seçildi'), findsOneWidget);
    expect(find.text('Önerilen'), findsNothing);
  });

  testWidgets('tied leader Semantics label "eşit lider" içerir',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      rank: 1,
      title: 'Deniz tatili',
      score: 56,
      isTiedLeader: true,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('Sıra 1.*Deniz tatili.*56 bölü 100 puan.*eşit lider'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('dark render crash yok', (tester) async {
    await pump(tester, isWinner: true, theme: AppTheme.dark);
    expect(find.text('iPhone 16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uzun başlık + dar ekran (320) + textScale 1.3 taşma yok',
      (tester) async {
    await pump(
      tester,
      title: 'Çok uzun bir seçenek adı iki satıra taşacak kadar uzun yazıldı',
      isWinner: true,
      isChosen: true,
      size: const Size(320, 800),
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('78/100'), findsOneWidget);
  });
}
