import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/ai_analysis/presentation/screens/ai_gallery_screen.dart';
import 'features/decision/presentation/screens/decision_edit_screen.dart';
import 'features/decision/presentation/screens/home_screen.dart';
import 'features/decision/presentation/screens/new_decision_screen.dart';
import 'features/journey/presentation/screens/check_in_screen.dart';
import 'features/results/presentation/screens/result_screen.dart';
import 'features/templates/presentation/screens/template_gallery_screen.dart';

/// Rota haritası — TEKNIK-MIMARI.md §6.2
/// Sprint 1: çekirdek akış gerçek ekranlarla bağlı.
/// Sprint 2+: onboarding guard'ı, kota → paywall redirect'i, analyze ekranı.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/templates',
        builder: (_, __) => const TemplateGalleryScreen(),
      ),
      GoRoute(
        path: '/decision/new',
        builder: (_, state) => NewDecisionScreen(
          initialTitle: state.uri.queryParameters['title'],
        ),
      ),
      GoRoute(
        path: '/decision/:id/edit',
        builder: (_, state) =>
            DecisionEditScreen(decisionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/decision/:id/result',
        builder: (_, state) =>
            ResultScreen(decisionId: state.pathParameters['id']!),
      ),
      // Sprint C.2 — bildirimden gelinen 1 hafta kontrolü.
      GoRoute(
        path: '/decision/:id/check-in',
        builder: (_, state) =>
            CheckInScreen(decisionId: state.pathParameters['id']!),
      ),
      // Sprint 3
      GoRoute(
        path: '/decision/:id/analyze',
        builder: (_, state) => const _PlaceholderScreen('AI Analiz — Sprint 3'),
      ),
      // DEV galerisi — UI'dan link yok; 6E temizliğinde kaldırılacak.
      GoRoute(
        path: '/dev/ai-gallery',
        builder: (_, __) => const AiGalleryScreen(),
      ),
      // Sprint 5-6
      GoRoute(
        path: '/paywall',
        builder: (_, __) => const _PlaceholderScreen('Premium — Sprint 5'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const _PlaceholderScreen('Ayarlar — Sprint 6'),
      ),
    ],
  );
});

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);
  final String title;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)));
}
