import '../entities/decision.dart';

/// Alan bazlı güncelleme (audit K-2 sunucu ayağı): yalnız değişen alanlar
/// yazılır — istemcinin tam-belge yazımıyla sunucu-sahipli alanları
/// (latestAnalysisId, status='analyzed') ezmesi yapısal olarak imkânsızlaşır.
/// Saf domain kavramıdır; Firestore tipleri data katmanında eşlenir.
class DecisionPatch {
  const DecisionPatch({
    this.title,
    this.options,
    this.criteria,
    this.scores,
    this.isFavorite,
    this.status,
  });

  final String? title;
  final List<Option>? options;
  final List<Criterion>? criteria;
  final ScoreMatrix? scores;
  final bool? isFavorite;
  final DecisionStatus? status;

  bool get isEmpty =>
      title == null &&
      options == null &&
      criteria == null &&
      scores == null &&
      isFavorite == null &&
      status == null;

  /// Patch'i bir karara uygular (in-memory repo ve testler için).
  Decision applyTo(Decision decision) => decision.copyWith(
        title: title ?? decision.title,
        options: options ?? decision.options,
        criteria: criteria ?? decision.criteria,
        scores: scores ?? decision.scores,
        isFavorite: isFavorite ?? decision.isFavorite,
        status: status ?? decision.status,
      );
}

/// Karar deposu sözleşmesi — TEKNIK-MIMARI.md §4.1, FIRESTORE-VERI-MODELI.md §2
abstract interface class DecisionRepository {
  /// Tüm kararlar, updatedAt azalan. Abone olunca mevcut durum HEMEN gelir.
  Stream<List<Decision>> watchAll();

  /// Tek kararın canlı akışı (audit K-2): abone olunca mevcut durum hemen
  /// gelir; harici yazımlar (ikinci cihaz, Functions) emisyon üretir.
  /// Karar silinirse null yayımlanır.
  Stream<Decision?> watchById(String id);

  Future<Decision?> getById(String id);

  /// Tam belge yazımı — YALNIZ oluşturma için kullanılmalı.
  /// Mevcut kararın mutasyonlarında [applyPatch] tercih edilir (K-2).
  Future<void> upsert(Decision decision);

  /// Alan bazlı güncelleme; updatedAt'i depo günceller
  /// (Firestore: serverTimestamp — audit Y-4).
  /// Karar yoksa [StateError] fırlatır.
  Future<void> applyPatch(String id, DecisionPatch patch);

  Future<void> delete(String id);
}
