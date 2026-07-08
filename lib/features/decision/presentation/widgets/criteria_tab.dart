import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/tokens.dart';
import '../providers/decision_editor.dart';

class CriteriaTab extends ConsumerWidget {
  const CriteriaTab({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(decisionEditorProvider(decisionId)).value;
    if (decision == null) return const SizedBox.shrink();
    final notifier = ref.read(decisionEditorProvider(decisionId).notifier);

    return ListView(
      padding: const EdgeInsets.all(AppTokens.s4),
      children: [
        Text(
          'Senin için neyin ne kadar önemli olduğunu belirle. '
          'Skorlar bu ağırlıklara göre hesaplanır.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppTokens.s4),
        for (final criterion in decision.criteria)
          Card(
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
                          criterion.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        'Önem: ${criterion.weight}/10',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Kriteri sil',
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
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _showAddCriterionDialog(context, ref),
          icon: const Icon(Icons.add),
          label: Text(
            decision.criteria.isEmpty ? 'İlk kriteri ekle' : 'Kriter ekle',
          ),
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
