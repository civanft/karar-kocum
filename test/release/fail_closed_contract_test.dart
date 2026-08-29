import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/mock_ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/credits_repository.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';

/// PR-RELEASE-1 — release fail-closed sözleşmesi.
///
/// Bu grup davranışı doğrular; kaynak dosyada dize araması YAPMAZ
/// (implementation yeniden yazıldığında kırılgan olmasın diye).
void main() {
  ProviderContainer unavailable() {
    final c = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.unavailable),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('release hata politikası unavailable', () {
    expect(
      firebaseFailureStatus(isReleaseMode: true),
      FirebaseStatus.unavailable,
    );
  });

  test('unavailable → mock AI istemcisi OLAMAZ', () {
    expect(
      unavailable().read(aiAnalysisClientProvider),
      isNot(isA<MockAiAnalysisClient>()),
    );
  });

  test('unavailable → sahte kredi deposu OLAMAZ', () {
    expect(
      unavailable().read(creditsRepositoryProvider),
      isNot(isA<LocalCreditsRepository>()),
    );
  });

  test('unavailable → hiçbir AI sonucu ÜRETİLMEZ', () async {
    final client = unavailable().read(aiAnalysisClientProvider);
    await expectLater(client.analyze('d1'), throwsA(isA<AiAnalysisFailure>()));
  });

  test('unavailable → hiçbir karar akışı veri YAYINLAMAZ', () async {
    final repo = unavailable().read(decisionRepositoryProvider);
    await expectLater(repo.watchAll().first, throwsA(isA<Exception>()));
  });

  test('debug/test override ile mock istemci HÂLÂ kullanılabilir', () {
    final c = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.unavailable),
        aiAnalysisClientProvider.overrideWithValue(MockAiAnalysisClient()),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(aiAnalysisClientProvider), isA<MockAiAnalysisClient>());
  });
}
