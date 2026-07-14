import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/entities/decision_template.dart';
import '../providers/template_providers.dart';
import '../widgets/template_card.dart';
import '../widgets/template_preview_sheet.dart';

/// Tüm şablonlar galerisi (/templates) — kategori başlıklı liste.
class TemplateGalleryScreen extends ConsumerWidget {
  const TemplateGalleryScreen({super.key});

  static const _categoryLabels = {
    TemplateCategory.shopping: 'Satın alma',
    TemplateCategory.career: 'Kariyer',
    TemplateCategory.education: 'Eğitim',
    TemplateCategory.lifestyle: 'Yaşam',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templateCatalogProvider).all();
    final byCategory = <TemplateCategory, List<DecisionTemplate>>{};
    for (final template in templates) {
      byCategory.putIfAbsent(template.category, () => []).add(template);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Şablonlar')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: [
          for (final entry in byCategory.entries) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppTokens.s2,
                bottom: AppTokens.s2,
              ),
              child: Text(
                _categoryLabels[entry.key] ?? entry.key.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final template in entry.value)
              TemplateCard(
                template: template,
                onTap: () => showTemplatePreviewSheet(context, template),
              ),
          ],
        ],
      ),
    );
  }
}
