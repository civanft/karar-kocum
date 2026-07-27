import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../../../scoring/domain/entities/scoring_types.dart';

/// Sonuç ekranının kazanan paneli (Görsel Dilim 3) — kazananı "rapor kartı"
/// yerine sakin, güçlü bir koç sonucu olarak sunar. Home AppHeroPanel'in
/// sıcak yüzey dilini izler; renkler temadan (AppTokens + AppSemanticColors).
///
/// Destek mesajı ve güven rozeti YALNIZ mevcut [Confidence] alanından
/// türetilir — yeni kriter/katkı hesabı YOK, DecisionResult değişmez.
class ResultWinnerPanel extends StatelessWidget {
  const ResultWinnerPanel({
    super.key,
    required this.title,
    required this.confidence,
  });

  final String title;
  final Confidence confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Uygulama temayı hep sağlar; kurulmamış bağlamda moda uygun güvenli
    // varsayılan (crash yerine).
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);

    // low → info/nötr; ASLA error/kırmızı (kullanıcıya "algoritma güvenilmez"
    // hissi vermemek için). Her seviyede renk + ikon + açık metin birlikte.
    final (
      Color badgeColor,
      IconData badgeIcon,
      String badgeLabel,
      String support
    ) = switch (confidence) {
      Confidence.high => (
          semantic.success,
          Icons.verified_outlined,
          'Yüksek güven',
          'Puanlamana göre bu seçenek belirgin biçimde öne çıkıyor.',
        ),
      Confidence.medium => (
          semantic.warning,
          Icons.balance_outlined,
          'Orta güven',
          'Puanlamana göre bu seçenek öne çıkıyor.',
        ),
      Confidence.low => (
          semantic.info,
          Icons.compare_arrows_outlined,
          'Yakın sonuç',
          'Sonuçlar birbirine yakın; kendi önceliklerini de düşün.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s6,
        vertical: AppTokens.s5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        border: Border.all(color: semantic.heroBorder),
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
          Text(
            'Analizin hazır',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            'Öne çıkan seçenek',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          _ConfidenceBadge(
            color: badgeColor,
            icon: badgeIcon,
            label: badgeLabel,
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            support,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Güven rozeti — semantik renk + ikon + metin (yalnız renge dayanmaz).
class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: AppTokens.s1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppTokens.s2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
