import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_empty_hint.dart';
import '../../domain/entities/decision.dart';
import '../providers/decision_editor.dart';
import 'scoring_progress_header.dart';

/// Seçenek × kriter puan matrisi.
/// "AI puanlasın" düğmesi Sprint 3'te (premium) eklenecek.
class ScoresTab extends ConsumerWidget {
  const ScoresTab({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(decisionEditorProvider(decisionId)).value;
    if (decision == null) return const SizedBox.shrink();

    // Ön koşul eksik: eksik olana yönlendiren sıcak, dinamik boş durum.
    if (decision.options.length < 2 || decision.criteria.isEmpty) {
      final needsOptions = decision.options.length < 2;
      return ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: [
          AppEmptyHint(
            icon: Icons.tune_outlined,
            title: 'Puanlamaya hazırlan',
            message: needsOptions
                ? 'Puanlamak için en az 2 seçenek gerekli. '
                    'Önce Seçenekler sekmesinden ekle.'
                : 'Puanlamak için en az 1 kriter gerekli. '
                    'Önce Kriterler sekmesinden ekle.',
            // Buton dialog açmıyor; ilgili sekmeye yönlendiriyor.
            actionLabel: needsOptions ? 'Seçeneklere git' : 'Kriterlere git',
            actionIcon: Icons.arrow_forward_rounded,
            onAction: () => DefaultTabController.maybeOf(context)
                ?.animateTo(needsOptions ? 0 : 1),
          ),
          const SizedBox(height: 96),
        ],
      );
    }

    return Column(
      children: [
        ScoringProgressHeader(decisionId: decisionId),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s2,
              AppTokens.s4,
              AppTokens.s4,
            ),
            children: [
              for (final option in decision.options)
                _OptionScoreCard(
                  decisionId: decisionId,
                  option: option,
                  criteria: decision.criteria,
                  scores: decision.scores[option.id],
                  filled: decision.filledScoreCellsFor(option.id),
                ),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sıcak seçenek puan kartı: leading rozet + ad + ilerleme rozeti +
/// her kriter için tam genişlik dikey satır (dar ekran + büyük yazıya dayanır).
class _OptionScoreCard extends ConsumerWidget {
  const _OptionScoreCard({
    required this.decisionId,
    required this.option,
    required this.criteria,
    required this.scores,
    required this.filled,
  });

  final String decisionId;
  final Option option;
  final List<Criterion> criteria;
  final Map<String, CellScore>? scores;
  final int filled;

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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  child: Icon(
                    Icons.alt_route_outlined,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Text(
                    option.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
                _OptionScoreBadge(filled: filled, total: criteria.length),
              ],
            ),
            const SizedBox(height: AppTokens.s2),
            for (final criterion in criteria)
              _CriterionScoreRow(
                criterionName: criterion.name,
                value: scores?[criterion.id]?.value,
                // İlk dokunuşta 5 varsayılanından başlar; hücre ancak
                // kullanıcı dokununca "dolu" sayılır.
                onChanged: (v) =>
                    notifier.setScore(option.id, criterion.id, v.round()),
                // Y-2: sürükleme boyunca yazım birikir, bırakınca tek yazım.
                onChangeEnd: (_) => notifier.flushPendingWrites(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tek kriter puan satırı — ad üstte tam satır, slider altta tam genişlik.
/// Yatay sıkışıklığı önler: 320–360dp + textScale 1.3'te taşmaz.
class _CriterionScoreRow extends StatelessWidget {
  const _CriterionScoreRow({
    required this.criterionName,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String criterionName;
  final int? value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unfilled = value == null;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  criterionName,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Text(
                '${value ?? "—"}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: unfilled
                      ? theme.colorScheme.outline
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Slider(
            value: (value ?? 5).toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '${value ?? "—"}',
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

/// Seçenek kartı ilerleme rozeti: "3/5" — tamam olunca semantik başarı.
class _OptionScoreBadge extends StatelessWidget {
  const _OptionScoreBadge({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final complete = total > 0 && filled == total;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: complete
            ? semantic.success.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.s2),
      ),
      child: Text(
        '$filled/$total',
        style: theme.textTheme.labelSmall?.copyWith(
          color:
              complete ? semantic.success : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
