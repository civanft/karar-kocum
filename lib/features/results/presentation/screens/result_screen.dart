import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/analytics/analytics_service.dart';
import '../../../../core/theme/tokens.dart';
import '../../../ai_analysis/presentation/widgets/analysis_card.dart';
import '../../../decision/domain/entities/decision.dart';
import '../../../decision/presentation/providers/decision_editor.dart';
import '../../../decision/presentation/providers/decision_providers.dart';
import '../../../scoring/domain/entities/scoring_types.dart';

/// Sonuç ekranı v1 — yerel ağırlıklı skor (US-C2).
/// Sprint 3'te eklenecekler: AI yorumu, riskler, what-if slider'ları, paylaşım.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.decisionId});
  final String decisionId;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  String get decisionId => widget.decisionId;

  @override
  void initState() {
    super.initState();
    // v1 aktivasyon olayı (PRD kuzey yıldızı hunisinin son adımı).
    unawaited(ref.read(analyticsServiceProvider).logResultViewed());
  }

  @override
  Widget build(BuildContext context) {
    final decisionAsync = ref.watch(decisionEditorProvider(decisionId));

    return decisionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Yüklenemedi: $e')),
      ),
      data: (decision) {
        if (!decision.isScoreMatrixComplete) {
          // Derin bağlantıyla eksik karara gelinirse güvenli düşüş.
          return Scaffold(
            appBar: AppBar(title: const Text('Sonuç')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Sonuç için önce tüm puanlamayı tamamla.'),
                    const SizedBox(height: AppTokens.s4),
                    FilledButton(
                      onPressed: () => context.go('/decision/$decisionId/edit'),
                      child: const Text('Puanlamaya Dön'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final result = ref.read(computeResultProvider)(decision);
        final byId = {for (final o in decision.options) o.id: o};
        final winner = byId[result.recommendedOptionId]!;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(title: const Text('Sonuç')),
          bottomNavigationBar: _CommitSection(
            decision: decision,
            recommendedOptionId: result.recommendedOptionId,
            onCommit: (optionId) => ref
                .read(decisionEditorProvider(decisionId).notifier)
                .commitDecision(optionId),
            onRevert: () => ref
                .read(decisionEditorProvider(decisionId).notifier)
                .revertDecision(),
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppTokens.s4),
            children: [
              // Önerilen seçenek kartı
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.s4),
                  child: Column(
                    children: [
                      Text(
                        'Önerilen seçenek',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s1),
                      Text(
                        winner.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s2),
                      _ConfidenceChip(result.confidence),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s4),
              Text('Sıralama', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppTokens.s2),
              for (final (rank, score) in result.ranking.indexed)
                _ScoreBar(
                  rank: rank + 1,
                  title: byId[score.optionId]?.title ?? '—',
                  score: score.score,
                  isWinner: score.optionId == result.recommendedOptionId,
                  isChosen: score.optionId == decision.chosenOptionId,
                ),
              const SizedBox(height: AppTokens.s6),
              // AI analiz bölümü (6D-1: mock kontrolcü; 6D-2: gerçek istemci)
              AnalysisSection(decisionId: decisionId),
            ],
          ),
        );
      },
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip(this.confidence);
  final Confidence confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      Confidence.high => ('Yüksek güven', Colors.green),
      Confidence.medium => ('Orta güven', Colors.orange),
      Confidence.low => ('Düşük güven — fark çok az', Colors.red),
    };
    return Chip(
      avatar: Icon(Icons.verified_outlined, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.rank,
    required this.title,
    required this.score,
    required this.isWinner,
    this.isChosen = false,
  });

  final int rank;
  final String title;
  final double score;
  final bool isWinner;

  /// Kullanıcının "Kararımı Verdim" ile seçtiği seçenek (Sprint B vurgusu).
  final bool isChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$rank.', style: theme.textTheme.labelLarge),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isWinner || isChosen
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (isChosen) ...[
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppTokens.s1),
              ],
              Text(
                score.toStringAsFixed(0),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s1),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 8,
              color: isWinner
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondaryContainer,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sprint B — alt bar: karar verilmediyse "Kararımı Verdim" CTA'sı,
/// verildiyse seçim + "Değiştir". Karar taahhüt anı burada kapanır.
class _CommitSection extends StatelessWidget {
  const _CommitSection({
    required this.decision,
    required this.recommendedOptionId,
    required this.onCommit,
    required this.onRevert,
  });

  final Decision decision;
  final String recommendedOptionId;
  final Future<void> Function(String optionId) onCommit;
  final Future<void> Function() onRevert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: decision.isDecided
            ? Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(
                    child: Text(
                      '${_chosenTitle()} seçildi',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openSheet(context),
                    child: const Text('Değiştir'),
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.how_to_reg),
                  label: const Text('Kararımı Verdim'),
                  onPressed: () => _openSheet(context),
                ),
              ),
      ),
    );
  }

  String _chosenTitle() {
    final chosen = decision.options
        .where((o) => o.id == decision.chosenOptionId)
        .map((o) => o.title);
    return chosen.isEmpty ? 'Seçimin' : chosen.first;
  }

  Future<void> _openSheet(BuildContext context) {
    // Önseçim: mevcut seçim, yoksa önerilen seçenek.
    final initial = decision.chosenOptionId ?? recommendedOptionId;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) => _CommitSheet(
        options: decision.options,
        initialId: initial,
        recommendedOptionId: recommendedOptionId,
        canRevert: decision.isDecided,
        onCommit: onCommit,
        onRevert: onRevert,
      ),
    );
  }
}

class _CommitSheet extends StatefulWidget {
  const _CommitSheet({
    required this.options,
    required this.initialId,
    required this.recommendedOptionId,
    required this.canRevert,
    required this.onCommit,
    required this.onRevert,
  });

  final List<Option> options;
  final String initialId;
  final String recommendedOptionId;
  final bool canRevert;
  final Future<void> Function(String optionId) onCommit;
  final Future<void> Function() onRevert;

  @override
  State<_CommitSheet> createState() => _CommitSheetState();
}

class _CommitSheetState extends State<_CommitSheet> {
  late String _selected = widget.initialId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppTokens.s4,
        right: AppTokens.s4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppTokens.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Hangisini seçtin?', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppTokens.s2),
          for (final option in widget.options)
            InkWell(
              onTap:
                  _saving ? null : () => setState(() => _selected = option.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
                child: Row(
                  children: [
                    Icon(
                      option.id == _selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: option.id == _selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTokens.s3),
                    Expanded(child: Text(option.title)),
                    if (option.id == widget.recommendedOptionId)
                      Text(
                        'önerilen ⭐',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppTokens.s2),
          FilledButton(
            onPressed: _saving ? null : _commit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Bu kararı veriyorum'),
          ),
          if (widget.canRevert)
            TextButton(
              onPressed: _saving ? null : _revert,
              child: const Text('Kararı geri al'),
            ),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    setState(() => _saving = true);
    await widget.onCommit(_selected);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _revert() async {
    setState(() => _saving = true);
    await widget.onRevert();
    if (mounted) Navigator.of(context).pop();
  }
}
