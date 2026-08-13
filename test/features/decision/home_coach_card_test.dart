import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/home_screen.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_coordinator.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';

/// SPRINT C-5 — "Sıcak Premium Koç" Home prototipi widget testleri.
/// Gerçek AppTheme uygulanır (AppSemanticColors extension gerekir).
/// journeyClockProvider sabit saatle override; gerçek zaman kullanılmaz.
void main() {
  const delay = FollowUpCoordinator.followUpDelay;
  final decidedAt = DateTime.utc(2026, 7, 1, 9);
  final due7 = decidedAt.add(delay); // tam 7 gün

  Decision decided({
    required String id,
    required String title,
    required DateTime decidedAt,
    DecisionCheckIn? checkIn,
  }) =>
      Decision(
        id: id,
        ownerUid: 'u1',
        title: title,
        decisionStatus: DecisionCommitStatus.decided,
        chosenOptionId: 'a',
        decidedAt: decidedAt,
        checkInStatus: checkIn,
        checkedInAt: checkIn != null ? decidedAt : null,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );

  late String lastRoute;

  Future<void> pumpHome(
    WidgetTester tester, {
    required List<Decision> decisions,
    required DateTime now,
    Size size = const Size(400, 800),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    lastRoute = '/home';

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/decision/:id/check-in',
          builder: (_, s) {
            lastRoute = '/decision/${s.pathParameters['id']}/check-in';
            return const Scaffold(body: Text('CHECK-IN ROUTE'));
          },
        ),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, s) {
            lastRoute = '/decision/${s.pathParameters['id']}/edit';
            return const Scaffold(body: Text('EDIT ROUTE'));
          },
        ),
        GoRoute(
          path: '/decision/new',
          builder: (_, __) {
            lastRoute = '/decision/new';
            return const Scaffold(body: Text('NEW ROUTE'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journeyClockProvider.overrideWithValue(() => now),
          decisionListProvider.overrideWith((ref) => Stream.value(decisions)),
        ],
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('1) due yoksa koç hero yok, karşılama hero görünür',
      (tester) async {
    await pumpHome(
      tester,
      decisions: [decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt)],
      now: decidedAt.add(const Duration(days: 1)),
    );

    expect(find.text('Koçundan'), findsNothing);
    expect(find.text('Bir kararını kontrol edelim'), findsNothing);
    // Karşılama hero'su + marka + karar kartı:
    expect(find.text('Bugün neyi netleştirelim?'), findsOneWidget);
    expect(find.text('Karar Koçum'), findsOneWidget);
    expect(find.text('Telefon'), findsOneWidget);
  });

  testWidgets('2) tam 7 günlük due → tek koç hero görünür', (tester) async {
    await pumpHome(
      tester,
      decisions: [decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt)],
      now: due7,
    );

    expect(find.text('Koçundan'), findsOneWidget);
    expect(find.text('Bir kararını kontrol edelim'), findsOneWidget);
    expect(find.text('Kontrol et'), findsOneWidget);
    // İkinci dev hero yok: karşılama başlığı gösterilmez.
    expect(find.text('Bugün neyi netleştirelim?'), findsNothing);
  });

  testWidgets('3) koç hero karar başlığı ve gün sayısını taşır',
      (tester) async {
    await pumpHome(
      tester,
      decisions: [decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt)],
      now: due7.add(const Duration(days: 2)), // 9 gün
    );

    expect(
      find.textContaining('"Telefon" kararının üzerinden 9 gün'),
      findsOneWidget,
    );
  });

  testWidgets('4) birden fazla due → toplam sayı hero içinde', (tester) async {
    await pumpHome(
      tester,
      decisions: [
        decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt),
        decided(id: 'd2', title: 'Araba', decidedAt: decidedAt),
        decided(id: 'd3', title: 'Ev', decidedAt: decidedAt),
      ],
      now: due7,
    );

    expect(find.textContaining('3 kararın kontrol bekliyor'), findsOneWidget);
  });

  testWidgets('5) "Kontrol et" en eski due kararın check-in rotasına gider',
      (tester) async {
    await pumpHome(
      tester,
      decisions: [
        decided(id: 'd1', title: 'Telefon', decidedAt: due7),
        decided(id: 'd2', title: 'Araba', decidedAt: decidedAt), // en eski
      ],
      now: due7.add(const Duration(days: 30)),
    );

    await tester.tap(find.text('Kontrol et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(lastRoute, '/decision/d2/check-in');
    expect(find.text('CHECK-IN ROUTE'), findsOneWidget);
  });

  testWidgets('6) check-in yapılmış karar için koç hero yok', (tester) async {
    await pumpHome(
      tester,
      decisions: [
        decided(
          id: 'd1',
          title: 'Telefon',
          decidedAt: decidedAt,
          checkIn: DecisionCheckIn.happy,
        ),
      ],
      now: due7.add(const Duration(days: 5)),
    );

    expect(find.text('Koçundan'), findsNothing);
    expect(find.text('Bir kararını kontrol edelim'), findsNothing);
    expect(find.text('Telefon'), findsOneWidget); // kart yine var
    // Durum etiketi:
    expect(find.text('Kontrol tamamlandı'), findsOneWidget);
  });

  testWidgets('7) uzun karar başlığında overflow yok', (tester) async {
    final uzun = 'Çok uzun bir karar başlığı ' * 8;
    await pumpHome(
      tester,
      decisions: [decided(id: 'd1', title: uzun, decidedAt: decidedAt)],
      now: due7,
      size: const Size(320, 640), // küçük ekran
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Koçundan'), findsOneWidget);
  });

  testWidgets('8) DecisionCard listesi ve Yeni Karar FAB korunur',
      (tester) async {
    await pumpHome(
      tester,
      decisions: [
        decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt),
        decided(id: 'd2', title: 'Araba', decidedAt: decidedAt),
      ],
      now: due7,
    );

    expect(find.text('Telefon'), findsOneWidget);
    expect(find.text('Araba'), findsOneWidget);
    expect(find.text('Kararların'), findsOneWidget); // section header
    expect(find.text('Yeni Karar'), findsOneWidget);
    await tester.tap(find.text('Yeni Karar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(lastRoute, '/decision/new');
  });

  testWidgets('9) DecisionCard doğru edit rotasına gider', (tester) async {
    await pumpHome(
      tester,
      decisions: [decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt)],
      now: decidedAt, // due değil → sade liste
    );

    await tester.tap(find.text('Telefon'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(lastRoute, '/decision/d1/edit');
  });

  testWidgets('10) dark tema Home render olur, overflow yok', (tester) async {
    await pumpHome(
      tester,
      decisions: [decided(id: 'd1', title: 'Telefon', decidedAt: decidedAt)],
      now: due7,
      theme: AppTheme.dark,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Koçundan'), findsOneWidget);
    expect(find.text('Karar Koçum'), findsOneWidget);
  });
}
