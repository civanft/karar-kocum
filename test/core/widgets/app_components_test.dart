import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/core/widgets/app_hero_panel.dart';
import 'package:karar_veriyorum/core/widgets/app_section_header.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/widgets/decision_card.dart';

/// SPRINT C-5 — ortak bileşen testleri.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(400, 800),
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
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('AppHeroPanel', () {
    testWidgets('light render + içerik', (tester) async {
      await pump(
        tester,
        const AppHeroPanel(
          eyebrow: 'Koçundan',
          title: 'Bir kararını kontrol edelim',
          supportText: 'Nasıl gidiyor?',
          icon: Icons.favorite_outline,
        ),
      );
      expect(find.text('Koçundan'), findsOneWidget);
      expect(find.text('Bir kararını kontrol edelim'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark render, crash yok', (tester) async {
      await pump(
        tester,
        const AppHeroPanel(title: 'Başlık'),
        theme: AppTheme.dark,
      );
      expect(find.text('Başlık'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uzun başlıkta overflow yok', (tester) async {
      await pump(
        tester,
        AppHeroPanel(title: 'Çok uzun bir başlık ' * 10),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opsiyonel action çalışır', (tester) async {
      var tapped = false;
      await pump(
        tester,
        AppHeroPanel(
          title: 'Başlık',
          actionLabel: 'Kontrol et',
          onAction: () => tapped = true,
        ),
      );
      await tester.tap(find.text('Kontrol et'));
      expect(tapped, isTrue);
    });

    testWidgets('action yoksa buton yok', (tester) async {
      await pump(tester, const AppHeroPanel(title: 'Başlık'));
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('AppSectionHeader', () {
    testWidgets('başlık + count', (tester) async {
      await pump(tester, const AppSectionHeader(title: 'Kararların', count: 3));
      expect(find.text('Kararların'), findsOneWidget);
      expect(find.text('3 karar'), findsOneWidget); // çıplak sayı değil, pil
    });

    testWidgets('count yoksa sayı yok, trailing gösterilir', (tester) async {
      await pump(
        tester,
        const AppSectionHeader(
          title: 'Şablonlar',
          trailing: Text('Tümü'),
        ),
      );
      expect(find.text('Şablonlar'), findsOneWidget);
      expect(find.text('Tümü'), findsOneWidget);
    });

    testWidgets('uzun başlık + count + textScale 1.3 taşmaz', (tester) async {
      await pump(
        tester,
        const AppSectionHeader(title: 'Çok uzun bir bölüm başlığı', count: 128),
        textScale: 1.3,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('128 karar'), findsOneWidget);
    });

    testWidgets('sıfır değer taşmadan gösterilir', (tester) async {
      await pump(tester, const AppSectionHeader(title: 'Kararların', count: 0));
      expect(find.text('0 karar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DecisionCard', () {
    Decision d({
      DecisionCommitStatus status = DecisionCommitStatus.open,
      DecisionStatus aiStatus = DecisionStatus.draft,
      DecisionCheckIn? checkIn,
      bool favorite = false,
      String title = 'Karar',
    }) =>
        Decision(
          id: 'd1',
          ownerUid: 'u1',
          title: title,
          status: aiStatus,
          decisionStatus: status,
          chosenOptionId: status == DecisionCommitStatus.decided ? 'a' : null,
          decidedAt: status == DecisionCommitStatus.decided
              ? DateTime.utc(2026)
              : null,
          checkInStatus: checkIn,
          isFavorite: favorite,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

    testWidgets('dört durum etiketi', (tester) async {
      // Taslak
      await pump(tester, DecisionCard(decision: d(), onTap: () {}));
      expect(find.text('Taslak'), findsOneWidget);

      // Analiz hazır (analyzed + karar verilmemiş)
      await pump(
        tester,
        DecisionCard(
          decision: d(aiStatus: DecisionStatus.analyzed),
          onTap: () {},
        ),
      );
      expect(find.text('Analiz hazır'), findsOneWidget);

      // Karar verildi
      await pump(
        tester,
        DecisionCard(
          decision: d(status: DecisionCommitStatus.decided),
          onTap: () {},
        ),
      );
      expect(find.text('Karar verildi'), findsOneWidget);

      // Kontrol tamamlandı (check-in yapılmış)
      await pump(
        tester,
        DecisionCard(
          decision: d(
            status: DecisionCommitStatus.decided,
            checkIn: DecisionCheckIn.happy,
          ),
          onTap: () {},
        ),
      );
      expect(find.text('Kontrol tamamlandı'), findsOneWidget);
    });

    testWidgets('onTap tetiklenir', (tester) async {
      var tapped = false;
      await pump(
        tester,
        DecisionCard(decision: d(), onTap: () => tapped = true),
      );
      await tester.tap(find.byType(DecisionCard));
      expect(tapped, isTrue);
    });

    testWidgets('favori yıldızı görünür/gizli', (tester) async {
      await pump(
        tester,
        DecisionCard(decision: d(favorite: true), onTap: () {}),
      );
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);

      await pump(
        tester,
        DecisionCard(decision: d(favorite: false), onTap: () {}),
      );
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('textScale 1.3 + uzun başlıkta overflow yok', (tester) async {
      await pump(
        tester,
        DecisionCard(decision: d(title: 'Çok uzun başlık ' * 8), onTap: () {}),
        textScale: 1.3,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
