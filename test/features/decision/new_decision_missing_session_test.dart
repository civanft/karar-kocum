import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/data/repositories/in_memory_decision_repository.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/new_decision_screen.dart';

/// PR-P1-UID-1 / DİLİM 2 — oturum yokken yeni karar oluşturma.
///
/// `ready` + resolved UID null: kullanıcı geçerli bir başlık girip
/// "Devam Et"e bastığında HİÇBİR yazma/navigasyon başlamamalı.
/// pumpAndSettle KULLANILMAZ.
class _SpyRepository extends InMemoryDecisionRepository {
  int writes = 0;

  @override
  Future<void> upsert(Decision decision) async {
    writes++;
    return super.upsert(decision);
  }
}

void main() {
  testWidgets('UID yokken kayıt YOK, navigasyon YOK, spinner YOK, hata VAR',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _SpyRepository();
    var navigated = false;

    final container = ProviderContainer(
      overrides: [
        // Firebase HAZIR ama oturum çözülemedi (auth stream boş, currentUser
        // null) — provider null döner.
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
        currentUidProvider.overrideWithValue(null),
        decisionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const NewDecisionScreen()),
        GoRoute(
          path: '/decision/:id/edit',
          builder: (_, __) {
            navigated = true;
            return const Scaffold(body: Text('EDIT'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();

    const title = 'Telefon değiştirmeli miyim';
    await tester.enterText(find.byType(TextField), title);
    await tester.pump();
    await tester.tap(find.text('Devam Et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.writes, 0, reason: 'UID yokken yazma yapılmamalı');
    expect(navigated, isFalse, reason: 'navigasyon olmamalı');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(const AuthFailure('missing-session').userMessage),
      findsOneWidget,
    );
    // Buton yeniden kullanılabilir kalmalı.
    expect(find.text('Devam Et'), findsOneWidget);
  });
}
