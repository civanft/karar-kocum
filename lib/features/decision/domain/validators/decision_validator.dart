import '../../../../core/constants/limits.dart';
import '../../../../core/error/failure.dart';
import '../entities/decision.dart';

/// PRD kabul kriterleri (§5) — saf Dart, %100 birim test hedefi.
/// Aynı kurallar Firestore rules ve Functions'ta da zorlanır (üç katman).
abstract final class DecisionValidator {
  static ValidationFailure? title(String value) {
    final trimmed = value.trim();
    if (trimmed.length < Limits.titleMinLength) {
      return const ValidationFailure(
        field: 'title',
        message: 'Başlık en az 3 karakter olmalı.',
      );
    }
    if (trimmed.length > Limits.titleMaxLength) {
      return const ValidationFailure(
        field: 'title',
        message: 'Başlık en fazla 100 karakter olabilir.',
      );
    }
    return null;
  }

  static ValidationFailure? optionTitle(String value) {
    if (value.trim().isEmpty) {
      return const ValidationFailure(
        field: 'optionTitle',
        message: 'Seçenek adı boş olamaz.',
      );
    }
    return null;
  }

  static ValidationFailure? prosConsItem(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const ValidationFailure(
        field: 'prosConsItem',
        message: 'Madde boş olamaz.',
      );
    }
    if (trimmed.length > Limits.prosConsItemMaxLength) {
      return const ValidationFailure(
        field: 'prosConsItem',
        message: 'Madde en fazla 140 karakter olabilir.',
      );
    }
    return null;
  }

  static ValidationFailure? criterionWeight(int value) {
    if (value < Limits.criterionWeightMin ||
        value > Limits.criterionWeightMax) {
      return const ValidationFailure(
        field: 'criterionWeight',
        message: 'Önem puanı 1-10 aralığında olmalı.',
      );
    }
    return null;
  }

  static ValidationFailure? cellScore(int value) {
    if (value < Limits.scoreMin || value > Limits.scoreMax) {
      return const ValidationFailure(
        field: 'cellScore',
        message: 'Puan 1-10 aralığında olmalı.',
      );
    }
    return null;
  }

  static bool canAddOption(Decision decision) =>
      decision.options.length < Limits.maxOptions;

  /// Analize hazırlık kontrolü — sonuç ekranına geçiş kapısı.
  /// Boş liste = hazır.
  static List<ValidationFailure> readyForResult(Decision decision) {
    final failures = <ValidationFailure>[];
    if (decision.options.length < Limits.minOptions) {
      failures.add(
        const ValidationFailure(
          field: 'options',
          message: 'En az 2 seçenek ekleyin.',
        ),
      );
    }
    if (decision.criteria.isEmpty) {
      failures.add(
        const ValidationFailure(
          field: 'criteria',
          message: 'En az 1 kriter ekleyin.',
        ),
      );
    }
    if (decision.options.length >= Limits.minOptions &&
        decision.criteria.isNotEmpty &&
        !decision.isScoreMatrixComplete) {
      failures.add(
        const ValidationFailure(
          field: 'scores',
          message: 'Tüm seçenekleri tüm kriterlerde puanlayın.',
        ),
      );
    }
    return failures;
  }
}
