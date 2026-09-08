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

/// İŞ PAKETİ 4 / DİLİM A — kalıcı analizin geri yüklenmesi.
///
/// Backend analizi `users/{uid}/decisions/{id}/aiAnalyses/latest` yoluna
/// yazıyor ama istemci bunu HİÇ okumuyordu: uygulama kapanıp açıldığında
/// kullanıcı ödediği analizi kaybediyor ve karşısında yeniden "AI Analizini
/// Başlat" CTA'sı buluyordu. Tekrar basmak yeni bir requestId ve YENİ BİR
/// KREDİ harcaması demekti.
class _RecordingClient implements AiAnalysisClient {
  int calls = 0;
  final List<String> requestIds = <String>[];

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    calls++;
    requestIds.add(requestId);
    return AiAnalysis.mock();
  }
}

/// Kontrollü kalıcı analiz deposu — dış sistem sınırında sahte.
class _FakeStoredAnalysisRepository implements StoredAnalysisRepository {
  _FakeStoredAnalysisRepository();

  final _controllers = <String, StreamController<AiAnalysis?>>{};
  int watchCalls = 0;

  StreamController<AiAnalysis?> _controllerFor(String decisionId) =>
      _controllers.putIfAbsent(
        decisionId,
        () => StreamController<AiAnalysis?>.broadcast(),
      );

  void emit(String decisionId, AiAnalysis? analysis) =>
      _controllerFor(decisionId).add(analysis);

  void fail(String decisionId, Object error) =>
      _controllerFor(decisionId).addError(error);

  @override
  Stream<AiAnalysis?> watchLatest(String decisionId) {
    watchCalls++;
    return _controllerFor(decisionId).stream;
  }
}

void main() {
  const uid = 'test-uid';
  const decisionId = 'd1';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({
    ProviderContainer container,
    _RecordingClient client,
    _FakeStoredAnalysisRepository stored,
  }) make() {
    final client = _RecordingClient();
    final stored = _FakeStoredAnalysisRepository();
    final container = ProviderContainer(
      overrides: [
        aiAnalysisClientProvider.overrideWithValue(client),
        storedAnalysisRepositoryProvider.overrideWithValue(stored),
        currentUidProvider.overrideWithValue(uid),
        // Restore yalnız Firebase HAZIRKEN çalışır (fail-closed sözleşme).
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, client: client, stored: stored);
  }

  AnalysisState read(ProviderContainer c) =>
      c.read(analysisControllerProvider(decisionId));

  /// Controller'ı canlı tut: autoDispose provider aksi hâlde okunur okunmaz
  /// atılır ve restore akışı gözlenemez.
  void keepAlive(ProviderContainer c) {
    final sub = c.listen(
      analysisControllerProvider(decisionId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
  }

  test('ilk durum RESTORING olur — Idle CTA flicker YAPMAZ', () async {
    final t = make();
    keepAlive(t.container);
    expect(read(t.container), isA<AnalysisRestoring>());
  });

  test('kalıcı latest analiz ilk girişte GÖSTERİLİR, callable ÇAĞRILMAZ',
      () async {
    final t = make();
    keepAlive(t.container);
    t.stored.emit(decisionId, AiAnalysis.mock());
    await Future<void>.delayed(Duration.zero);

    expect(read(t.container), isA<AnalysisSuccess>());
    expect(t.client.calls, 0);
  });

  test('belge YOKSA Idle olur ve analiz kendiliğinden başlamaz', () async {
    final t = make();
    keepAlive(t.container);
    t.stored.emit(decisionId, null);
    await Future<void>.delayed(Duration.zero);

    expect(read(t.container), isA<AnalysisIdle>());
    expect(t.client.calls, 0);
  });

  test('re-entry / autoDispose sonrası analiz GERİ GELİR, yeni istek YOK',
      () async {
    final t = make();
    var sub = t.container.listen(
      analysisControllerProvider(decisionId),
      (_, __) {},
      fireImmediately: true,
    );
    t.stored.emit(decisionId, AiAnalysis.mock());
    await Future<void>.delayed(Duration.zero);
    expect(read(t.container), isA<AnalysisSuccess>());

    // Ekrandan çık: autoDispose provider atılır.
    sub.close();
    await Future<void>.delayed(Duration.zero);

    // Geri gir: yeniden kurulur ve kalıcı analizi tekrar okur.
    sub = t.container.listen(
      analysisControllerProvider(decisionId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    t.stored.emit(decisionId, AiAnalysis.mock());
    await Future<void>.delayed(Duration.zero);

    expect(read(t.container), isA<AnalysisSuccess>());
    expect(t.client.calls, 0);
  });

  test('okuma hatası güvenli RESTORE HATASI verir, raw exception SIZMAZ',
      () async {
    final t = make();
    keepAlive(t.container);
    t.stored.fail(decisionId, StateError('permission-denied: users/$uid/...'));
    await Future<void>.delayed(Duration.zero);

    final state = read(t.container);
    expect(state, isA<AnalysisRestoreError>());
    final message = (state as AnalysisRestoreError).message;
    expect(message, isNot(contains('permission-denied')));
    expect(message, isNot(contains(uid)));
    expect(message, isNotEmpty);
  });

  test('read-retry ANALİZ ÇAĞIRMAZ, yalnız okumayı yeniden başlatır', () async {
    final t = make();
    keepAlive(t.container);
    t.stored.fail(decisionId, StateError('boom'));
    await Future<void>.delayed(Duration.zero);
    final before = t.stored.watchCalls;

    await t.container
        .read(analysisControllerProvider(decisionId).notifier)
        .retryRestore();

    expect(t.stored.watchCalls, greaterThan(before));
    expect(t.client.calls, 0);
  });

  test('mevcut başarılı analiz varken okuma hatası ekranı BOŞALTMAZ', () async {
    final t = make();
    keepAlive(t.container);
    t.stored.emit(decisionId, AiAnalysis.mock());
    await Future<void>.delayed(Duration.zero);
    expect(read(t.container), isA<AnalysisSuccess>());

    t.stored.fail(decisionId, StateError('network'));
    await Future<void>.delayed(Duration.zero);

    expect(read(t.container), isA<AnalysisSuccess>());
  });

  test('UID yoksa fail-closed: depo hiç dinlenmez, callable çağrılmaz',
      () async {
    final client = _RecordingClient();
    final stored = _FakeStoredAnalysisRepository();
    final container = ProviderContainer(
      overrides: [
        aiAnalysisClientProvider.overrideWithValue(client),
        storedAnalysisRepositoryProvider.overrideWithValue(stored),
        currentUidProvider.overrideWithValue(null),
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      analysisControllerProvider(decisionId),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    expect(stored.watchCalls, 0);
    expect(client.calls, 0);
    expect(
      container.read(analysisControllerProvider(decisionId)),
      isA<AnalysisIdle>(),
    );
  });
}
