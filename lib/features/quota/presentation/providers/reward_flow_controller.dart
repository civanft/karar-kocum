import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../decision/presentation/providers/decision_providers.dart';
import '../../domain/repositories/reward_ports.dart';
import 'credits_providers.dart';

/// Ödül akışı durumları — UI bunları render eder.
sealed class RewardState {
  const RewardState();
}

class RewardIdle extends RewardState {
  const RewardIdle();
}

class RewardInProgress extends RewardState {
  const RewardInProgress(this.stage); // ticket | ad | verifying
  final String stage;
}

class RewardEarned extends RewardState {
  const RewardEarned();
}

class RewardFailed extends RewardState {
  const RewardFailed(this.message);
  final String message;
}

/// Gerçek adaptörler AdMob kurulumuyla gelir (7B); varsayılanlar kapalı.
final rewardTicketPortProvider =
    Provider<RewardTicketPort>((_) => const UnavailableRewardTicketPort());
final rewardedAdPortProvider =
    Provider<RewardedAdPort>((_) => const UnavailableRewardedAdPort());

/// Buton görünürlüğü: reklam altyapısı hazır mı?
final rewardAdsAvailableProvider =
    Provider<bool>((ref) => ref.watch(rewardedAdPortProvider).isAvailable);

/// SSV doğrulama bekleme süresi (callback → Firestore yansıması).
final rewardVerifyTimeoutProvider =
    Provider<Duration>((_) => const Duration(seconds: 12));

class RewardFlowController extends AutoDisposeNotifier<RewardState> {
  @override
  RewardState build() => const RewardIdle();

  Future<void> watchAd() async {
    if (state is RewardInProgress) return; // çift tık koruması

    final tickets = ref.read(rewardTicketPortProvider);
    final ads = ref.read(rewardedAdPortProvider);
    final credits = ref.read(creditsRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    final timeout = ref.read(rewardVerifyTimeoutProvider);

    try {
      // Ödül geldi mi kıyası için taban değer:
      final baseline = await credits.watchRemaining().first;

      state = const RewardInProgress('ticket');
      final ticketId = await tickets.createTicket();

      state = const RewardInProgress('ad');
      final outcome = await ads.show(ssvUserId: uid, ticketId: ticketId);

      switch (outcome) {
        case AdOutcome.dismissed:
          // Kural: reklam tamamlanmadan kredi yok.
          state = const RewardFailed(
            'Reklam tamamlanmadı — kredi eklenmedi. İstersen tekrar dene.',
          );
          return;
        case AdOutcome.failed:
          state = const RewardFailed(
            'Reklam şu an gösterilemiyor, birazdan tekrar dene.',
          );
          return;
        case AdOutcome.completed:
          break;
      }

      // Ödülü İSTEMCİ VERMEZ: AdMob SSV callback'inin Firestore'a
      // yazmasını bekle; kredi akışı artınca kazanılmış say.
      state = const RewardInProgress('verifying');
      final earned = await credits
          .watchRemaining()
          .firstWhere((value) => value > baseline)
          .timeout(timeout)
          .then((_) => true)
          .catchError((_) => false);

      state = earned
          ? const RewardEarned()
          : const RewardFailed(
              'Ödül doğrulaması gecikti — kredin birkaç dakika içinde '
              'hesabına yansıyabilir.',
            );
    } catch (_) {
      state = const RewardFailed(
        'Bir şeyler ters gitti, lütfen tekrar dene.',
      );
    }
  }

  void reset() => state = const RewardIdle();
}

final rewardFlowProvider =
    NotifierProvider.autoDispose<RewardFlowController, RewardState>(
  RewardFlowController.new,
);
