import '../../../scoring/domain/entities/scoring_types.dart';
import '../../../scoring/domain/usecases/scoring_engine.dart';
import '../entities/decision.dart';

/// Decision entity'sini skor motoruna köprüler — tamamen yerel, senkron.
/// What-if simülatörü de bu use case üzerinden anlık yeniden hesap yapar.
class ComputeResult {
  const ComputeResult([this._engine = const ScoringEngine()]);

  final ScoringEngine _engine;

  /// Çağıran, [Decision.isScoreMatrixComplete] kontrolünü yapmış olmalı;
  /// eksik matris [IncompleteScoreMatrixException] fırlatır (motor sözleşmesi).
  DecisionResult call(Decision decision) {
    return _engine.compute(
      options: [
        for (final o in decision.options)
          ScoringOption(id: o.id, title: o.title),
      ],
      criteria: [
        for (final c in decision.criteria)
          ScoringCriterion(id: c.id, name: c.name, weight: c.weight),
      ],
      scores: {
        for (final entry in decision.scores.entries)
          entry.key: {
            for (final cell in entry.value.entries) cell.key: cell.value.value,
          },
      },
    );
  }
}
