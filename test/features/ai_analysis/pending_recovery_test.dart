import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/pending_analysis_request_store.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/stored_analysis_repository.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/retry_directive.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İŞ PAKETİ 4 / DİLİM B — yarım kalan analizin güvenli sürdürülmesi.
///
/// Bekleyen requestId varken uygulama açıldığında kullanıcı ne olduğunu
/// göremiyordu. Otomatik ücretli çağrı da yapılmamalı: kullanıcı kredisi
/// onun bilgisi dışında harcanmamalıdır.
class _ScriptedClient implements AiAnalysisClient {
  _ScriptedClient(this._script);
  final List<Object> _script;
  final List<String> requestIds = <String>[];
  int _i = 0;
  int get calls => requestIds.length;

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

class _FakeStored implements StoredAnalysisRepository {
  _FakeStored(this._value);
  final AiAnalysis? _value;
  @override
  Stream<AiAnalysis?> watchLatest(String decisionId) =>
      Stream<AiAnalysis?>.value(_value);
}

void main() {
  const uid = 'test-uid';
  const decisionId = 'd1';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({ProviderContainer container, _ScriptedClient client}) make({
    AiAnalysis? stored,
    List<Object> script = const [],
  }) {
    final client =
        _ScriptedClient(script.isEmpty ? [AiAnalysis.mock()] : script);
    final container = ProviderContainer(
      overrides: [
        aiAnalysisClientProvider.overrideWithValue(client),
        storedAnalysisRepositoryProvider.overrideWithValue(_FakeStored(stored)),
        currentUidProvider.overrideWithValue(uid),
        // Restore yalnız Firebase HAZIRKEN çalışır (fail-closed sözleşme).
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, client: client);
  }

  void keepAlive(ProviderContainer c) {
    final sub = c.listen(
      analysisControllerProvider(decisionId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
  }

  Future<void> seedPending(ProviderContainer c, String requestId) => c
      .read(pendingAnalysisRequestStoreProvider)
      .write(uid: uid, decisionId: decisionId, requestId: requestId);

  Future<String?> pending(ProviderContainer c) => c
      .read(pendingAnalysisRequestStoreProvider)
      .read(uid: uid, decisionId: decisionId);

  const pendingId = 'aaaaaaaaaaaaaaaaaaaaaaaa';

  test('pending + latest VAR → Success, pending TEMİZLENİR, callable 0',
      () async {
    final t = make(stored: AiAnalysis.mock());
    await seedPending(t.container, pendingId);
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisSuccess>(),
    );
    expect(await pending(t.container), isNull);
    expect(t.client.calls, 0);
  });

  test('pending + latest YOK → recovery durumu, OTOMATİK çağrı YOK', () async {
    final t = make(stored: null);
    await seedPending(t.container, pendingId);
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisResumable>(),
    );
    expect(t.client.calls, 0);
  });

  test('recovery devam edilince AYNI requestId kullanılır', () async {
    final t = make(stored: null, script: [AiAnalysis.mock()]);
    await seedPending(t.container, pendingId);
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    await t.container
        .read(analysisControllerProvider(decisionId).notifier)
        .analyze();

    expect(t.client.requestIds, [pendingId]);
  });

  test('başarısız reanalyze ESKİ başarılı sonucu ekranda BIRAKIR', () async {
    const failure = AiAnalysisFailure(
      kind: AnalysisFailureKind.retryable,
      message: 'Analiz şu an yapılamadı.',
      retry: RetryDirective.newRequest,
    );
    final t = make(stored: AiAnalysis.mock(), script: [failure]);
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);
    expect(
      t.container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisSuccess>(),
    );

    await t.container
        .read(analysisControllerProvider(decisionId).notifier)
        .reanalyze();

    final state = t.container.read(analysisControllerProvider(decisionId));
    // Önceki analiz KAYBOLMAZ; hata AYRI biçimde taşınır.
    expect(state, isA<AnalysisSuccess>());
    expect((state as AnalysisSuccess).lastFailureMessage, isNotNull);
    expect(state.lastFailureMessage, isNot(contains('Exception')));
  });

  test('terminal hata STALE pending bırakmaz', () async {
    const terminal = AiAnalysisFailure(
      kind: AnalysisFailureKind.nonRetryable,
      message: 'Bu içerik analiz edilemiyor.',
      retry: RetryDirective.none,
    );
    final t = make(stored: null, script: [terminal]);
    keepAlive(t.container);
    await Future<void>.delayed(Duration.zero);

    await t.container
        .read(analysisControllerProvider(decisionId).notifier)
        .analyze();

    expect(await pending(t.container), isNull);
  });
}
