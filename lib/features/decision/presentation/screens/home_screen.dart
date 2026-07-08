import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
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
        data: (list) =>
            list.isEmpty ? const _EmptyState() : _DecisionList(list),
      ),
    );
  }
}

class _DecisionList extends StatelessWidget {
  const _DecisionList(this.decisions);
  final List<Decision> decisions;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.s4),
      itemCount: decisions.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.s2),
      itemBuilder: (context, i) {
        final d = decisions[i];
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
            trailing: d.isFavorite
                ? const Icon(Icons.star, color: Colors.amber)
                : null,
            onTap: () => context.push('/decision/${d.id}/edit'),
          ),
        );
      },
    );
  }
}

/// Boş durum — PRD §6.1: "İlk kararını oluştur" + örnek kartları.
/// Şablon sistemi Sprint 2'de geliyor; kartlar şimdilik başlık önerisi taşır.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static const _suggestions = [
    ('📱', 'iPhone mu Samsung mu?'),
    ('💼', 'Hangi iş teklifini kabul etmeliyim?'),
    ('🎓', 'Hangi bölümü seçmeliyim?'),
    ('🏙️', 'Hangi şehirde yaşamalıyım?'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              'Seçeneklerini yaz, kriterlerini puanla,\nnet bir sonuç gör.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.s6),
            for (final (emoji, title) in _suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.s2),
                child: OutlinedButton(
                  onPressed: () => context.push(
                    Uri(
                      path: '/decision/new',
                      queryParameters: {
                        'title': title,
                      },
                    ).toString(),
                  ),
                  child: Row(
                    children: [
                      Text(emoji),
                      const SizedBox(width: AppTokens.s3),
                      Expanded(child: Text(title)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
