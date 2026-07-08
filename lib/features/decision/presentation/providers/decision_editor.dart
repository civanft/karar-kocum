import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/decision.dart';
import '../../domain/validators/decision_validator.dart';
import 'decision_providers.dart';

/// Taslak düzenleme durum makinesi — TEKNIK-MIMARI.md §6.1
/// Her mutasyon: state güncelle → repository'ye kaydet.
/// (Firestore'a geçişte 800 ms debounce eklenecek; in-memory'de gereksiz.)
class DecisionEditor extends AutoDisposeFamilyAsyncNotifier<Decision, String> {
  @override
  Future<Decision> build(String arg) async {
    final repo = ref.watch(decisionRepositoryProvider);

    // Audit K-2: tek seferlik okuma yerine canlı akış — harici yazımlar
    // (ikinci cihaz, Sprint 3'te aiAnalysis yazan Functions) editöre yansır.
    // Bayat emisyon koruması: mevcut durumdan ESKİ updatedAt taşıyan
    // emisyonlar yok sayılır (yerel iyimser güncellemeyi ezmesin).
    final sub = repo.watchById(arg).listen((incoming) {
      if (incoming == null) return; // silinme: navigasyon üst katmanın işi
      final current = state.valueOrNull;
      if (current == null || !incoming.updatedAt.isBefore(current.updatedAt)) {
        state = AsyncData(incoming);
      }
    });
    ref.onDispose(sub.cancel);

    final initial = await repo.getById(arg);
    if (initial == null) {
      throw StateError('Karar bulunamadı: $arg');
    }
    // Akış build tamamlanmadan daha yeni bir durum getirdiyse onu koru.
    final streamed = state.valueOrNull;
    if (streamed != null && streamed.updatedAt.isAfter(initial.updatedAt)) {
      return streamed;
    }
    return initial;
  }

  Future<void> _mutate(Decision Function(Decision) transform) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = transform(current).copyWith(updatedAt: DateTime.now());
    state = AsyncData(updated);
    await ref.read(decisionRepositoryProvider).upsert(updated);
  }

  // ---- Seçenekler (US-A3) ----

  Future<ValidationFailure?> addOption(String title) async {
    final failure = DecisionValidator.optionTitle(title);
    if (failure != null) return failure;
    final current = state.valueOrNull;
    if (current == null || !DecisionValidator.canAddOption(current)) {
      return const ValidationFailure(
        field: 'options',
        message: 'En fazla 10 seçenek eklenebilir.',
      );
    }
    final id = ref.read(idGeneratorProvider)();
    await _mutate(
      (d) => d.copyWith(
        options: [...d.options, Option(id: id, title: title.trim())],
      ),
    );
    return null;
  }

  Future<void> removeOption(String optionId) => _mutate(
        (d) => d.copyWith(
          options: d.options.where((o) => o.id != optionId).toList(),
          scores: Map.of(d.scores)..remove(optionId),
        ),
      );

  Future<void> updateOptionDescription(String optionId, String? description) =>
      _mutate(
        (d) => d.copyWith(
          options: [
            for (final o in d.options)
              o.id == optionId
                  ? o.copyWith(description: description?.trim())
                  : o,
          ],
        ),
      );

  // ---- Artı / Eksi (US-B1) ----

  Future<ValidationFailure?> addProCon(
    String optionId,
    String text, {
    required bool isPro,
  }) async {
    final failure = DecisionValidator.prosConsItem(text);
    if (failure != null) return failure;
    await _mutate(
      (d) => d.copyWith(
        options: [
          for (final o in d.options)
            o.id == optionId
                ? (isPro
                    ? o.copyWith(pros: [...o.pros, text.trim()])
                    : o.copyWith(cons: [...o.cons, text.trim()]))
                : o,
        ],
      ),
    );
    return null;
  }

  Future<void> removeProCon(
    String optionId,
    int index, {
    required bool isPro,
  }) =>
      _mutate(
        (d) => d.copyWith(
          options: [
            for (final o in d.options)
              o.id == optionId
                  ? (isPro
                      ? o.copyWith(
                          pros: [...o.pros]..removeAt(index),
                        )
                      : o.copyWith(cons: [...o.cons]..removeAt(index)))
                  : o,
          ],
        ),
      );

  // ---- Kriterler (US-B2) ----

  Future<ValidationFailure?> addCriterion(String name, int weight) async {
    if (name.trim().isEmpty) {
      return const ValidationFailure(
        field: 'criterionName',
        message: 'Kriter adı boş olamaz.',
      );
    }
    final failure = DecisionValidator.criterionWeight(weight);
    if (failure != null) return failure;
    final id = ref.read(idGeneratorProvider)();
    await _mutate(
      (d) => d.copyWith(
        criteria: [
          ...d.criteria,
          Criterion(id: id, name: name.trim(), weight: weight),
        ],
      ),
    );
    return null;
  }

  Future<void> setCriterionWeight(String criterionId, int weight) async {
    if (DecisionValidator.criterionWeight(weight) != null) return;
    await _mutate(
      (d) => d.copyWith(
        criteria: [
          for (final c in d.criteria)
            c.id == criterionId ? c.copyWith(weight: weight) : c,
        ],
      ),
    );
  }

  Future<void> removeCriterion(String criterionId) => _mutate(
        (d) => d.copyWith(
          criteria: d.criteria.where((c) => c.id != criterionId).toList(),
          scores: {
            for (final e in d.scores.entries)
              e.key: Map.of(e.value)..remove(criterionId),
          },
        ),
      );

  // ---- Puan matrisi (US-B4) ----

  Future<void> setScore(String optionId, String criterionId, int value) async {
    if (DecisionValidator.cellScore(value) != null) return;
    await _mutate((d) {
      final scores = {
        for (final e in d.scores.entries) e.key: Map.of(e.value),
      };
      (scores[optionId] ??= {})[criterionId] = CellScore(value: value);
      return d.copyWith(scores: scores);
    });
  }

  // ---- Diğer ----

  Future<void> setTitle(String title) async {
    if (DecisionValidator.title(title) != null) return;
    await _mutate((d) => d.copyWith(title: title.trim()));
  }

  Future<void> toggleFavorite() =>
      _mutate((d) => d.copyWith(isFavorite: !d.isFavorite));
}

final decisionEditorProvider = AsyncNotifierProvider.autoDispose
    .family<DecisionEditor, Decision, String>(DecisionEditor.new);

/// Sonuç ekranına geçiş kapısı: boş liste = hazır.
final resultReadinessProvider =
    Provider.autoDispose.family<List<ValidationFailure>, String>((ref, id) {
  final decision = ref.watch(decisionEditorProvider(id)).valueOrNull;
  if (decision == null) return const [];
  return DecisionValidator.readyForResult(decision);
});
