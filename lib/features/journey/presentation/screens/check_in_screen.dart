import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/app_empty_hint.dart';
import '../../../../core/widgets/app_hero_panel.dart';
import '../../../decision/domain/entities/decision.dart';
import '../../../decision/presentation/providers/decision_editor.dart';
import '../providers/journey_providers.dart';

/// SPRINT C.2 — 1 hafta kontrol ekranı (Görsel Dilim 4B: sıcak koç dili).
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
    // Kaynağı taşı: result ekranı geri davranışını buna göre Home'a çevirir
    // (check-in akışında altta pop edilecek bir stack olmayabilir — cold-start
    // veya go ile gelinen durumlar). Normal puanlama akışı bu parametreyi
    // taşımaz, geri davranışı değişmez.
    context.go('/decision/${widget.decisionId}/result?source=check-in');
  }

  @override
  Widget build(BuildContext context) {
    final decisionAsync = ref.watch(decisionEditorProvider(widget.decisionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Kontrol')),
      body: decisionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Ham exception gösterilmez — güvenli, sıcak düşüş (4B).
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(AppTokens.s4),
          children: [
            AppEmptyHint(
              icon: Icons.search_off_outlined,
              title: 'Bu karar açılamadı',
              message: 'Karar silinmiş veya artık erişilebilir olmayabilir.',
              actionLabel: 'Ana sayfaya dön',
              actionIcon: Icons.home_outlined,
              onAction: () => context.go('/home'),
            ),
          ],
        ),
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

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.s4),
              children: [
                // Koç bölümü — Home hero diliyle hizalı, aksiyonsuz.
                AppHeroPanel(
                  eyebrow: 'Koçundan',
                  title: 'Nasıl gidiyor?',
                  icon: Icons.psychology_outlined,
                  supportText: chosen == null
                      ? 'Kararının üzerinden $days gün geçti.'
                      : '$chosen kararının üzerinden $days gün geçti.',
                ),
                const SizedBox(height: AppTokens.s5),
                _CheckInAnswerCard(
                  icon: Icons.sentiment_satisfied_outlined,
                  tone: _AnswerTone.success,
                  label: 'Memnunum',
                  support: 'Kararımdan memnunum.',
                  enabled: !_saving,
                  onTap: () => _answer(DecisionCheckIn.happy),
                ),
                const SizedBox(height: AppTokens.s3),
                _CheckInAnswerCard(
                  icon: Icons.sentiment_neutral_outlined,
                  tone: _AnswerTone.info,
                  label: 'Kararsızım',
                  support: 'Biraz daha zamana ihtiyacım var.',
                  enabled: !_saving,
                  onTap: () => _answer(DecisionCheckIn.neutral),
                ),
                const SizedBox(height: AppTokens.s3),
                _CheckInAnswerCard(
                  icon: Icons.sentiment_dissatisfied_outlined,
                  tone: _AnswerTone.warning,
                  label: 'Pişmanım',
                  support: 'Farklı bir seçim yapmak isterdim.',
                  enabled: !_saving,
                  onTap: () => _answer(DecisionCheckIn.regret),
                ),
                const SizedBox(height: AppTokens.s5),
                const _PrivacyNote(),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Container(
          padding: const EdgeInsets.all(AppTokens.s6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppTokens.s4),
              Text(
                'Cevabın kaydediliyor…',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cevap kartı ton eşlemesi: yalnız semantik renkler (error/kırmızı YOK).
enum _AnswerTone { success, info, warning }

/// Tam dokunulabilir sıcak cevap kartı (4B) — border + surfaceContainer,
/// düşük-alpha semantik leading ikon, label + kısa destek. ≥64dp hedef.
class _CheckInAnswerCard extends StatelessWidget {
  const _CheckInAnswerCard({
    required this.icon,
    required this.tone,
    required this.label,
    required this.support,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final _AnswerTone tone;
  final String label;
  final String support;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
    final toneColor = switch (tone) {
      _AnswerTone.success => semantic.success,
      _AnswerTone.info => semantic.info,
      _AnswerTone.warning => semantic.warning,
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label. $support',
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(AppTokens.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: toneColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  child: Icon(icon, color: toneColor, size: 22),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        support,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alt güven notu — sahipsiz alt yazı değil; sakin, düşük vurgulu yüzey.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Text(
              'Cevabın yalnız sana ait; kararlarının nasıl gittiğini '
              'zamanla birlikte göreceğiz.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Karar başına TEK kayıt: ikinci kez gelindiğinde soru tekrar sorulmaz.
/// 4B: sıcak AppEmptyHint diline taşındı; kilitli cümleler birebir korunur.
class _AlreadyDone extends StatelessWidget {
  const _AlreadyDone({required this.decision, required this.onClose});

  final Decision decision;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final answered = decision.hasCheckedIn;
    return ListView(
      padding: const EdgeInsets.all(AppTokens.s4),
      children: [
        if (answered)
          AppEmptyHint(
            icon: Icons.check_circle_outline,
            title: 'Bu kararın kontrolünü zaten yaptın.',
            message: 'Bu karar için kontrol yanıtın kaydedildi.',
            actionLabel: 'Tamam',
            actionIcon: Icons.home_outlined,
            onAction: onClose,
          )
        else
          AppEmptyHint(
            icon: Icons.info_outline,
            title: 'Bu karar henüz verilmiş değil.',
            message: 'Kontrol yapabilmek için önce kararını vermelisin.',
            actionLabel: 'Tamam',
            actionIcon: Icons.home_outlined,
            onAction: onClose,
          ),
      ],
    );
  }
}
