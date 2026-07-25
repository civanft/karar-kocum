import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../../../journey/presentation/providers/journey_providers.dart';
import '../../../templates/presentation/providers/template_providers.dart';
import '../../../templates/presentation/widgets/template_card.dart';
import '../../../templates/presentation/widgets/template_preview_sheet.dart';
import '../../domain/entities/decision.dart';
import '../providers/decision_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisions = ref.watch(decisionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kararlarım')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/decision/new'),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Karar'),
      ),
      body: decisions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Bir şeyler ters gitti: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyState();
          // Sprint C-4: kontrol zamanı gelmiş kararlar için koç kartı.
          // Bildirim tercihinden BAĞIMSIZ; en eski due karar üstte gösterilir.
          final now = ref.watch(journeyClockProvider)();
          final due =
              ref.watch(checkInDuePolicyProvider).dueDecisions(list, now);
          Widget? coachCard;
          if (due.isNotEmpty) {
            final top = due.first;
            final elapsed = now.difference(top.decidedAt!).inDays;
            coachCard = _CoachCard(
              decision: top,
              days: elapsed < 7 ? 7 : elapsed, // en az 7, negatif olmaz
              dueCount: due.length,
            );
          }
          return _DecisionList(list, header: coachCard);
        },
      ),
    );
  }
}

class _DecisionList extends StatelessWidget {
  const _DecisionList(this.decisions, {this.header});
  final List<Decision> decisions;

  /// Üstte gösterilecek koç kartı (varsa). Tek ListView içinde header olarak
  /// render edilir — ayrı/iç içe kaydırma alanı YARATILMAZ.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.s4),
      children: [
        if (header != null) ...[header!, const SizedBox(height: AppTokens.s4)],
        for (var i = 0; i < decisions.length; i++) ...[
          _DecisionTile(decisions[i]),
          if (i < decisions.length - 1) const SizedBox(height: AppTokens.s2),
        ],
      ],
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile(this.decision);
  final Decision decision;

  @override
  Widget build(BuildContext context) {
    final d = decision;
    return Card(
      child: ListTile(
        title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${d.options.length} seçenek · ${d.criteria.length} kriter',
        ),
        leading: Icon(
          d.status == DecisionStatus.analyzed
              ? Icons.check_circle_outline
              : Icons.edit_note,
          color: Theme.of(context).colorScheme.primary,
        ),
        trailing:
            d.isFavorite ? const Icon(Icons.star, color: Colors.amber) : null,
        onTap: () => context.push('/decision/${d.id}/edit'),
      ),
    );
  }
}

/// Sprint C-4 — Home koç kartı. Bildirime alternatif uygulama-içi giriş
/// noktası: bildirim reddedilmiş/kaçırılmış olsa da kullanıcı buradan
/// check-in'e ulaşır. Check-in yazılınca decision stream güncellenir ve
/// kart (kalıcı state olmadan) otomatik kaybolur / sıradaki due'ya geçer.
class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.decision,
    required this.days,
    required this.dueCount,
  });

  final Decision decision;
  final int days;
  final int dueCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Koçundan',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: AppTokens.s1),
                      Text(
                        'Bir kararını kontrol edelim',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s2),
                      Text(
                        '"${decision.title}" kararının üzerinden $days gün '
                        'geçti. Nasıl gidiyor?',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onPrimaryContainer),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (dueCount > 1) ...[
              const SizedBox(height: AppTokens.s2),
              Text(
                '$dueCount kararın kontrol bekliyor',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
            const SizedBox(height: AppTokens.s3),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () =>
                    context.push('/decision/${decision.id}/check-in'),
                child: const Text('Kontrol et'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boş durum — PRD §6.1: "İlk kararını oluştur" + örnek kartları.
/// Boş durum: 4 şablon kartı + "Tüm şablonlar" (PR-A1).
/// Kart, önizleme sheet'i açar — karar taahhütten önce YARATILMAZ.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templates = ref.watch(templateCatalogProvider).all().take(4);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'İlk kararını oluştur',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              'Bir şablonla başla — kriterler hazır,\nsen sadece puanla.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.s6),
            for (final template in templates)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.s2),
                child: TemplateCard(
                  template: template,
                  onTap: () => showTemplatePreviewSheet(context, template),
                ),
              ),
            TextButton(
              onPressed: () => context.push('/templates'),
              child: const Text('Tüm şablonlar'),
            ),
          ],
        ),
      ),
    );
  }
}
