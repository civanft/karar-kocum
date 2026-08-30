import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/templates/data/static_template_catalog.dart';
import 'package:karar_veriyorum/features/templates/domain/entities/decision_template.dart';
import 'package:karar_veriyorum/features/templates/presentation/providers/template_decision_creator.dart';
import 'package:karar_veriyorum/features/templates/presentation/widgets/template_preview_sheet.dart';

/// PR-P1-UID-1 / DİLİM 3 — oturum yokken şablondan karar.
///
/// pumpAndSettle KULLANILMAZ (bu dosyanın kardeşi olan
/// template_preview_sheet_test.dart, modal yaşam döngüsünün
/// pumpAndSettle ile 10 dk timeout'a sürüklendiğini belgeliyor).
/// Yalnız sınırlı pump ve YALNIZ null-UID koruması doğrulanır.
class _CountingCreator implements TemplateDecisionCreator {
  int calls = 0;
  final List<String> ownerUids = [];

  @override
  Future<String?> call({
    required String ownerUid,
    required String title,
    required DecisionTemplate template,
  }) async {
    calls++;
    ownerUids.add(ownerUid);
    return 'd1';
  }
}

void main() {
  testWidgets('UID yokken creator çağrılmaz, navigasyon yok, hata gösterilir',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final template = const StaticTemplateCatalog().byId('phone-purchase')!;
    final creator = _CountingCreator();
    var navigated = false;

    final container = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
        currentUidProvider.overrideWithValue(null),
        templateDecisionCreatorProvider.overrideWithValue(creator),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showTemplatePreviewSheet(context, template),
                  child: const Text('AÇ'),
                ),
              ),
            ),
          ),
        ),
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('AÇ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Bu şablonla başla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(creator.calls, 0, reason: 'UID yokken creator çağrılmamalı');
    expect(creator.ownerUids, isEmpty);
    expect(navigated, isFalse, reason: 'editöre yönlenmemeli');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(const AuthFailure('missing-session').userMessage),
      findsOneWidget,
    );
  });
}
