import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/mock_ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/credits_repository.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';

/// PR-RELEASE-1 — defense-in-depth: başlangıç kapısı aşılsa BİLE
/// `unavailable` altında hiçbir sahte veri üretilmez.
ProviderContainer containerFor(FirebaseStatus status) {
  final c = ProviderContainer(
    overrides: [firebaseStatusProvider.overrideWithValue(status)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('C. AI istemcisi seçimi', () {
    test('localMode → mock istemci (geliştirme akışı korunur)', () {
      expect(
        containerFor(FirebaseStatus.localMode).read(aiAnalysisClientProvider),
        isA<MockAiAnalysisClient>(),
      );
    });

    test('unavailable → mock DEĞİL', () {
      expect(
        containerFor(FirebaseStatus.unavailable).read(aiAnalysisClientProvider),
        isNot(isA<MockAiAnalysisClient>()),
      );
    });

    test('unavailable → retryable AiAnalysisFailure, sahte analiz YOK',
        () async {
      final client = containerFor(FirebaseStatus.unavailable)
          .read(aiAnalysisClientProvider);

      await expectLater(
        client.analyze(decisionId: 'd1', requestId: 'a' * 24),
        throwsA(
          isA<AiAnalysisFailure>()
              .having((e) => e.kind, 'kind', AnalysisFailureKind.retryable)
              .having(
                (e) => e.message,
                'message',
                'Servise bağlanılamadı. Bağlantını kontrol edip tekrar dene.',
              ),
        ),
      );
    });
  });

  group('D. Karar deposu seçimi', () {
    // NOT: depo FollowUpAwareDecisionRepository ile SARMALANIR, bu yüzden
    // tip kontrolü her durumda geçer (yanıltıcı). DAVRANIŞ karşılaştırılır.
    test('localMode → çalışan yerel depo (geliştirme akışı korunur)', () async {
      final repo = containerFor(FirebaseStatus.localMode)
          .read(decisionRepositoryProvider);
      await expectLater(repo.watchAll().first, completion(isEmpty));
    });

    test('unavailable → yerel depo davranışı YOK', () async {
      final repo = containerFor(FirebaseStatus.unavailable)
          .read(decisionRepositoryProvider);
      await expectLater(repo.watchAll().first, throwsA(isA<Exception>()));
    });

    test('unavailable → tüm işlemler güvenli biçimde reddedilir', () async {
      final repo = containerFor(FirebaseStatus.unavailable)
          .read(decisionRepositoryProvider);

      await expectLater(repo.watchAll().first, throwsA(isA<Exception>()));
      await expectLater(repo.getById('d1'), throwsA(isA<Exception>()));
      await expectLater(repo.delete('d1'), throwsA(isA<Exception>()));
    });
  });

  group('E. Kredi deposu seçimi', () {
    test('localMode → LocalCreditsRepository (geliştirme akışı korunur)', () {
      expect(
        containerFor(FirebaseStatus.localMode).read(creditsRepositoryProvider),
        isA<LocalCreditsRepository>(),
      );
    });

    test('unavailable → LocalCreditsRepository DEĞİL', () {
      expect(
        containerFor(FirebaseStatus.unavailable)
            .read(creditsRepositoryProvider),
        isNot(isA<LocalCreditsRepository>()),
      );
    });

    test('unavailable → SAHTE kredi sayısı yayınlanmaz', () async {
      final repo = containerFor(FirebaseStatus.unavailable)
          .read(creditsRepositoryProvider);
      await expectLater(repo.watchRemaining().first, throwsA(isA<Exception>()));
    });
  });
}
