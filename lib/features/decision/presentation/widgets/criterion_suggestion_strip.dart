import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/services/analytics/analytics_service.dart';
import '../../../../core/theme/tokens.dart';
import '../../domain/entities/decision.dart';
import '../../domain/usecases/suggest_criteria.dart';
import '../providers/criterion_suggestions.dart';
import '../providers/decision_editor.dart';

/// Öneri chip şeridi (PR-A2, SPRINT-A §2.2): tek dokunuş kriteri
/// varsayılan ağırlıkla (5) ekler — "önce ekle, sonra ayarla" akışı.
/// Chip'le eklenen kriter aiSuggested etiketlenir (huni ölçümü).
class CriterionSuggestionStrip extends ConsumerWidget {
  const CriterionSuggestionStrip({super.key, required this.decisionId});

  final String decisionId;

  static const int defaultWeight = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(suggestionsDismissedProvider(decisionId));
    final suggestions = ref.watch(criterionSuggestionsProvider(decisionId));
    if (dismissed || suggestions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Önerilen kriterler',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Önerileri gizle',
                  onPressed: () => ref
                      .read(suggestionsDismissedProvider(decisionId).notifier)
                      .state = true,
                ),
              ],
            ),
            Wrap(
              spacing: AppTokens.s2,
              runSpacing: AppTokens.s2,
              children: [
                for (final suggestion in suggestions)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(suggestion.name),
                    onPressed: () => _accept(context, ref, suggestion),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    CriterionSuggestion suggestion,
  ) async {
    final failure = await ref
        .read(decisionEditorProvider(decisionId).notifier)
        .addCriterion(
          suggestion.name,
          defaultWeight,
          source: CriterionSource.aiSuggested,
        );
    if (failure != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.userMessage)));
      }
      return;
    }
    unawaited(
      ref.read(analyticsServiceProvider).logCriterionSuggestionAccepted(
            origin: suggestion.origin.name,
          ),
    );
  }
}
