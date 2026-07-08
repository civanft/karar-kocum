import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../providers/decision_editor.dart';

/// Seçenek × kriter puan matrisi.
/// "AI puanlasın" düğmesi Sprint 3'te (premium) eklenecek.
class ScoresTab extends ConsumerWidget {
  const ScoresTab({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(decisionEditorProvider(decisionId)).value;
    if (decision == null) return const SizedBox.shrink();

    if (decision.options.length < 2 || decision.criteria.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s6),
          child: Text(
            'Puanlamaya başlamak için önce en az 2 seçenek ve 1 kriter ekle.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final notifier = ref.read(decisionEditorProvider(decisionId).notifier);

    return ListView(
      padding: const EdgeInsets.all(AppTokens.s4),
      children: [
        for (final option in decision.options)
          Card(
            margin: const EdgeInsets.only(bottom: AppTokens.s3),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppTokens.s2),
                  for (final criterion in decision.criteria)
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            criterion.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: (decision.scores[option.id]?[criterion.id]
                                        ?.value ??
                                    5)
                                .toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label:
                                '${decision.scores[option.id]?[criterion.id]?.value ?? "—"}',
                            // İlk dokunuşta 5 varsayılanından başlar; hücre
                            // ancak kullanıcı dokununca "dolu" sayılır.
                            onChanged: (v) => notifier.setScore(
                              option.id,
                              criterion.id,
                              v.round(),
                            ),
                            // Y-2: sürükleme boyunca yazım birikir,
                            // bırakınca tek yazım gider.
                            onChangeEnd: (_) => notifier.flushPendingWrites(),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${decision.scores[option.id]?[criterion.id]?.value ?? "—"}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: decision.scores[option.id]
                                              ?[criterion.id] ==
                                          null
                                      ? Theme.of(context).colorScheme.outline
                                      : null,
                                ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 96),
      ],
    );
  }
}
