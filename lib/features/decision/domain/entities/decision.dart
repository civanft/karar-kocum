import 'package:freezed_annotation/freezed_annotation.dart';

part 'decision.freezed.dart';
part 'decision.g.dart';

enum DecisionStatus { draft, analyzed, archived }

enum ScoreSource { manual, ai }

enum CriterionSource { user, aiSuggested }

/// scores[optionId][criterionId] = CellScore
typedef ScoreMatrix = Map<String, Map<String, CellScore>>;

@freezed
class Decision with _$Decision {
  const Decision._();

  const factory Decision({
    required String id,
    required String ownerUid,
    required String title,
    String? templateId,
    @Default(DecisionStatus.draft) DecisionStatus status,
    @Default([]) List<Option> options,
    @Default([]) List<Criterion> criteria,
    @Default({}) ScoreMatrix scores,
    @Default(false) bool isFavorite,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Decision;

  factory Decision.fromJson(Map<String, dynamic> json) =>
      _$DecisionFromJson(json);

  /// Analiz için tüm hücreler dolu mu? (partial analize izin verilmez)
  bool get isScoreMatrixComplete {
    if (options.length < 2 || criteria.isEmpty) return false;
    for (final o in options) {
      for (final c in criteria) {
        if (scores[o.id]?[c.id] == null) return false;
      }
    }
    return true;
  }
}

@freezed
class Option with _$Option {
  const factory Option({
    required String id,
    required String title,
    String? description,
    String? imageUrl,
    @Default([]) List<String> pros,
    @Default([]) List<String> cons,
  }) = _Option;

  factory Option.fromJson(Map<String, dynamic> json) => _$OptionFromJson(json);
}

@freezed
class Criterion with _$Criterion {
  const factory Criterion({
    required String id,
    required String name,
    required int weight, // 1-10
    @Default(CriterionSource.user) CriterionSource source,
  }) = _Criterion;

  factory Criterion.fromJson(Map<String, dynamic> json) =>
      _$CriterionFromJson(json);
}

@freezed
class CellScore with _$CellScore {
  const factory CellScore({
    required int value, // 1-10
    @Default(ScoreSource.manual) ScoreSource source,
  }) = _CellScore;

  factory CellScore.fromJson(Map<String, dynamic> json) =>
      _$CellScoreFromJson(json);
}
