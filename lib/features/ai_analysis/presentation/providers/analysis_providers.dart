import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/firebase_bootstrap.dart';
import '../../../../core/config/firebase_environment.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../data/firebase_ai_analysis_client.dart';
import '../../data/firestore_stored_analysis_repository.dart';
import '../../data/mock_ai_analysis_client.dart';
import '../../data/pending_analysis_request_store.dart';
import '../../data/unavailable_ai_analysis_client.dart';
import '../../domain/analysis_request_id.dart';
import '../../domain/entities/ai_analysis.dart';
import '../../domain/repositories/ai_analysis_client.dart';
import '../../domain/repositories/stored_analysis_repository.dart';
import '../../domain/retry_directive.dart';

/// Analiz durum makinesi — kartın 5 durumu (PR #6D-1, UI değişmedi).
sealed class AnalysisState {
  const AnalysisState();
}

/// Henüz analiz yok — CTA gösterilir.
class AnalysisIdle extends AnalysisState {
  const AnalysisIdle();
}

/// KALICI analiz okunuyor (İş Paketi 4 / Dilim A).
///
/// [AnalysisLoading] ile KARIŞTIRILMAMALIDIR: o, ücretli sağlayıcı
/// çağrısının sürdüğünü gösterir. Bu ise yalnız Firestore'daki mevcut
/// sonucun okunmasıdır — hiçbir kredi harcanmaz. Ayrı durum olması,
/// açılışta bir an "AI Analizini Başlat" CTA'sının parlamasını da önler.
class AnalysisRestoring extends AnalysisState {
  const AnalysisRestoring();
}

/// Kalıcı analiz OKUNAMADI. Yeniden deneme yalnız OKUMAYI tekrarlar;
/// sağlayıcı çağrısı yapmaz, kredi harcamaz.
class AnalysisRestoreError extends AnalysisState {
  const AnalysisRestoreError(this.message);
  final String message;
}

class AnalysisLoading extends AnalysisState {
  const AnalysisLoading();
}

class AnalysisSuccess extends AnalysisState {
  const AnalysisSuccess(this.analysis, {this.lastFailureMessage});

  final AiAnalysis analysis;

  /// Son "Yeniden Analiz Et" denemesi başarısızsa güvenli mesajı (İş
  /// Paketi 4 / Dilim B). Önceki BAŞARILI analiz ekranda kalır — kullanıcı
  /// ödediği sonucu, yeni deneme patladı diye kaybetmez.
  final String? lastFailureMessage;
}

/// YARIM KALAN analiz (İş Paketi 4 / Dilim B).
///
/// Bekleyen bir requestId var ama kalıcı sonuç yok: iş sunucuda asılı
/// kalmış olabilir. Uygulama açılır açılmaz OTOMATİK ücretli çağrı
/// YAPILMAZ — kullanıcı kredisi bilgisi dışında harcanmamalıdır. Devam
/// etmek kullanıcının açık eylemidir ve AYNI requestId ile sürer.
class AnalysisResumable extends AnalysisState {
  const AnalysisResumable();
}

class AnalysisError extends AnalysisState {
  const AnalysisError({required this.message, required this.retryable});
  final String message;
  final bool retryable;
}

class AnalysisQuotaExceeded extends AnalysisState {
  const AnalysisQuotaExceeded({required this.totalCredits});

  /// Başlangıçta verilen toplam ücretsiz kredi (yenilenmez — 6C-2).
  final int totalCredits;
}

/// AI istemcisi bağlama noktası (6D-2, PR-RELEASE-1).
///
/// Mock YALNIZ localMode'da (debug/profile/test) kullanılır. Release'de
/// bağlantı kurulamadığında (`unavailable`) mock DÖNMEZ — uydurma bir analiz
/// kullanıcıya gerçek gibi görünürdü. Testler bu provider'ı override eder.
final aiAnalysisClientProvider = Provider<AiAnalysisClient>((ref) {
  return switch (ref.watch(firebaseStatusProvider)) {
    FirebaseStatus.ready => FirebaseAiAnalysisClient(
        FirebaseFunctions.instanceFor(
          region: ref.watch(functionsRegionProvider),
        ),
      ),
    FirebaseStatus.localMode => MockAiAnalysisClient(),
    FirebaseStatus.unavailable => const UnavailableAiAnalysisClient(),
  };
});

/// KALICI analiz okuma deposu (İş Paketi 4 / Dilim A).
///
/// Fail-closed: `unavailable` ya da oturum yokken Firestore yolu KURULMAZ.
/// `localMode`'da da kurulmaz — geliştirme akışı mock analizle çalışır ve
/// üretime mock sızmaz.
final storedAnalysisRepositoryProvider = Provider<StoredAnalysisRepository>((
  ref,
) {
  final uid = ref.watch(currentUidProvider);
  final status = ref.watch(firebaseStatusProvider);
  if (status != FirebaseStatus.ready || uid == null) {
    return const UnavailableStoredAnalysisRepository();
  }
  return FirestoreStoredAnalysisRepository(
    firestore: FirebaseFirestore.instance,
    uid: uid,
  );
});

/// Karar başına analiz durumu — gövde artık gerçek callable çağırır (6D-2).
/// ARAYÜZ (analyze/reanalyze/sendFeedback + AnalysisState) DEĞİŞMEDİ.
class AnalysisController
    extends AutoDisposeFamilyNotifier<AnalysisState, String> {
  StreamSubscription<AiAnalysis?>? _restoreSub;

  @override
  AnalysisState build(String arg) {
    ref.onDispose(() {
      _restoreSub?.cancel();
      _restoreSub = null;
    });
    // Fail-closed: Firebase hazır değilse ya da oturum yoksa hiçbir
    // kullanıcı yolu kurulmaz, kalıcı analiz okunmaz ve bekleyen istek
    // sorgulanmaz — sunucu yokken sürdürülecek bir analiz de yoktur.
    // `localMode` mock akışı da bu daldan geçer ve değişmez.
    // Karar BURADA verilir: `build`'in dönüşü state'i belirler, bu yüzden
    // `_startRestore` içindeki atama ezilirdi.
    if (!_canRestore) return const AnalysisIdle();
    _startRestore();
    return const AnalysisRestoring();
  }

  /// Kalıcı analizi dinlemeye başlar. Sağlayıcı ÇAĞRILMAZ ve requestId
  /// ÜRETİLMEZ — bu yol tamamen okumadır.
  bool get _canRestore =>
      ref.read(firebaseStatusProvider) == FirebaseStatus.ready &&
      ref.read(currentUidProvider) != null;

  void _startRestore() {
    if (!_canRestore) return; // fail-closed
    _restoreSub?.cancel();
    _restoreSub =
        ref.read(storedAnalysisRepositoryProvider).watchLatest(arg).listen(
      (analysis) {
        if (analysis != null) {
          state = AnalysisSuccess(analysis);
          // Kalıcı sonuç geldi: bekleyen anahtar artık gereksizdir.
          unawaited(_clearPending());
          return;
        }
        // Kalıcı analiz yok: yalnız HENÜZ bir sonuç göstermiyorsak CTA'ya
        // ya da "yarım kalan" durumuna düş. Ekranda başarılı bir sonuç
        // varken onu silmeyiz.
        if (state is AnalysisRestoring) unawaited(_resolveIdleOrResumable());
      },
      onError: (Object _) {
        // Ham hata metni ASLA yüzeye çıkmaz.
        if (state is AnalysisSuccess) return; // mevcut sonucu boşaltma
        state = const AnalysisRestoreError(
          'Analiz yüklenemedi. Bağlantını kontrol edip tekrar dene.',
        );
      },
    );
  }

  /// Kalıcı sonuç yokken: bekleyen istek varsa kullanıcıya "sürdür"
  /// seçeneği sunulur, yoksa normal CTA gösterilir. Hiçbir durumda
  /// otomatik sağlayıcı çağrısı YAPILMAZ.
  Future<void> _resolveIdleOrResumable() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      if (state is AnalysisRestoring) state = const AnalysisIdle();
      return;
    }
    final pending = await ref
        .read(pendingAnalysisRequestStoreProvider)
        .read(uid: uid, decisionId: arg);
    if (state is! AnalysisRestoring) return; // arada durum değiştiyse dokunma
    state = pending == null ? const AnalysisIdle() : const AnalysisResumable();
  }

  Future<void> _clearPending() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref
        .read(pendingAnalysisRequestStoreProvider)
        .clear(uid: uid, decisionId: arg);
  }

  /// Okuma hatasından sonra YALNIZ okumayı yeniden başlatır.
  Future<void> retryRestore() async {
    state = const AnalysisRestoring();
    _startRestore();
  }

  Future<void> analyze() async {
    if (state is AnalysisLoading) return; // çift istek koruması (6B kararı)
    // Ekranda ödenmiş bir analiz varsa onu SAKLA: yeni deneme başarısız
    // olursa kullanıcı eski sonucunu kaybetmemeli (İş Paketi 4 / Dilim B).
    final previous =
        state is AnalysisSuccess ? (state as AnalysisSuccess).analysis : null;
    state = const AnalysisLoading();

    unawaited(
      ref.read(analyticsServiceProvider).logAnalysisRequested(tier: 'basic'),
    );

    // İDEMPOTENCY ANAHTARI (İş Paketi 2): tek kullanıcı eylemi için BİR kez
    // üretilir. Süreç kesintisi sonrası bekleyen anahtar geri alınır, böylece
    // retry sunucudaki journal'ı sağlayıcıyı YENİDEN ÇAĞIRMADAN finalize eder.
    final uid = ref.read(currentUidProvider);
    final store = ref.read(pendingAnalysisRequestStoreProvider);
    String requestId;
    if (uid == null) {
      // Oturum yoksa kalıcılık alanı yok; tek seferlik anahtar yeterli.
      requestId = newAnalysisRequestId();
    } else {
      requestId =
          await store.read(uid: uid, decisionId: arg) ?? newAnalysisRequestId();
      await store.write(uid: uid, decisionId: arg, requestId: requestId);
    }

    Future<void> clearPending() async {
      if (uid != null) {
        await store.clear(uid: uid, decisionId: arg);
      }
    }

    try {
      final analysis = await ref
          .read(aiAnalysisClientProvider)
          .analyze(decisionId: arg, requestId: requestId);
      await clearPending(); // terminal başarı
      state = AnalysisSuccess(analysis);
      unawaited(
        ref.read(analyticsServiceProvider).logAnalysisCompleted(
              tier: 'basic',
              latencyMs: 0, // sunucu tarafı ölçüyor; istemci süresi Sprint 3+
              cached: false,
            ),
      );
    } on AiAnalysisFailure catch (f) {
      // Bekleyen anahtarın kaderini SUNUCUNUN yönergesi belirler (2B).
      // `sameRequest` DIŞINDAKİ her durumda anahtar temizlenir: aksi halde
      // sunucuda tükenmiş bir requestId sonsuza kadar tekrar gönderilirdi.
      if (f.retry != RetryDirective.sameRequest) {
        await clearPending();
      }
      state = _failureState(f, previous);
    } catch (_) {
      // Beklenmedik istisna: çağrının sunucuya ulaşıp ulaşmadığı BİLİNMİYOR.
      // Bekleyen anahtar KORUNUR (sameRequest); iş tamamlanmışsa bir sonraki
      // deneme saklanan sonucu getirir, hiç başlamamışsa baştan çalışır.
      const message = 'Analiz şu an yapılamadı, birazdan tekrar dene.';
      state = previous == null
          ? const AnalysisError(message: message, retryable: true)
          : AnalysisSuccess(previous, lastFailureMessage: message);
    }
  }

  /// Başarısızlık durumu — ÖNCEKİ başarılı analiz varsa o ekranda kalır ve
  /// hata ayrı bir alanda taşınır. Kullanıcı ödediği sonucu, yeni deneme
  /// patladı diye kaybetmez.
  AnalysisState _failureState(AiAnalysisFailure f, AiAnalysis? previous) {
    if (f.kind == AnalysisFailureKind.quotaExceeded && previous == null) {
      return AnalysisQuotaExceeded(totalCredits: f.totalCredits ?? 5);
    }
    if (previous != null) {
      return AnalysisSuccess(previous, lastFailureMessage: f.message);
    }
    return AnalysisError(
      message: f.message,
      retryable: f.kind == AnalysisFailureKind.retryable,
    );
  }

  /// "Yeniden analiz et" onayından sonra çağrılır.
  ///
  /// AÇIK kullanıcı eylemi → YENİ idempotency anahtarı: bekleyen anahtar
  /// silinir, böylece sunucuda yeni bir analiz üretilir.
  Future<void> reanalyze() async {
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      await ref
          .read(pendingAnalysisRequestStoreProvider)
          .clear(uid: uid, decisionId: arg);
    }
    // Durum SIFIRLANMAZ: mevcut başarılı analiz, yeni deneme sonuçlanana
    // kadar ekranda kalmalı (İş Paketi 4 / Dilim B).
    return analyze();
  }

  /// 👍/👎 — analysis_feedback olayı (6D-2 bağlandı).
  void sendFeedback({required bool thumbsUp}) {
    unawaited(
      ref.read(analyticsServiceProvider).logAnalysisFeedback(
            thumbsUp: thumbsUp,
          ),
    );
  }
}

final analysisControllerProvider = NotifierProvider.autoDispose
    .family<AnalysisController, AnalysisState, String>(AnalysisController.new);
