import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_hero_panel.dart';
import '../../../../core/widgets/app_section_header.dart';
import '../../../journey/presentation/providers/journey_providers.dart';
import '../../../templates/presentation/providers/template_providers.dart';
import '../../../templates/presentation/widgets/template_card.dart';
import '../../../templates/presentation/widgets/template_preview_sheet.dart';
import '../../domain/entities/decision.dart';
import '../providers/decision_providers.dart';
import '../widgets/decision_card.dart';

/// Home — "Sıcak Premium Koç" başlangıç ekranı (Sprint C-5).
/// Marka + karşılama/koç hero'su + kararlar + şablonlar. Tüm davranışlar
/// (due policy, navigation, empty template akışı) korunur; yalnız görsel katman.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisions = ref.watch(decisionListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/decision/new'),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Karar'),
      ),
      body: SafeArea(
        child: decisions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s6),
              child: Text('Bir şeyler ters gitti: $e'),
            ),
          ),
          data: (list) =>
              list.isEmpty ? const _EmptyHome() : _PopulatedHome(list),
        ),
      ),
    );
  }
}

/// Üstte kalıcı marka satırı — sahte avatar/profil YOK.
/// Sağ uçta Ayarlar girişi: Home'un boş ve dolu hâllerinin ORTAK parçası
/// olduğu için ikon her iki durumda da tek tanımdan gelir (PR-R1).
class _BrandLine extends StatelessWidget {
  const _BrandLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.psychology_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: AppTokens.s2),
        Expanded(
          child: Text(
            'Karar Koçum',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        IconButton(
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Ayarlar',
        ),
      ],
    );
  }
}

class _PopulatedHome extends ConsumerWidget {
  const _PopulatedHome(this.decisions);
  final List<Decision> decisions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(journeyClockProvider)();
    final due =
        ref.watch(checkInDuePolicyProvider).dueDecisions(decisions, now);

    // Due varsa TEK hero koç eylemini taşır; yoksa karşılamayı. İki dev
    // panel üst üste gelmez.
    final Widget hero;
    if (due.isNotEmpty) {
      final top = due.first;
      final elapsed = now.difference(top.decidedAt!).inDays;
      final days = elapsed < 7 ? 7 : elapsed; // en az 7, negatif olmaz
      final extra =
          due.length > 1 ? ' · ${due.length} kararın kontrol bekliyor' : '';
      hero = AppHeroPanel(
        eyebrow: 'Koçundan',
        title: 'Bir kararını kontrol edelim',
        supportText: '"${top.title}" kararının üzerinden $days gün geçti. '
            'Nasıl gidiyor?$extra',
        icon: Icons.favorite_outline,
        actionLabel: 'Kontrol et',
        onAction: () => context.push('/decision/${top.id}/check-in'),
      );
    } else {
      hero = const AppHeroPanel(
        title: 'Bugün neyi netleştirelim?',
        supportText: 'Seçeneklerini sadeleştir, önemli olanı gör ve '
            'içini rahatlatan adımı seç.',
        icon: Icons.explore_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s4,
        AppTokens.s4,
        96, // FAB içeriği kapatmasın
      ),
      children: [
        const _BrandLine(),
        const SizedBox(height: AppTokens.s4),
        hero,
        const SizedBox(height: AppTokens.s6),
        AppSectionHeader(title: 'Kararların', count: decisions.length),
        for (var i = 0; i < decisions.length; i++) ...[
          DecisionCard(
            decision: decisions[i],
            onTap: () => context.push('/decision/${decisions[i].id}/edit'),
          ),
          if (i < decisions.length - 1) const SizedBox(height: AppTokens.s3),
        ],
      ],
    );
  }
}

/// Boş durum — sıcak yüzeylerle üstten başlar; şablon davranışı korunur.
class _EmptyHome extends ConsumerWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templateCatalogProvider).all().take(4).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s4,
        AppTokens.s4,
        96,
      ),
      children: [
        const _BrandLine(),
        const SizedBox(height: AppTokens.s4),
        const AppHeroPanel(
          title: 'İlk kararını birlikte netleştirelim',
          supportText: 'Bir şablonla başla — kriterler hazır, '
              'sen sadece puanla.',
          icon: Icons.explore_outlined,
        ),
        const SizedBox(height: AppTokens.s6),
        const AppSectionHeader(title: 'İlham veren şablonlar'),
        for (final template in templates) ...[
          TemplateCard(
            template: template,
            onTap: () => showTemplatePreviewSheet(context, template),
          ),
          const SizedBox(height: AppTokens.s3),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push('/templates'),
            child: const Text('Tüm şablonlar'),
          ),
        ),
      ],
    );
  }
}
