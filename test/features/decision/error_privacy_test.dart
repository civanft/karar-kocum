import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/services/crash_reporter.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/repositories/decision_repository.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_editor.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/home_screen.dart';

/// İŞ PAKETİ 4 — HAM HATA YÜZEYİ ve GİZLİLİK SÖZLEŞMESİ.
///
/// Kullanıcıya ham `$e`, exception sınıfı, backend ayrıntısı veya stack
/// GÖSTERİLMEZ; log/Crashlytics'e karar içeriği, UID, yama, secret veya
/// kişisel veri GİTMEZ. Yalnız UI'da görünmeyen sanitize teknik neden kodu
/// serbesttir.

/// Gerçek bir backend hatasının taşıyabileceği her tür sızıntıyı tek
/// exception'da toplayan sınır taklidi (dış sistem sınırı).
class _LeakyException implements Exception {
  const _LeakyException();
  @override
  String toString() =>
      'FirebaseException(permission-denied): users/uid-9f3a-SECRET/'
      'decisions/d1 — "İşten ayrılmalı mıyım?" patch={title: gizli} '
      'token=Bearer.eyJhbGciOi';
}

const _leakMarkers = <String>[
  'uid-9f3a-SECRET',
  'users/',
  'decisions/d1',
  'İşten ayrılmalı mıyım?',
  'patch=',
  'token=',
  'Bearer.eyJhbGciOi',
  'permission-denied',
  'FirebaseException',
];

class _ThrowingListRepository implements DecisionRepository {
  @override
  Stream<List<Decision>> watchAll() =>
      Stream<List<Decision>>.error(const _LeakyException());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Crashlytics sınırının taklidi: gerçekte gönderilen argümanları yakalar.
class _RecordingReporter implements CrashReporter {
  final List<String> sent = [];

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    final safe = safeFlutterErrorDetails(details);
    sent.add('${safe.exception}');
    sent.add('${safe.library}');
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    // FirebaseCrashReporter'ın gerçekte gönderdiği şey.
    sent.add('${safeCrashError(error)}');
  }
}

class _FailingPatchRepository implements DecisionRepository {
  _FailingPatchRepository(this._decision);
  final Decision _decision;

  @override
  Future<Decision?> getById(String id) async => _decision;

  @override
  Stream<Decision?> watchById(String id) => const Stream.empty();

  @override
  Future<void> applyPatch(String id, DecisionPatch patch) async =>
      throw const _LeakyException();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Home yükleme hatası: HAM exception GÖSTERİLMEZ', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(_ThrowingListRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Ekrandaki HİÇBİR metin sızıntı işareti taşımaz.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join(' | ');
    for (final marker in _leakMarkers) {
      expect(texts.contains(marker), isFalse, reason: 'sızıntı: $marker');
    }
    expect(texts.contains('Exception'), isFalse);

    // Güvenli Türkçe mesaj + tekrar deneme yolu VAR.
    expect(find.textContaining('Kararların yüklenemedi'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });

  test('Crashlytics sınırına karar içeriği/UID/yama/token GİTMEZ', () async {
    final reporter = _RecordingReporter();
    await reporter.recordError(
      const _LeakyException(),
      StackTrace.current,
      reason: 'decision_patch_failed',
    );
    await reporter.recordFlutterError(
      const FlutterErrorDetails(
        exception: _LeakyException(),
        library: 'gizli-kütüphane-adı',
      ),
    );

    final payload = reporter.sent.join(' | ');
    for (final marker in _leakMarkers) {
      expect(payload.contains(marker), isFalse, reason: 'sızıntı: $marker');
    }
  });

  test('kayıt hatasında rapor edilen içerik sanitize edilir', () async {
    final reporter = _RecordingReporter();
    final container = ProviderContainer(
      overrides: [
        decisionRepositoryProvider.overrideWithValue(
          _FailingPatchRepository(
            Decision(
              id: 'd1',
              ownerUid: 'uid-9f3a-SECRET',
              title: 'İşten ayrılmalı mıyım?',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ),
        ),
        crashReporterProvider.overrideWithValue(reporter),
        autosaveDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);

    await container.read(decisionEditorProvider('d1').future);
    final sub = container.listen(decisionEditorProvider('d1'), (_, __) {});
    addTearDown(sub.close);

    unawaited(
      container.read(decisionEditorProvider('d1').notifier).toggleFavorite(),
    );
    await container.read(decisionEditorProvider('d1').notifier).retrySave();

    expect(reporter.sent, isNotEmpty);
    final payload = reporter.sent.join(' | ');
    for (final marker in _leakMarkers) {
      expect(payload.contains(marker), isFalse, reason: 'sızıntı: $marker');
    }

    // Kullanıcıya dönen mesaj da güvenli ve Türkçe.
    final state = container.read(decisionSaveStateProvider('d1'));
    expect(state, isA<SaveFailed>());
    final message = (state as SaveFailed).message;
    for (final marker in _leakMarkers) {
      expect(message.contains(marker), isFalse, reason: 'sızıntı: $marker');
    }
  });
}
