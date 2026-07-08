import '../entities/scoring_types.dart';

/// Ağırlıklı skor motoru — deterministik, senkron, %100 test kapsamı hedefi.
///
/// skor(seçenek) = Σ (normalizeAğırlık(kriter) × hücrePuanı) → 0-100 ölçeği
///   normalizeAğırlık = kriterAğırlığı / toplamAğırlık
///   0-100 ölçeği: hücre puanları 1-10 → (ham - 1) / 9 × 100
///
/// Eksik hücre analiz engelidir (yanıltıcı sonuç üretmemek için) —
/// IncompleteScoreMatrixException fırlatılır.
class ScoringEngine {
  const ScoringEngine();

  DecisionResult compute({
    required List<ScoringOption> options,
    required List<ScoringCriterion> criteria,
    required ScoreMatrix scores,
  }) {
    if (options.length < 2) {
      throw ArgumentError(
        'En az 2 seçenek gerekli, ${options.length} verildi.',
      );
    }
    if (criteria.isEmpty) {
      throw ArgumentError('En az 1 kriter gerekli.');
    }

    _ensureComplete(options, criteria, scores);

    final totalWeight =
        criteria.fold<int>(0, (sum, c) => sum + c.weight).toDouble();

    final ranking = options.map((option) {
      var weighted = 0.0;
      for (final criterion in criteria) {
        final raw = scores[option.id]![criterion.id]!;
        final normalized = (raw - 1) / 9.0; // 1-10 → 0-1
        weighted += (criterion.weight / totalWeight) * normalized;
      }
      return OptionScore(optionId: option.id, score: weighted * 100);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return DecisionResult(
      ranking: ranking,
      recommendedOptionId: ranking.first.optionId,
      confidence: _confidence(ranking, criteria.length),
    );
  }

  void _ensureComplete(
    List<ScoringOption> options,
    List<ScoringCriterion> criteria,
    ScoreMatrix scores,
  ) {
    final missing = <(String, String)>[];
    for (final o in options) {
      for (final c in criteria) {
        final value = scores[o.id]?[c.id];
        if (value == null) {
          missing.add((o.id, c.id));
        } else if (value < 1 || value > 10) {
          throw ArgumentError(
            'Puan 1-10 aralığında olmalı: ${o.id}/${c.id} = $value',
          );
        }
      }
    }
    if (missing.isNotEmpty) throw IncompleteScoreMatrixException(missing);
  }

  /// Güven seviyesi: 1. ve 2. seçenek arasındaki skor farkı + kriter sayısı.
  /// AI'dan gelen nitel güven yorumu sonuç ekranında bununla birleştirilir.
  Confidence _confidence(List<OptionScore> ranking, int criterionCount) {
    final gap = ranking[0].score - ranking[1].score;
    if (gap >= 15 && criterionCount >= 3) return Confidence.high;
    if (gap >= 5) return Confidence.medium;
    return Confidence.low;
  }
}
