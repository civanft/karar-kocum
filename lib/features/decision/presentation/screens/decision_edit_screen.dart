import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/tokens.dart';
import '../providers/decision_editor.dart';
import '../providers/scoring_progress.dart';
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
            bottom: TabBar(
              tabs: [
                const Tab(text: 'Seçenekler'),
                const Tab(text: 'Kriterler'),
                Tab(child: _ScoresTabLabel(decisionId: decisionId)),
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
                        _blockerMessage(ref, decisionId, blockers.first),
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

/// PR-A3: puanlama engeli NİCELİKSEL mesaja zenginleşir; validator
/// sözleşmesi DEĞİŞMEDİ — yalnız sunum katmanı mesajı türetiyor.
String _blockerMessage(
  WidgetRef ref,
  String decisionId,
  ValidationFailure blocker,
) {
  if (blocker.field != 'scores') return blocker.message;
  final progress = ref.watch(scoringProgressProvider(decisionId));
  if (progress.total == 0) return blocker.message;
  final remaining = progress.total - progress.filled;
  return 'Puanlama: ${progress.filled}/${progress.total} — '
      '$remaining hücre kaldı';
}

/// "Puanlar" sekme etiketi + kalan-sayısı rozeti. Kendi Consumer'ında —
/// TabBar'ın tamamı değil yalnız rozet rebuild olur.
class _ScoresTabLabel extends ConsumerWidget {
  const _ScoresTabLabel({required this.decisionId});

  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scoringProgressProvider(decisionId));
    final remaining = progress.total - progress.filled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Puanlar'),
        if (progress.total > 0 && remaining > 0) ...[
          const SizedBox(width: AppTokens.s1),
          CircleAvatar(
            radius: 9,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              '$remaining',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
