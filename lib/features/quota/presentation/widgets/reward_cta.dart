import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../providers/reward_flow_controller.dart';

/// Kota kartının altında görünen "reklam izle → +1 analiz" bölümü.
/// Reklam altyapısı kapalıyken (AdMob kurulmadan) hiç render edilmez.
class RewardCtaSection extends ConsumerWidget {
  const RewardCtaSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(rewardAdsAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(rewardFlowProvider);
    return RewardCtaView(
      state: state,
      onWatchAd: () => ref.read(rewardFlowProvider.notifier).watchAd(),
      onDismissError: () => ref.read(rewardFlowProvider.notifier).reset(),
    );
  }
}

/// Saf görsel katman — galeri ve widget testleri durumu doğrudan verir.
class RewardCtaView extends StatelessWidget {
  const RewardCtaView({
    super.key,
    required this.state,
    this.onWatchAd,
    this.onDismissError,
  });

  final RewardState state;
  final VoidCallback? onWatchAd;
  final VoidCallback? onDismissError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.s3),
      child: AnimatedSwitcher(
        duration: AppTokens.durMed,
        child: switch (state) {
          RewardIdle() => FilledButton.tonalIcon(
              key: const ValueKey('reward-idle'),
              onPressed: onWatchAd,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Reklam izle → +1 analiz hakkı'),
            ),
          RewardInProgress(:final stage) => Row(
              key: const ValueKey('reward-progress'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppTokens.s2),
                Text(
                  switch (stage) {
                    'ticket' => 'Hazırlanıyor…',
                    'ad' => 'Reklam gösteriliyor…',
                    _ => 'Ödülün doğrulanıyor…',
                  },
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          RewardEarned() => Row(
              key: const ValueKey('reward-earned'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600),
                const SizedBox(width: AppTokens.s2),
                Text(
                  '+1 analiz hakkı eklendi!',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          RewardFailed(:final message) => Column(
              key: const ValueKey('reward-failed'),
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                TextButton(
                  onPressed: onDismissError,
                  child: const Text('Tamam'),
                ),
              ],
            ),
        },
      ),
    );
  }
}
