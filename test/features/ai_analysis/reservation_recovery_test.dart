import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/pending_analysis_request_store.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/retry_directive.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Her çağrıda sıradaki sonucu veren, gönderilen requestId'leri kaydeden
/// test client'ı. Sunucunun kurtarma davranışını taklit eder.
class _ScriptedClient implements AiAnalysisClient {
  _ScriptedClient(this._script);
  final List<Object> _script;
  final List<String> requestIds = <String>[];
  int _i = 0;

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    requestIds.add(requestId);
    final result = _script[_i < _script.length ? _i : _script.length - 1];
    _i++;
    if (result is AiAnalysisFailure) throw result;
    return result as AiAnalysis;
  }
}

void main() {
  const uid = 'test-uid';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer make(AiAnalysisClient client) {
    final container = ProviderContainer(
      overrides: [
        aiAnalysisClientProvider.overrideWithValue(client),
        currentUidProvider.overrideWithValue(uid),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String?> pending(ProviderContainer c) => c
      .read(pendingAnalysisRequestStoreProvider)
      .read(uid: uid, decisionId: 'd1');

  const uncertain = AiAnalysisFailure(
    kind: AnalysisFailureKind.retryable,
    message: 'Analiz sonucu doğrulanamadı — yeni bir analiz başlatabilirsin.',
    retry: RetryDirective.newRequest,
  );
  const transport = AiAnalysisFailure(
    kind: AnalysisFailureKind.retryable,
    message: 'bağlantı hatası',
    retry: RetryDirective.sameRequest,
  );

  test(
    'uygulama kapanıp açılsa da KURTARILABİLİR istek aynı requestId ile döner',
    () async {
      // 1. oturum: taşıma hatası → anahtar korunur (iş sunucuda asılı olabilir).
      final first = _ScriptedClient([transport]);
      final c1 = make(first);
      await c1.read(analysisControllerProvider('d1').notifier).analyze();
      final preserved = first.requestIds.single;
      expect(await pending(c1), preserved);

      // 2. oturum (yeni container = yeniden başlatma): sunucu asılı işi
      // finalize eder ve saklanan sonucu döndürür.
      final second = _ScriptedClient([AiAnalysis.mock()]);
      final c2 = make(second);
      await c2.read(analysisControllerProvider('d1').notifier).analyze();

      expect(second.requestIds.single, preserved);
      expect(await pending(c2), isNull); // terminal başarı
    },
  );

  test(
    'backend stale isteği kurtarıp uncertain dönerse istemci YENİ requestId üretir',
    () async {
      final client = _ScriptedClient([uncertain, AiAnalysis.mock()]);
      final c = make(client);
      final n = c.read(analysisControllerProvider('d1').notifier);

      await n.analyze();
      expect(await pending(c), isNull); // tükenmiş anahtar temizlendi

      await n.analyze();
      expect(client.requestIds, hasLength(2));
      expect(client.requestIds[0], isNot(client.requestIds[1]));
      expect(c.read(analysisControllerProvider('d1')), isA<AnalysisSuccess>());
    },
  );

  test('tekrarlanan uncertain SONSUZ döngü kurmaz: her deneme YENİ kimlik',
      () async {
    final client = _ScriptedClient([uncertain]);
    final c = make(client);
    final n = c.read(analysisControllerProvider('d1').notifier);

    for (var i = 0; i < 5; i++) {
      await n.analyze();
    }

    expect(client.requestIds, hasLength(5));
    // Hiçbir kimlik TEKRAR kullanılmadı — sunucuda tükenmiş bir anahtar
    // ikinci kez gönderilmez.
    expect(client.requestIds.toSet(), hasLength(5));
    expect(await pending(c), isNull);
  });

  test('taşıma hatası tekrarlanırsa AYNI kimlik korunur (kurtarma penceresi)',
      () async {
    final client = _ScriptedClient([transport]);
    final c = make(client);
    final n = c.read(analysisControllerProvider('d1').notifier);

    for (var i = 0; i < 3; i++) {
      await n.analyze();
    }

    expect(client.requestIds.toSet(), hasLength(1));
    expect(await pending(c), client.requestIds.first);
  });
}
