import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/journey/presentation/providers/pending_check_in.dart';

class KararVeriyorumApp extends ConsumerStatefulWidget {
  const KararVeriyorumApp({super.key});

  @override
  ConsumerState<KararVeriyorumApp> createState() => _KararVeriyorumAppState();
}

class _KararVeriyorumAppState extends ConsumerState<KararVeriyorumApp> {
  @override
  void initState() {
    super.initState();
    // Sprint C.2: bildirim altyapısını kur ve dokunuşu dinlemeye başla.
    // Beklenmez — takip sistemi kurulamasa da uygulama açılır.
    unawaited(ref.read(journeyBootstrapProvider)());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Bildirime dokunuldu → ilgili kontrol ekranına git. Yönlendirme
    // widget ağacının İÇİNDE yapılır; callback'in context'i yoktur.
    ref.listen<String?>(pendingCheckInProvider, (_, decisionId) {
      if (decisionId == null) return;
      router.go('/decision/$decisionId/check-in');
      ref.read(pendingCheckInProvider.notifier).consume();
    });

    return MaterialApp.router(
      title: 'Karar Veriyorum',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system, // + kullanıcı tercihi (settings) Faz 2
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
