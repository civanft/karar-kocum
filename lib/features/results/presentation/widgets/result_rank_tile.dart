import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';

/// "Puan dağılımı" bölümündeki tek seçenek satırı (Görsel Dilim 3).
///
/// Rank rozeti + seçenek adı + `N/100` + ilerleme çubuğu. Önerilen/seçilen
/// durumu YALNIZ renkle değil; etiket + ikon ile de gösterilir ve tek bir
/// Semantics label'ında (rank, başlık, skor, durum) toplanır.
class ResultRankTile extends StatelessWidget {
  const ResultRankTile({
    super.key,
    required this.rank,
    required this.title,
    required this.score,
    required this.isWinner,
    this.isChosen = false,
  });

  final int rank;
  final String title;

  /// 0–100 ölçeğinde ağırlıklı skor (hesaplama değişmez).
  final double score;
  final bool isWinner;

  /// Kullanıcının "Kararımı Verdim" ile seçtiği seçenek.
  final bool isChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);

    final scoreText = score.toStringAsFixed(0);
    final statusParts = <String>[
      if (isWinner) 'önerilen',
      if (isChosen) 'seçildi',
    ];
    final semanticsLabel = 'Sıra $rank, $title, $scoreText bölü 100 puan'
        '${statusParts.isEmpty ? '' : ', ${statusParts.join(', ')}'}';

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RankBadge(rank: rank, highlight: isWinner),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: isWinner || isChosen
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s2),
                  Text('$scoreText/100', style: theme.textTheme.labelLarge),
                ],
              ),
              if (isWinner || isChosen) ...[
                const SizedBox(height: AppTokens.s1),
                Wrap(
                  spacing: AppTokens.s2,
                  runSpacing: AppTokens.s1,
                  children: [
                    if (isWinner)
                      _StatusTag(
                        label: 'Önerilen',
                        color: scheme.primary,
                        icon: Icons.star_outline_rounded,
                      ),
                    if (isChosen)
                      _StatusTag(
                        label: 'Seçildi',
                        color: semantic.success,
                        icon: Icons.check_circle_outline,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.s2),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 8,
                  color: isWinner ? scheme.primary : scheme.secondaryContainer,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sakin rank rozeti; önerilen satırda primary vurgu alır.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.highlight});
  final int rank;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        '$rank',
        style: theme.textTheme.labelLarge?.copyWith(
          color: highlight ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Önerilen/seçildi etiketi — renk + ikon + metin.
class _StatusTag extends StatelessWidget {
  const _StatusTag({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppTokens.s1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
