import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/services/crash_reporter.dart';
import 'core/startup/startup_gate.dart';

Future<void> main() async {
  // Crashlytics zone guard: async hatalar dahil her şey raporlayıcıya düşer.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Firebase + sessiz anonim oturum (US-E1). Debug/profile'da hata →
    // yerel mod; RELEASE'de hata → unavailable (fail-closed, PR-RELEASE-1).
    final status = await FirebaseBootstrap.ensureInitialized();

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
      _Root(initialStatus: status),
    );
  }, (error, stackTrace) {
    // Zone dışına sızan son savunma hattı — Crashlytics hazırsa oraya.
    if (!kReleaseMode) debugPrint('Yakalanmamış hata: $error');
  });
}

/// Başlangıç kapısı + provider ağacı.
///
/// `unavailable` iken [KararVeriyorumApp] HİÇ kurulmaz; retry başarılı
/// olduğunda yeni durumla birlikte normal uygulama açılır.
class _Root extends StatefulWidget {
  const _Root({required this.initialStatus});

  final FirebaseStatus initialStatus;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late FirebaseStatus _status = widget.initialStatus;

  @override
  Widget build(BuildContext context) {
    return StartupGate(
      initialStatus: _status,
      retry: () async {
        final next = await FirebaseBootstrap.ensureInitialized();
        if (mounted) setState(() => _status = next);
        return next;
      },
      appBuilder: (_) => ProviderScope(
        overrides: [firebaseStatusProvider.overrideWithValue(_status)],
        child: const KararVeriyorumApp(),
      ),
    );
  }
}
