import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/app_router.dart';
import 'package:karar_veriyorum/features/settings/presentation/screens/settings_screen.dart';

/// Release 6E-A — production router hijyeni.
///
/// Dev-only rotalar üretim router'ında BULUNMAMALI; çekirdek rotalar
/// kayıtlı kalmalı. Firebase/emülatör gerektirmez: yalnız provider'dan
/// router yapılandırması okunur (ekran build edilmez).
void main() {
  List<String> routePaths() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    return router.configuration.routes
        .whereType<GoRoute>()
        .map((r) => r.path)
        .toList();
  }

  test('dev rotası /dev/ai-gallery üretim router\'ında YOK', () {
    final paths = routePaths();
    expect(paths, isNot(contains('/dev/ai-gallery')));
    expect(paths.where((p) => p.startsWith('/dev')), isEmpty);
  });

  testWidgets('/settings gerçek SettingsScreen\'dir (placeholder DEĞİL)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    router.go('/settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.textContaining('Sprint'), findsNothing);
  });

  test('çekirdek rotalar kayıtlı kalır', () {
    final paths = routePaths();
    expect(
      paths,
      containsAll(<String>[
        '/home',
        '/templates',
        '/decision/new',
        '/decision/:id/edit',
        '/decision/:id/result',
        '/decision/:id/check-in',
        '/paywall',
        '/settings',
      ]),
    );
  });
}
