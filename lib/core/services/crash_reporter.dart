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

/// Never send arbitrary exception messages, reasons or diagnostic collectors
/// to a third party: SDK errors can embed request data or credentials.
Object safeCrashError(Object error) =>
    StateError('Application error (${error.runtimeType})');

FlutterErrorDetails safeFlutterErrorDetails(FlutterErrorDetails details) =>
    FlutterErrorDetails(
      exception: safeCrashError(details.exception),
      stack: details.stack,
      library: 'application',
    );

class FirebaseCrashReporter implements CrashReporter {
  const FirebaseCrashReporter();

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) =>
      FirebaseCrashlytics.instance
          .recordFlutterFatalError(safeFlutterErrorDetails(details));

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) =>
      FirebaseCrashlytics.instance
          .recordError(safeCrashError(error), stackTrace, fatal: fatal);
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!kReleaseMode) FlutterError.presentError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    if (!kReleaseMode) debugPrint('CrashReporter(noop): $reason $error');
  }
}

final crashReporterProvider = Provider<CrashReporter>(
  (ref) => ref.watch(firebaseStatusProvider) == FirebaseStatus.ready
      ? const FirebaseCrashReporter()
      : const NoopCrashReporter(),
);
