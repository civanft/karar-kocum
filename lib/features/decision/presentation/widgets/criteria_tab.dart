import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_empty_hint.dart';
import '../../domain/entities/decision.dart';
import '../providers/decision_editor.dart';
import 'criterion_suggestion_strip.dart';

class CriteriaTab extends ConsumerWidget {
  const CriteriaTab({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(decisionEditorProvider(decisionId)).value;
    if (decision == null) return const SizedBox.shrink();

    // Boş durum: sıcak rehber + öneri şeridi (kendini gizler) + tek CTA.
    if (decision.criteria.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: [
          const _CriteriaGuide(),
          const SizedBox(height: AppTokens.s4),
          CriterionSuggestionStrip(decisionId: decisionId),
          AppEmptyHint(
            icon: Icons.balance_outlined,
            title: 'İlk kriterini ekle',
            message: 'Her kriterin etkisini 1–10 arasında ayarlayabilirsin.',
            actionLabel: 'Kriter ekle',
            onAction: () => _showAddCriterionDialog(context, ref),
          ),
          const SizedBox(height: 96),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppTokens.s4),
      children: [
        const _CriteriaGuide(),
        const SizedBox(height: AppTokens.s4),
        CriterionSuggestionStrip(decisionId: decisionId),
        for (final criterion in decision.criteria)
          _CriterionCard(decisionId: decisionId, criterion: criterion),
        const SizedBox(height: AppTokens.s2),
        OutlinedButton.icon(
          onPressed: () => _showAddCriterionDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Kriter ekle'),
        ),
        const SizedBox(height: 96),
      ],
    );
  }

  Future<void> _showAddCriterionDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    var weight = 5;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Yeni Kriter'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(hintText: 'Örn. Fiyat, Kamera…'),
              ),
              const SizedBox(height: AppTokens.s4),
              Row(
                children: [
                  const Text('Önem:'),
                  Expanded(
                    child: Slider(
                      value: weight.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$weight',
                      onChanged: (v) => setState(() => weight = v.round()),
                    ),
                  ),
                  Text('$weight'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || controller.text.trim().isEmpty) return;
    final failure = await ref
        .read(decisionEditorProvider(decisionId).notifier)
        .addCriterion(controller.text, weight);
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.userMessage)));
    }
  }
}

/// Kompakt sekme rehberi — Seçenekler sekmesiyle hizalı dil.
class _CriteriaGuide extends StatelessWidget {
  const _CriteriaGuide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kriterlerin', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppTokens.s1),
        Text(
          'Kararında senin için önemli olanları belirle ve ağırlıklandır.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Sıcak kriter kartı: leading rozet + ad + "N/10" ağırlık rozeti +
/// nötr silme + tam genişlik ağırlık slider'ı.
class _CriterionCard extends ConsumerWidget {
  const _CriterionCard({required this.decisionId, required this.criterion});
  final String decisionId;
  final Criterion criterion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(decisionEditorProvider(decisionId).notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Yumuşak leading rozet — Home/Seçenekler kart diliyle hizalı.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  child: Icon(
                    Icons.balance_outlined,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Text(
                    criterion.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
                _WeightBadge(weight: criterion.weight),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Kriteri sil',
                  visualDensity: VisualDensity.compact,
                  color: scheme.onSurfaceVariant,
                  onPressed: () => notifier.removeCriterion(criterion.id),
                ),
              ],
            ),
            Slider(
              value: criterion.weight.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${criterion.weight}',
              onChanged: (v) => notifier.setCriterionWeight(
                criterion.id,
                v.round(),
              ),
              // Y-2: bırakınca tek yazım.
              onChangeEnd: (_) => notifier.flushPendingWrites(),
            ),
          ],
        ),
      ),
    );
  }
}

/// "N/10" ağırlık rozeti — sakin nötr yüzey.
class _WeightBadge extends StatelessWidget {
  const _WeightBadge({required this.weight});
  final int weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.s2),
      ),
      child: Text(
        '$weight/10',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
