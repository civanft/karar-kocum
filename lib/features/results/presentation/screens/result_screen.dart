import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../../../decision/presentation/providers/decision_editor.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../../scoring/domain/entities/scoring_types.dart';

/// Sonuç ekranı v1 — yerel ağırlıklı skor (US-C2).
/// Sprint 3'te eklenecekler: AI yorumu, riskler, what-if slider'ları, paylaşım.
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisionAsync = ref.watch(decisionEditorProvider(decisionId));

    return decisionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Yüklenemedi: $e')),
      ),
      data: (decision) {
        if (!decision.isScoreMatrixComplete) {
          // Derin bağlantıyla eksik karara gelinirse güvenli düşüş.
          return Scaffold(
            appBar: AppBar(title: const Text('Sonuç')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Sonuç için önce tüm puanlamayı tamamla.'),
                    const SizedBox(height: AppTokens.s4),
                    FilledButton(
                      onPressed: () => context.go('/decision/$decisionId/edit'),
                      child: const Text('Puanlamaya Dön'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final result = ref.read(computeResultProvider)(decision);
        final byId = {for (final o in decision.options) o.id: o};
        final winner = byId[result.recommendedOptionId]!;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(title: const Text('Sonuç')),
          body: ListView(
            padding: const EdgeInsets.all(AppTokens.s4),
            children: [
              // Önerilen seçenek kartı
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.s4),
                  child: Column(
                    children: [
                      Text(
                        'Önerilen seçenek',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s1),
                      Text(
                        winner.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s2),
                      _ConfidenceChip(result.confidence),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s4),
              Text('Sıralama', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppTokens.s2),
              for (final (rank, score) in result.ranking.indexed)
                _ScoreBar(
                  rank: rank + 1,
                  title: byId[score.optionId]?.title ?? '—',
                  score: score.score,
                  isWinner: score.optionId == result.recommendedOptionId,
                ),
              const SizedBox(height: AppTokens.s6),
              // Sprint 3 önizlemesi — pasif AI kartı
              const Card(
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('AI Analizi'),
                  subtitle: Text(
                    'Tarafsız değerlendirme, riskler ve gözden kaçanlar — yakında.',
                  ),
                  enabled: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip(this.confidence);
  final Confidence confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      Confidence.high => ('Yüksek güven', Colors.green),
      Confidence.medium => ('Orta güven', Colors.orange),
      Confidence.low => ('Düşük güven — fark çok az', Colors.red),
    };
    return Chip(
      avatar: Icon(Icons.verified_outlined, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.rank,
    required this.title,
    required this.score,
    required this.isWinner,
  });

  final int rank;
  final String title;
  final double score;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$rank.', style: theme.textTheme.labelLarge),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                score.toStringAsFixed(0),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s1),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 8,
              color: isWinner
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondaryContainer,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
