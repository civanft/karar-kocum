import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../templates/presentation/providers/template_providers.dart';
import '../../domain/usecases/suggest_criteria.dart';
import 'decision_editor.dart';

/// Kriter önerileri (PR-A2) — SPRINT-A §1.2.
///
/// Editör durumuna reaktif: kriter eklenince/silinince otomatik yeniden
/// hesaplanır. 6+ kriterde boş döner (öneri değeri düşer, gürültü olur).
/// templateId doluysa o şablonun eklenmemiş kriterleri önce gelir.
final criterionSuggesterProvider =
    Provider<CriterionSuggester>((_) => const CriterionSuggester());

final criterionSuggestionsProvider = Provider.autoDispose
    .family<List<CriterionSuggestion>, String>((ref, decisionId) {
  final decision = ref.watch(decisionEditorProvider(decisionId)).valueOrNull;
  if (decision == null) return const [];
  if (decision.criteria.length >= 6) return const [];

  final template = decision.templateId == null
      ? null
      : ref.watch(templateByIdProvider(decision.templateId!));

  return ref.watch(criterionSuggesterProvider).suggest(
    decision: decision,
    templateCriteria: [
      if (template != null)
        for (final c in template.criteria) (name: c.name, weight: c.weight),
    ],
  );
});

/// ✕ davranışı: şerit bu EKRAN ÖMRÜ boyunca gizlenir (autoDispose
/// bilinçli — kalıcılaştırılmaz, ucuz geri dönüş).
final suggestionsDismissedProvider =
    StateProvider.autoDispose.family<bool, String>((_, __) => false);
