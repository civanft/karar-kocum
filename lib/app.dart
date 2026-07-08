import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class KararVeriyorumApp extends ConsumerWidget {
  const KararVeriyorumApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

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
