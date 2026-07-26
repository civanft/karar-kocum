import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../../domain/entities/decision.dart';

/// Home karar listesi kartı (Sprint C-5).
///
/// Zenginleştirilmiş metadata + sakin durum etiketi + favori + ileri işareti.
/// Durum yalnız mevcut Decision alanlarından türetilir (yeni alan yok).
/// onTap davranışı çağıran tarafından korunur.
class DecisionCard extends StatelessWidget {
  const DecisionCard({super.key, required this.decision, required this.onTap});

  final Decision decision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Tema hep sağlanır; kurulmamış bağlamlarda moda uygun güvenli varsayılan.
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final status = _statusOf(decision, scheme, semantic);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s4),
          child: Row(
            children: [
              // Durum rengiyle hafif tonlanmış ikon rozeti.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(status.icon, color: status.color, size: 22),
              ),
              const SizedBox(width: AppTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      decision.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppTokens.s2),
                    Row(
                      children: [
                        _StatusChip(label: status.label, color: status.color),
                        const SizedBox(width: AppTokens.s2),
                        Flexible(
                          child: Text(
                            '${decision.options.length} seçenek · '
                            '${decision.criteria.length} kriter',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (decision.isFavorite) ...[
                const SizedBox(width: AppTokens.s2),
                Icon(Icons.star_rounded, color: semantic.warning, size: 20),
              ],
              const SizedBox(width: AppTokens.s1),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _CardStatus _statusOf(
    Decision d,
    ColorScheme scheme,
    AppSemanticColors semantic,
  ) {
    if (d.hasCheckedIn) {
      return _CardStatus(
        'Kontrol tamamlandı',
        semantic.success,
        Icons.task_alt,
      );
    }
    if (d.isDecided) {
      return _CardStatus('Karar verildi', scheme.primary, Icons.flag_outlined);
    }
    if (d.status == DecisionStatus.analyzed) {
      return _CardStatus(
        'Analiz hazır',
        scheme.tertiary,
        Icons.auto_awesome_outlined,
      );
    }
    return _CardStatus('Taslak', scheme.onSurfaceVariant, Icons.edit_note);
  }
}

class _CardStatus {
  const _CardStatus(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

/// Küçük, sakin durum etiketi — nötr yüzey, durum rengi yalnız metinde/noktada.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppTokens.s1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
