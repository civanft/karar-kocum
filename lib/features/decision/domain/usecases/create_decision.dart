import '../../../../core/error/failure.dart';
import '../../../../core/services/id_generator.dart';
import '../entities/decision.dart';
import '../repositories/decision_repository.dart';
import '../validators/decision_validator.dart';

/// Yeni karar taslağı oluşturur.
/// Kota kontrolü Sprint 5'te bu use case'in ÖNÜNE eklenir (sunucu doğrulamalı).
///
/// Şablon yolu (PR-A1): [initialCriteria]/[initialOptions] record listesi
/// alır — templates feature'ına İMPORT YOK (katman kararı, SPRINT-A §3):
/// kriter/seçenek id'leri burada üretilir, kaynak her zaman `user`dır
/// (aiSuggested A2'ye ayrıldı; metrikler karışmaz). Tek upsert — ek
/// Firestore yazımı yok, şema değişmez.
class CreateDecision {
  const CreateDecision(this._repository, this._idGenerator);

  final DecisionRepository _repository;
  final IdGenerator _idGenerator;

  Future<Result<Decision>> call({
    required String ownerUid,
    required String title,
    String? templateId,
    List<({String name, int weight})> initialCriteria = const [],
    List<String> initialOptions = const [],
  }) async {
    final titleFailure = DecisionValidator.title(title);
    if (titleFailure != null) return Err(titleFailure);

    final now = DateTime.now();
    final decision = Decision(
      id: _idGenerator(),
      ownerUid: ownerUid,
      title: title.trim(),
      templateId: templateId,
      criteria: [
        for (final c in initialCriteria)
          Criterion(id: _idGenerator(), name: c.name, weight: c.weight),
      ],
      options: [
        for (final optionTitle in initialOptions)
          Option(id: _idGenerator(), title: optionTitle),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await _repository.upsert(decision);
    return Ok(decision);
  }
}
