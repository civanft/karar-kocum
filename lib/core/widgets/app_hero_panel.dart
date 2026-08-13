import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/tokens.dart';

/// Sıcak, premium karşılama/koç paneli (Sprint C-5).
///
/// Home karşılamasında ve koç (check-in) çağrısında kullanılır. Yumuşak
/// indigo yüzey + çok hafif dikey gradient; renkler temadan (light/dark).
class AppHeroPanel extends StatelessWidget {
  const AppHeroPanel({
    super.key,
    required this.title,
    this.eyebrow,
    this.supportText,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  /// Üst küçük etiket (ör. "Koçundan"). Boşsa gösterilmez.
  final String? eyebrow;
  final String title;
  final String? supportText;
  final IconData? icon;

  /// Aksiyon butonu — etiket + geri çağrı birlikte verilmeli.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Uygulama temayı hep sağlar; tema kurulmamış bağlamlarda moda uygun
    // güvenli varsayılan (crash yerine).
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final onHero = scheme.onSurface;

    return Container(
      width: double.infinity,
      // ~%12 daha kompakt: dikey padding s6→s5, iç boşluklar da azaltıldı.
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s6,
        vertical: AppTokens.s5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: semantic.heroBorder),
        // Çok hafif dikey gradient — yalnız hero'da, tokenlaştırılmış.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            semantic.heroSurface,
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.06),
              semantic.heroSurface,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s2),
                    ],
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: onHero,
                      ),
                    ),
                  ],
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: AppTokens.s3),
                Container(
                  padding: const EdgeInsets.all(AppTokens.s3),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
              ],
            ],
          ),
          if (supportText != null) ...[
            const SizedBox(height: AppTokens.s2),
            Text(
              supportText!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppTokens.s3),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
