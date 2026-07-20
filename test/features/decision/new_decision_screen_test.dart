import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/new_decision_screen.dart';

/// SPINNER HOTFIX widget testleri: hiçbir Firestore/Firebase hatası
/// sonsuz spinner üretemez — spinner kapanır, kullanıcı mesaj görür.
/// Kural: pumpAndSettle YOK (sınırlı pump).
class _ThrowingRepository extends InMemoryDecisionRepository {
  @override
  Future<void> upsert(Decision decision) async {
    throw Exception('[cloud_firestore/permission-denied] simülasyonu');
  }
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    DecisionRepository repo,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const NewDecisionScreen()),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, state) =>
              Scaffold(body: Text('EDIT ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'repo hatası: spinner KAPANIR, anlamlı hata görünür, buton tekrar aktif',
      (tester) async {
    await pumpScreen(tester, _ThrowingRepository());

    await tester.enterText(find.byType(TextField), 'Geçerli bir başlık');
    await tester.pump();
    await tester.tap(find.text('Devam Et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Spinner yok, buton geri geldi:
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Devam Et'), findsOneWidget);
    // Kullanıcı-dostu mesaj (sonsuz spinner yerine):
    expect(find.textContaining('tekrar'), findsWidgets);

    // Buton yeniden basılabilir (kilitli kalmadı):
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('başarı yolu regresyonu: karar oluşur (hata dalı bozmadı)',
      (tester) async {
    final repo = InMemoryDecisionRepository();
    addTearDown(repo.dispose);
    await pumpScreen(tester, repo);

    await tester.enterText(find.byType(TextField), 'Normal karar');
    await tester.pump();
    await tester.tap(find.text('Devam Et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Editöre yönlendi + karar repo'da (watchAll().first KULLANILMAZ —
    // in-memory akışın onCancel'ı testWidgets içinde kilitlenebiliyor,
    // bkz. A1/M4 dersi; id stub ekrandan okunur, getById ile doğrulanır):
    final editText =
        tester.widget<Text>(find.textContaining('EDIT ')).data!; // 'EDIT <id>'
    final id = editText.substring('EDIT '.length);
    final persisted = await repo.getById(id);
    expect(persisted, isNotNull);
    expect(persisted!.title, 'Normal karar');
  });
}
