import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/tokens.dart';
import '../../../decision/domain/entities/decision.dart';
import '../../../decision/presentation/providers/decision_editor.dart';
import '../providers/journey_providers.dart';

/// SPRINT C.2 — 1 hafta kontrol ekranı.
///
/// Koç verdiği sözü burada tutar: "Nasıl gidiyor?" Cevap ÇEKİRDEK veridir,
/// Firestore'a yazılır (Karar Sağlığı / Yıllık Karne / AI koçluğu besler).
/// Bildirim temizliği cihazda kalır.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, required this.decisionId});
  final String decisionId;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  bool _saving = false;

  Future<void> _answer(DecisionCheckIn status) async {
    if (_saving) return;
    setState(() => _saving = true);

    final failure = await ref
        .read(decisionEditorProvider(widget.decisionId).notifier)
        .submitCheckIn(status);

    // Bildirim temizliği BEKLENMEZ: cevap zaten yazıldı, yerel temizlik
    // kullanıcıyı ekranda tutmamalı (Sprint C.1 dersi).
    unawaited(
      ref.read(followUpCoordinatorProvider).onReverted(widget.decisionId),
    );

    if (!mounted) return;
    if (failure != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi, tekrar dener misin?')),
      );
      return;
    }
    context.go('/decision/${widget.decisionId}/result');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decisionAsync = ref.watch(decisionEditorProvider(widget.decisionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Kontrol')),
      body: decisionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Yüklenemedi: $e')),
        data: (decision) {
          // Gönderim sürerken: submitCheckIn iyimser olarak checkInStatus'ı
          // hemen yazar → canCheckIn false olur. Bu kontrol canCheckIn'den
          // ÖNCE gelmezse, sonuç ekranına gitmeden hemen önce _AlreadyDone
          // bir frame görünür (flaş). Kararlı "kaydediliyor" görünümü ver.
          if (_saving) {
            return const _SavingView();
          }
          // Zaten cevaplanmış ya da karar geri alınmış → güvenli düşüş.
          if (!decision.canCheckIn) {
            return _AlreadyDone(
              decision: decision,
              onClose: () => context.go('/home'),
            );
          }

          final chosen = decision.options
              .where((o) => o.id == decision.chosenOptionId)
              .map((o) => o.title)
              .firstOrNull;
          final days = decision.decidedAt == null
              ? 7
              : DateTime.now().difference(decision.decidedAt!).inDays;

          return Padding(
            padding: const EdgeInsets.all(AppTokens.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppTokens.s4),
                Text(
                  chosen == null
                      ? 'Kararının üzerinden $days gün geçti.'
                      : '$chosen kararının üzerinden $days gün geçti.',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppTokens.s2),
                Text(
                  'Nasıl gidiyor?',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppTokens.s6),
                _CheckInOption(
                  emoji: '😌',
                  label: 'Memnunum',
                  enabled: !_saving,
                  onTap: () => _answer(DecisionCheckIn.happy),
                ),
                const SizedBox(height: AppTokens.s3),
                _CheckInOption(
                  emoji: '😐',
                  label: 'Kararsızım',
                  enabled: !_saving,
                  onTap: () => _answer(DecisionCheckIn.neutral),
                ),
                const SizedBox(height: AppTokens.s3),
                _CheckInOption(
                  emoji: '😣',
                  label: 'Pişmanım',
                  enabled: !_saving,
                  onTap: () => _answer(DecisionCheckIn.regret),
                ),
                const Spacer(),
                Text(
                  'Cevabın yalnız sana ait; kararlarının nasıl gittiğini '
                  'zamanla birlikte göreceğiz.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Cevap yazılırken gösterilen kararlı ara görünüm — _AlreadyDone flaşını
/// engeller ve kullanıcıyı ikinci seçimden alıkoyar (seçenekler render
/// edilmez; _answer da _saving guard'ıyla korunur).
class _SavingView extends StatelessWidget {
  const _SavingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppTokens.s4),
          Text(
            'Cevabın kaydediliyor…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _CheckInOption extends StatelessWidget {
  const _CheckInOption({
    required this.emoji,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: AppTokens.s4),
          Text(label, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Karar başına TEK kayıt: ikinci kez gelindiğinde soru tekrar sorulmaz.
class _AlreadyDone extends StatelessWidget {
  const _AlreadyDone({required this.decision, required this.onClose});

  final Decision decision;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = decision.hasCheckedIn;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              answered ? Icons.check_circle_outline : Icons.info_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              answered
                  ? 'Bu kararın kontrolünü zaten yaptın.'
                  : 'Bu karar henüz verilmiş değil.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.s4),
            FilledButton(onPressed: onClose, child: const Text('Tamam')),
          ],
        ),
      ),
    );
  }
}
