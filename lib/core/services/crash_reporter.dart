import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_bootstrap.dart';

/// Çökme/hata raporlayıcı — yerel modda sessiz, Firebase hazırsa Crashlytics.
/// PII kuralı: log'a karar içeriği eklenmez; yalnız hata + stack.
abstract interface class CrashReporter {
  Future<void> recordFlutterError(FlutterErrorDetails details);
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  });
}

class FirebaseCrashReporter implements CrashReporter {
  const FirebaseCrashReporter();

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) =>
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) =>
      FirebaseCrashlytics.instance
          .recordError(error, stackTrace, fatal: fatal, reason: reason);
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    FlutterError.presentError(details); // geliştirmede konsola düşsün
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    debugPrint('CrashReporter(noop): $reason $error');
  }
}

final crashReporterProvider = Provider<CrashReporter>(
  (ref) => ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? const FirebaseCrashReporter()
      : const NoopCrashReporter(),
);
