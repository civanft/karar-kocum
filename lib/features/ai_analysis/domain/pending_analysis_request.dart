/// Bekleyen analiz isteği deposu sözleşmesi (İş Paketi 2).
///
/// Saf domain: platform tipi yoktur. Yalnız idempotency ANAHTARI saklanır —
/// karar metni ya da başka hassas içerik ASLA.
abstract interface class PendingAnalysisRequestStore {
  Future<String?> read({required String uid, required String decisionId});

  Future<void> write({
    required String uid,
    required String decisionId,
    required String requestId,
  });

  /// Terminal sonuç (başarı veya kalıcı hata) sonrası temizlenir.
  Future<void> clear({required String uid, required String decisionId});

  /// Hesap/yerel veri silme akışında tüm bekleyen istekleri siler.
  Future<void> clearAll();
}
