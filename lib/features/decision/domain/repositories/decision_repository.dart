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
    this.decisionStatus,
    this.chosenOptionId,
    this.checkInStatus,
  });

  final String? title;
  final List<Option>? options;
  final List<Criterion>? criteria;
  final ScoreMatrix? scores;
  final bool? isFavorite;
  final DecisionStatus? status;

  /// Sprint B — taahhüt patch'i. [decisionStatus] YÖNETİR: `decided` iken
  /// [chosenOptionId] dolu olmalı (usecase garanti eder); `open` iken
  /// chosenOptionId/decidedAt temizlenir (geri alma). null = dokunma.
  final DecisionCommitStatus? decisionStatus;
  final String? chosenOptionId;

  /// Sprint C.2 — 1 hafta kontrol cevabı. Dolu ise checkedInAt'i data
  /// katmanı serverTimestamp ile yazar (Y-4: cihaz saati değil).
  /// null = dokunma. Bir kez yazılır, güncellenmez.
  final DecisionCheckIn? checkInStatus;

  bool get isEmpty =>
      title == null &&
      options == null &&
      criteria == null &&
      scores == null &&
      isFavorite == null &&
      status == null &&
      decisionStatus == null &&
      checkInStatus == null;

  /// Patch'i bir karara uygular (in-memory repo ve testler için).
  Decision applyTo(Decision decision) {
    if (checkInStatus != null) {
      return decision.copyWith(
        checkInStatus: checkInStatus,
        checkedInAt: DateTime.now(),
      );
    }
    if (decisionStatus == DecisionCommitStatus.decided) {
      return decision.copyWith(
        decisionStatus: DecisionCommitStatus.decided,
        chosenOptionId: chosenOptionId,
        decidedAt: DateTime.now(),
      );
    }
    if (decisionStatus == DecisionCommitStatus.open) {
      // Geri alma: taahhüt alanları temizlenir.
      return decision.copyWith(
        decisionStatus: DecisionCommitStatus.open,
        chosenOptionId: null,
        decidedAt: null,
      );
    }
    return decision.copyWith(
      title: title ?? decision.title,
      options: options ?? decision.options,
      criteria: criteria ?? decision.criteria,
      scores: scores ?? decision.scores,
      isFavorite: isFavorite ?? decision.isFavorite,
      status: status ?? decision.status,
    );
  }
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
