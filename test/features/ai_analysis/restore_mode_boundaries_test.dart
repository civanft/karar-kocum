import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/stored_analysis_repository.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İŞ PAKETİ 4 / DİLİM E — GERİ YÜKLEME MOD SINIRLARI.
///
/// Üretim geri yükleme akışı DEĞİŞMEDİ. Burada kayıt altına alınan şey,
/// `localMode`'un neden KALICI geri yükleme YAPMADIĞI ve hiçbir modda
/// açılış/geri yükleme sırasında ÜCRETLİ callable çağrılmadığıdır.
///
/// `localMode` gerekçesi (docs/AI-MVP-MIMARI.md ile aynı):
///  * localMode'da kullanıcı oturumu ve Firestore YOKTUR; okunacak
///    `aiAnalyses/latest` belgesi de yoktur.
///  * Analizi `MockAiAnalysisClient` üretir. Bunu kalıcılaştırmak, uydurma
///    bir analizi "kaydedilmiş sonuç" gibi geri getirirdi.
///  * Sahte bir kalıcılık katmanı, üretimdeki gerçek Firestore yolunun
///    testini ZAYIFLATIR: yeşil kalan şey üretimde çalışmayan bir yol olur.
class _RecordingClient implements AiAnalysisClient {
  int calls = 0;

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    calls++;
    return AiAnalysis.mock();
  }
}

/// Kurulursa BAŞARISIZ sayılır: bu modlarda depo hiç dinlenmemelidir.
class _ForbiddenStoredRepository implements StoredAnalysisRepository {
  int watchCalls = 0;

  @override
  Stream<AiAnalysis?> watchLatest(String decisionId) {
    watchCalls++;
    return const Stream<AiAnalysis?>.empty();
  }
}

void main() {
  const decisionId = 'd1';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({
    ProviderContainer container,
    _RecordingClient client,
    _ForbiddenStoredRepository stored,
  }) make(FirebaseStatus status, {String? uid}) {
    final client = _RecordingClient();
    final stored = _ForbiddenStoredRepository();
    final container = ProviderContainer(
      overrides: [
        aiAnalysisClientProvider.overrideWithValue(client),
        storedAnalysisRepositoryProvider.overrideWithValue(stored),
        currentUidProvider.overrideWithValue(uid),
        firebaseStatusProvider.overrideWithValue(status),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, client: client, stored: stored);
  }

  void keepAlive(ProviderContainer c) {
    final sub = c.listen(
      analysisControllerProvider(decisionId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
  }

  test('localMode: KALICI geri yükleme YOK, depo hiç dinlenmez', () async {
    final t = make(FirebaseStatus.localMode, uid: 'local-uid');
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisIdle>(),
    );
    expect(t.stored.watchCalls, 0);
    expect(t.client.calls, 0, reason: 'açılışta ücretli çağrı YOK');
  });

  test('unavailable: fail-closed — depo dinlenmez, çağrı yapılmaz', () async {
    final t = make(FirebaseStatus.unavailable, uid: 'u1');
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisIdle>(),
    );
    expect(t.stored.watchCalls, 0);
    expect(t.client.calls, 0);
  });

  test(
      'gerçek storedAnalysisRepository localMode ve unavailable\'da '
      'Firestore yolunu KURMAZ', () async {
    for (final status in [
      FirebaseStatus.localMode,
      FirebaseStatus.unavailable,
    ]) {
      final c = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWithValue('u1'),
          firebaseStatusProvider.overrideWithValue(status),
        ],
      );
      addTearDown(c.dispose);
      expect(
        c.read(storedAnalysisRepositoryProvider),
        isA<UnavailableStoredAnalysisRepository>(),
        reason: '$status Firestore deposu kurmamalı',
      );
      // Fail-closed depo boş yayınlar: hiçbir zaman uydurma sonuç dönmez.
      expect(
        await c.read(storedAnalysisRepositoryProvider).watchLatest('d1').first,
        isNull,
      );
    }
  });

  test('localMode: analiz YALNIZ açık kullanıcı eylemiyle başlar', () async {
    final t = make(FirebaseStatus.localMode, uid: 'local-uid');
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);
    expect(t.client.calls, 0);

    await t.container
        .read(analysisControllerProvider(decisionId).notifier)
        .analyze();

    expect(t.client.calls, 1, reason: 'kullanıcı eylemi çalışmaya devam eder');
    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisSuccess>(),
    );
  });

  test('ready ama OTURUM YOK: geri yükleme kurulmaz, çağrı yapılmaz', () async {
    final t = make(FirebaseStatus.ready);
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisIdle>(),
    );
    expect(t.stored.watchCalls, 0);
    expect(t.client.calls, 0);
  });
}
