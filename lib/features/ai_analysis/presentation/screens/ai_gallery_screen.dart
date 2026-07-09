import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/entities/ai_analysis.dart';
import '../providers/analysis_providers.dart';
import '../widgets/analysis_card.dart';

/// GELİŞTİRME GALERİSİ — /dev/ai-gallery (UI'dan link YOK).
/// 5 analiz durumunu tek sayfada gösterir: tasarım QA'sı + ekran görüntüsü.
/// Mağaza sürümünden önce kaldırılacak (PR #6E temizlik listesinde).
class AiGalleryScreen extends StatelessWidget {
  const AiGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final states = <String, AnalysisState>{
      '1 · Boş durum (CTA)': const AnalysisIdle(),
      '2 · Loading': const AnalysisLoading(),
      '3 · Başarılı analiz': AnalysisSuccess(AiAnalysis.mock()),
      '4 · Hata durumu': const AnalysisError(
        message: 'Analiz şu an yapılamadı. İnternet bağlantını kontrol '
            'edip tekrar deneyebilirsin.',
        retryable: true,
      ),
      '5 · Kota doldu': const AnalysisQuotaExceeded(totalCredits: 5),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('AI Kart Galerisi (dev)')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: [
          for (final entry in states.entries) ...[
            Text(
              entry.key,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppTokens.s2),
            AnalysisStateView(
              state: entry.value,
              onAnalyze: () {},
              onRetry: () {},
              onReanalyze: () {},
              onFeedback: (_) {},
            ),
            const SizedBox(height: AppTokens.s6),
          ],
        ],
      ),
    );
  }
}
