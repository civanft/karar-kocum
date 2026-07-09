import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/entities/ai_analysis.dart';
import '../providers/analysis_providers.dart';

/// Sonuç ekranındaki AI bölümü — provider'a bağlı kabuk.
/// Görsel katman [AnalysisStateView]'da: galeri ve widget testleri
/// durumu doğrudan enjekte eder.
class AnalysisSection extends ConsumerWidget {
  const AnalysisSection({super.key, required this.decisionId});
  final String decisionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisControllerProvider(decisionId));
    final controller =
        ref.read(analysisControllerProvider(decisionId).notifier);

    return AnalysisStateView(
      state: state,
      onAnalyze: controller.analyze,
      onRetry: controller.analyze,
      onReanalyze: () => _confirmReanalyze(context, controller),
      onFeedback: (up) => controller.sendFeedback(thumbsUp: up),
    );
  }

  Future<void> _confirmReanalyze(
    BuildContext context,
    AnalysisController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeniden analiz edilsin mi?'),
        content: const Text(
          'Mevcut analiz silinip yenisi oluşturulacak. '
          'Bu işlem aylık analiz hakkından düşer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yeniden Analiz Et'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.reanalyze();
  }
}

/// 5 durumun saf görsel karşılığı — durum dışarıdan verilir.
class AnalysisStateView extends StatelessWidget {
  const AnalysisStateView({
    super.key,
    required this.state,
    this.onAnalyze,
    this.onRetry,
    this.onReanalyze,
    this.onFeedback,
  });

  final AnalysisState state;
  final VoidCallback? onAnalyze;
  final VoidCallback? onRetry;
  final VoidCallback? onReanalyze;
  final ValueChanged<bool>? onFeedback;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppTokens.durMed,
      switchInCurve: Curves.easeOut,
      child: switch (state) {
        AnalysisIdle() => _IdleCard(onAnalyze: onAnalyze),
        AnalysisLoading() => const _LoadingCard(),
        AnalysisSuccess(:final analysis) => _SuccessCard(
            analysis: analysis,
            onReanalyze: onReanalyze,
            onFeedback: onFeedback,
          ),
        AnalysisError(:final message, :final retryable) =>
          _ErrorCard(message: message, retryable: retryable, onRetry: onRetry),
        AnalysisQuotaExceeded(:final monthlyLimit) =>
          _QuotaCard(monthlyLimit: monthlyLimit),
      },
    );
  }
}

// ---- 1. Boş durum: CTA ----

class _IdleCard extends StatelessWidget {
  const _IdleCard({this.onAnalyze});
  final VoidCallback? onAnalyze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Shell(
      key: const ValueKey('analysis-idle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: AppTokens.s2),
              Text('AI Analizi', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            'Kararını tarafsız gözle değerlendirt: güçlü ve zayıf yönler, '
            'gözden kaçan riskler ve net bir öneri.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTokens.s4),
          FilledButton.icon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('AI Analizini Başlat'),
          ),
        ],
      ),
    );
  }
}

// ---- 2. Loading: iskelet + nabız ----

class _LoadingCard extends StatefulWidget {
  const _LoadingCard();

  @override
  State<_LoadingCard> createState() => _LoadingCardState();
}

class _LoadingCardState extends State<_LoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Shell(
      key: const ValueKey('analysis-loading'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Text(
                'Kararın analiz ediliyor…',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 0.9).animate(_pulse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final width in const [0.9, 0.75, 0.85, 0.5])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.s2),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: width,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusSm),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            'Genelde 10 saniyeden kısa sürer.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---- 3. Başarılı analiz ----

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.analysis,
    this.onReanalyze,
    this.onFeedback,
  });

  final AiAnalysis analysis;
  final VoidCallback? onReanalyze;
  final ValueChanged<bool>? onFeedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Shell(
      key: const ValueKey('analysis-success'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Text('AI Analizi', style: theme.textTheme.titleMedium),
              ),
              _ConfidenceBadge(analysis.confidence),
            ],
          ),
          const SizedBox(height: AppTokens.s3),

          // Öneri bandı
          Container(
            padding: const EdgeInsets.all(AppTokens.s3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: Text(
                    analysis.recommendation,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s3),

          Text(analysis.summary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppTokens.s4),

          _InsightList(
            title: 'Güçlü yönler',
            icon: Icons.check_circle_outline,
            color: Colors.green.shade600,
            items: analysis.strengths,
          ),
          _InsightList(
            title: 'Zayıf yönler',
            icon: Icons.remove_circle_outline,
            color: Colors.orange.shade700,
            items: analysis.weaknesses,
          ),
          _InsightList(
            title: 'Riskler',
            icon: Icons.warning_amber_outlined,
            color: theme.colorScheme.error,
            items: analysis.risks,
          ),

          const Divider(height: AppTokens.s6),
          Row(
            children: [
              Text(
                'Bu analiz yardımcı oldu mu?',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Evet',
                icon: const Icon(Icons.thumb_up_outlined, size: 20),
                onPressed: onFeedback == null ? null : () => onFeedback!(true),
              ),
              IconButton(
                tooltip: 'Hayır',
                icon: const Icon(Icons.thumb_down_outlined, size: 20),
                onPressed: onFeedback == null ? null : () => onFeedback!(false),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: onReanalyze,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Yeniden analiz et'),
          ),
          Text(
            'AI analizi bir karar destek aracıdır; nihai karar senindir.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 4. Hata durumu ----

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.retryable,
    this.onRetry,
  });

  final String message;
  final bool retryable;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Shell(
      key: const ValueKey('analysis-error'),
      borderColor: theme.colorScheme.error.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: theme.colorScheme.error),
              const SizedBox(width: AppTokens.s2),
              Text('Analiz yapılamadı', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (retryable) ...[
            const SizedBox(height: AppTokens.s3),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- 5. Kota doldu ----

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.monthlyLimit});
  final int monthlyLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];

    return _Shell(
      key: const ValueKey('analysis-quota'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_bottom, color: theme.colorScheme.tertiary),
              const SizedBox(width: AppTokens.s2),
              Text(
                'Aylık analiz hakkın doldu',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            'Bu ay $monthlyLimit ücretsiz AI analizinin tamamını kullandın. '
            'Hakların 1 ${months[nextMonth.month - 1]}\'ta yenilenecek.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            'Skor tablon ve karşılaştırman her zaman kullanılabilir durumda.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          // Premium CTA'sı Sprint 5'te buraya gelecek (paywall_viewed olayı).
        ],
      ),
    );
  }
}

// ---- Ortak kabuk ve parçalar ----

class _Shell extends StatelessWidget {
  const _Shell({super.key, required this.child, this.borderColor});
  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        side: BorderSide(
          color: borderColor ?? theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: child,
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge(this.confidence);
  final AnalysisConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      AnalysisConfidence.high => ('Yüksek güven', Colors.green.shade600),
      AnalysisConfidence.medium => ('Orta güven', Colors.orange.shade700),
      AnalysisConfidence.low => ('Düşük güven', Colors.red.shade600),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s2,
        vertical: AppTokens.s1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
          const SizedBox(height: AppTokens.s1),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(
                    child: Text(item, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
