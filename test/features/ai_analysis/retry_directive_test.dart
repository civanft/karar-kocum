import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/pending_analysis_request_store.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/retry_directive.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gönderilen requestId'leri kaydeden, istenen sonucu üreten test client'ı.
class _RecordingClient implements AiAnalysisClient {
  _RecordingClient(this._result);
  final Object _result;
  final List<String> requestIds = <String>[];

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    requestIds.add(requestId);
    if (_result is AiAnalysisFailure) throw _result;
    return _result as AiAnalysis;
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

  AiAnalysisFailure failure(RetryDirective retry) => AiAnalysisFailure(
        kind: retry == RetryDirective.none
            ? AnalysisFailureKind.nonRetryable
            : AnalysisFailureKind.retryable,
        message: 'hata',
        retry: retry,
      );

  group('retry yönergesi — bekleyen requestId yaşam döngüsü', () {
    test('newRequest: bekleyen anahtar TEMİZLENİR, sonraki deneme YENİ ID',
        () async {
      final client = _RecordingClient(failure(RetryDirective.newRequest));
      final c = make(client);
      final n = c.read(analysisControllerProvider('d1').notifier);

      await n.analyze();
      expect(await pending(c), isNull);

      await n.analyze();
      expect(client.requestIds, hasLength(2));
      expect(client.requestIds[0], isNot(client.requestIds[1]));
    });

    test('sameRequest: bekleyen anahtar KORUNUR, sonraki deneme AYNI ID',
        () async {
      final client = _RecordingClient(failure(RetryDirective.sameRequest));
      final c = make(client);
      final n = c.read(analysisControllerProvider('d1').notifier);

      await n.analyze();
      expect(await pending(c), isNotNull);

      await n.analyze();
      expect(client.requestIds[0], client.requestIds[1]);
    });

    test('none: bekleyen anahtar temizlenir ve retry SUNULMAZ', () async {
      final client = _RecordingClient(failure(RetryDirective.none));
      final c = make(client);
      final n = c.read(analysisControllerProvider('d1').notifier);

      await n.analyze();

      expect(await pending(c), isNull);
      final state = c.read(analysisControllerProvider('d1'));
      expect(state, isA<AnalysisError>());
      expect((state as AnalysisError).retryable, isFalse);
    });
  });

  group('backend hata kodu → yönerge eşlemesi', () {
    test('ai-uncertain SONSUZ döngü kurmaz: newRequest', () {
      expect(retryDirectiveFor('ai-uncertain'), RetryDirective.newRequest);
    });

    test('app-check-replay AYNI istekle tekrarlanır: iş journal\'a ulaşmadı',
        () {
      expect(retryDirectiveFor('app-check-replay'), RetryDirective.sameRequest);
    });

    test('finalize bekleyen internal hata AYNI istekle tamamlanır', () {
      expect(retryDirectiveFor('internal'), RetryDirective.sameRequest);
    });

    test('bilinmeyen/ağ hatası güvenli tarafta: sameRequest', () {
      expect(retryDirectiveFor(null), RetryDirective.sameRequest);
      expect(retryDirectiveFor('unavailable'), RetryDirective.sameRequest);
    });

    test('rate-limited ve breaker ai-unavailable: newRequest', () {
      expect(retryDirectiveFor('rate-limited'), RetryDirective.newRequest);
      expect(retryDirectiveFor('ai-unavailable'), RetryDirective.newRequest);
    });

    test('superseded ve terminal sağlayıcı hatası: newRequest', () {
      expect(retryDirectiveFor('superseded'), RetryDirective.newRequest);
      expect(retryDirectiveFor('ai-failed'), RetryDirective.newRequest);
    });

    test('kota/limit/moderasyon/geçersiz istek: none', () {
      for (final code in [
        'quota-exceeded',
        'daily-limit',
        'moderated',
        'invalid-argument',
      ]) {
        expect(retryDirectiveFor(code), RetryDirective.none, reason: code);
      }
    });

    test('sunucunun açık yönergesi kod tablosunu EZER', () {
      expect(
        retryDirectiveFor('internal', serverDirective: 'new'),
        RetryDirective.newRequest,
      );
      expect(
        retryDirectiveFor('ai-uncertain', serverDirective: 'none'),
        RetryDirective.none,
      );
      // Tanınmayan yönerge yok sayılır; kod tablosuna düşülür.
      expect(
        retryDirectiveFor('ai-uncertain', serverDirective: 'saçma'),
        RetryDirective.newRequest,
      );
    });
  });

  group('kullanıcı eylemleri', () {
    test('reanalyze DAİMA yeni requestId üretir', () async {
      final client = _RecordingClient(failure(RetryDirective.sameRequest));
      final c = make(client);
      final n = c.read(analysisControllerProvider('d1').notifier);

      await n.analyze();
      final first = client.requestIds.single;
      expect(await pending(c), first);

      await n.reanalyze();
      expect(client.requestIds, hasLength(2));
      expect(client.requestIds[1], isNot(first));
    });

    test(
        'yeniden başlatma: yalnız KURTARILABİLİR bekleyen istek aynı ID ile sürer',
        () async {
      // 1. oturum: sameRequest hatası → anahtar korunur.
      final first = _RecordingClient(failure(RetryDirective.sameRequest));
      final c1 = make(first);
      await c1.read(analysisControllerProvider('d1').notifier).analyze();
      final preserved = first.requestIds.single;

      // 2. oturum (yeni container = yeniden başlatma): aynı ID devam eder.
      final second = _RecordingClient(AiAnalysis.mock());
      final c2 = make(second);
      await c2.read(analysisControllerProvider('d1').notifier).analyze();
      expect(second.requestIds.single, preserved);

      // Başarı terminaldir: anahtar temizlenir, sonraki analiz YENİ ID alır.
      expect(await pending(c2), isNull);
      final third = _RecordingClient(AiAnalysis.mock());
      final c3 = make(third);
      await c3.read(analysisControllerProvider('d1').notifier).analyze();
      expect(third.requestIds.single, isNot(preserved));
    });
  });
}
