import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Sıcak, rehber eden boş durum bileşeni (Görsel Dilim 2A).
///
/// İkon + başlık + kısa destek metni + tek CTA. Sahipsiz beyaz boşluk
/// yerine yönlendiren bir yüzey. Renkler temadan; hard-code yok.
class AppEmptyHint extends StatelessWidget {
  const AppEmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.add,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  /// CTA ikonu — bağlama uygun (ekleme için add, yönlendirme için ok).
  /// Geriye uyumlu: verilmezse artı ikonu.
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTokens.s3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Icon(icon, color: scheme.primary, size: 28),
          ),
          const SizedBox(height: AppTokens.s4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          FilledButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
