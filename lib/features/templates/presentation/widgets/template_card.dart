import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/entities/decision_template.dart';

/// Ortak şablon kartı — boş-durum listesi (dikey), galeri ve yeni-karar
/// şeridi (compact, yatay) aynı bileşeni kullanır (SPRINT-A §2.1).
class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.template,
    required this.onTap,
    this.compact = false,
  });

  final DecisionTemplate template;
  final VoidCallback onTap;

  /// true: yatay şeritteki dar kart (yeni-karar ekranı).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = Text(
      '${template.criteria.length} hazır kriter',
      style: theme.textTheme.labelSmall
          ?.copyWith(color: theme.colorScheme.primary),
    );

    if (compact) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 168,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(template.emoji, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppTokens.s2),
                  Text(
                    template.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppTokens.s2),
                  badge,
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Text(template.emoji, style: theme.textTheme.titleLarge),
        title: Text(template.title),
        subtitle: badge,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
