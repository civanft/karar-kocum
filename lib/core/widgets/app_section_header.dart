import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Bölüm başlığı (Sprint C-5) — büyük boşluk oluşturmadan net ayrım.
/// Başlık + opsiyonel sayaç/yardımcı metin + opsiyonel trailing aksiyon.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
  });

  final String title;

  /// Başlığın yanında sakin bir sayaç (ör. karar sayısı). null = gizle.
  final int? count;

  /// Sağ tarafta opsiyonel aksiyon (ör. TextButton). null = gizle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Row(
        children: [
          // Uzun başlık + pil + textScale'de taşmayı önle.
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: AppTokens.s2),
            _CountPill(count: count!),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Küçük, sakin sayı rozeti — "N karar". Çıplak sayı yerine.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        '$count karar',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
