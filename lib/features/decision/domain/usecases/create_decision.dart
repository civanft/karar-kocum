import '../../../../core/error/failure.dart';
import '../../../../core/services/id_generator.dart';
import '../entities/decision.dart';
import '../repositories/decision_repository.dart';
import '../validators/decision_validator.dart';

/// Yeni karar taslağı oluşturur.
/// Kota kontrolü Sprint 5'te bu use case'in ÖNÜNE eklenir (sunucu doğrulamalı).
class CreateDecision {
  const CreateDecision(this._repository, this._idGenerator);

  final DecisionRepository _repository;
  final IdGenerator _idGenerator;

  Future<Result<Decision>> call({
    required String ownerUid,
    required String title,
    String? templateId,
  }) async {
    final titleFailure = DecisionValidator.title(title);
    if (titleFailure != null) return Err(titleFailure);

    final now = DateTime.now();
    final decision = Decision(
      id: _idGenerator(),
      ownerUid: ownerUid,
      title: title.trim(),
      templateId: templateId,
      createdAt: now,
      updatedAt: now,
    );

    await _repository.upsert(decision);
    return Ok(decision);
  }
}
