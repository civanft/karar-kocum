/// Skor motoru tipleri — saf Dart, flutter import YOK (TEKNIK-MIMARI.md AD-2).
library;

class ScoringOption {
  const ScoringOption({required this.id, required this.title});
  final String id;
  final String title;
}

class ScoringCriterion {
  const ScoringCriterion({
    required this.id,
    required this.name,
    required this.weight, // 1-10
  }) : assert(weight >= 1 && weight <= 10);
  final String id;
  final String name;
  final int weight;
}

/// scores[optionId][criterionId] = 1-10
typedef ScoreMatrix = Map<String, Map<String, int>>;

enum Confidence { low, medium, high }

class OptionScore {
  const OptionScore({required this.optionId, required this.score});

  /// 0-100 ölçeğinde ağırlıklı skor.
  final String optionId;
  final double score;
}

class DecisionResult {
  const DecisionResult({
    required this.ranking, // skora göre azalan sıralı
    required this.recommendedOptionId,
    required this.confidence,
  });
  final List<OptionScore> ranking;
  final String recommendedOptionId;
  final Confidence confidence;
}

class IncompleteScoreMatrixException implements Exception {
  const IncompleteScoreMatrixException(this.missing);

  /// Eksik (optionId, criterionId) çiftleri — partial analize izin verilmez.
  final List<(String optionId, String criterionId)> missing;
}
