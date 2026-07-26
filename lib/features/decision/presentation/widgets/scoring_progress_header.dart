import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../providers/scoring_progress.dart';

/// Puanlama ilerleme başlığı (PR-A3, SPRINT-A §2.3) — listenin DIŞINDA
/// (sticky): scroll'da hedef hep görünür (Zeigarnik). Yalnız sayı
/// değişince rebuild olur (scoringProgressProvider select'li).
class ScoringProgressHeader extends ConsumerWidget {
  const ScoringProgressHeader({super.key, required this.decisionId});

  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scoringProgressProvider(decisionId));
    if (progress.total == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final complete = progress.filled == progress.total;
    final percent = (100 * progress.filled / progress.total).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s4,
        AppTokens.s4,
        AppTokens.s2,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Row(
          key: ValueKey(complete),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🎉 emoji yerine sakin, sıcak semantik başarı ikonu.
            Icon(
              complete
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 20,
              color: complete ? semantic.success : theme.colorScheme.outline,
            ),
            const SizedBox(width: AppTokens.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    complete
                        ? 'Puanlama tamam '
                            '${progress.filled}/${progress.total}'
                        : 'Puanlama: ${progress.filled}/${progress.total} '
                            'tamamlandı (%$percent)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: complete
                          ? semantic.success
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s2),
                  LinearProgressIndicator(
                    value: progress.filled / progress.total,
                    color: complete ? semantic.success : null,
                    borderRadius: BorderRadius.circular(AppTokens.s1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
