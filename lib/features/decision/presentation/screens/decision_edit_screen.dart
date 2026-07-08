import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../providers/decision_editor.dart';
import '../widgets/criteria_tab.dart';
import '../widgets/options_tab.dart';
import '../widgets/scores_tab.dart';

/// Sekmeli düzenleme ekranı: Seçenekler / Kriterler / Puanlar.
/// "Sonucu Gör" yalnız matris tamamlanınca aktifleşir (US-C2 kapısı).
class DecisionEditScreen extends ConsumerWidget {
  const DecisionEditScreen({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decisionAsync = ref.watch(decisionEditorProvider(decisionId));
    final blockers = ref.watch(resultReadinessProvider(decisionId));

    return decisionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Karar yüklenemedi: $e')),
      ),
      data: (decision) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              decision.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: Icon(
                  decision.isFavorite ? Icons.star : Icons.star_border,
                  color: decision.isFavorite ? Colors.amber : null,
                ),
                tooltip: 'Favori',
                onPressed: () => ref
                    .read(decisionEditorProvider(decisionId).notifier)
                    .toggleFavorite(),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Seçenekler'),
                Tab(text: 'Kriterler'),
                Tab(text: 'Puanlar'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              OptionsTab(decisionId: decisionId),
              CriteriaTab(decisionId: decisionId),
              ScoresTab(decisionId: decisionId),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (blockers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.s2),
                      child: Text(
                        blockers.first.message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: blockers.isEmpty
                        ? () => context.push('/decision/$decisionId/result')
                        : null,
                    icon: const Icon(Icons.insights),
                    label: const Text('Sonucu Gör'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
