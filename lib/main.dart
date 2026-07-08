import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/services/crash_reporter.dart';

Future<void> main() async {
  // Crashlytics zone guard: async hatalar dahil her şey raporlayıcıya düşer.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Firebase + sessiz anonim oturum (US-E1). Placeholder yapılandırma
    // veya hata → yerel mod; uygulama Firebase'siz de çalışır.
    final status = await FirebaseBootstrap.tryInitialize();

    final CrashReporter reporter = status == FirebaseStatus.ready
        ? const FirebaseCrashReporter()
        : const NoopCrashReporter();

    FlutterError.onError = (details) {
      unawaited(reporter.recordFlutterError(details));
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(reporter.recordError(error, stackTrace, fatal: true));
      return true;
    };

    runApp(
      ProviderScope(
        overrides: [firebaseStatusProvider.overrideWithValue(status)],
        child: const KararVeriyorumApp(),
      ),
    );
  }, (error, stackTrace) {
    // Zone dışına sızan son savunma hattı — Crashlytics hazırsa oraya.
    debugPrint('Yakalanmamış hata: $error');
  });
}
