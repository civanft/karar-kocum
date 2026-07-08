import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/firebase_bootstrap.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + sessiz anonim oturum (US-E1). Placeholder yapılandırma veya
  // hata → yerel mod; uygulama Firebase'siz de çalışır (in-memory depo).
  // Crashlytics zone guard + App Check: Sprint 3 (Console kurulumu ister).
  final status = await FirebaseBootstrap.tryInitialize();

  runApp(
    ProviderScope(
      overrides: [firebaseStatusProvider.overrideWithValue(status)],
      child: const KararVeriyorumApp(),
    ),
  );
}
