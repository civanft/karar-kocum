import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/error/failure.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/credits_repository.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/reward_ports.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/reward_flow_controller.dart';

/// PR-P1-UID-1 / DİLİM 4 — oturum yokken ödül akışı.
///
/// UID null iken HİÇBİR port çağrılmamalı: bilet oluşmamalı, reklam
/// gösterilmemeli, SSV'ye boş kullanıcı kimliği gitmemeli, kredi akışı
/// dinlenmemeli.
class _CountingTickets implements RewardTicketPort {
  int calls = 0;
  @override
  Future<String> createTicket() async {
    calls++;
    return 't1';
  }
}

class _CountingAds implements RewardedAdPort {
  int calls = 0;
  final List<String> ssvIds = [];

  @override
  bool get isAvailable => true;
  @override
  Future<AdOutcome> show({
    required String ssvUserId,
    required String ticketId,
  }) async {
    calls++;
    ssvIds.add(ssvUserId);
    return AdOutcome.completed;
  }
}

class _CountingCredits implements CreditsRepository {
  int calls = 0;
  @override
  Stream<int> watchRemaining() {
    calls++;
    return Stream.value(1);
  }
}

void main() {
  test('UID yokken RewardFailed, hiçbir port çağrılmaz', () async {
    final tickets = _CountingTickets();
    final ads = _CountingAds();
    final credits = _CountingCredits();

    final container = ProviderContainer(
      overrides: [
        firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
        currentUidProvider.overrideWithValue(null),
        rewardTicketPortProvider.overrideWithValue(tickets),
        rewardedAdPortProvider.overrideWithValue(ads),
        creditsRepositoryProvider.overrideWithValue(credits),
      ],
    );
    addTearDown(container.dispose);

    await container.read(rewardFlowProvider.notifier).watchAd();

    final state = container.read(rewardFlowProvider);
    expect(state, isA<RewardFailed>());
    expect(
      (state as RewardFailed).message,
      const AuthFailure('missing-session').userMessage,
    );

    expect(tickets.calls, 0, reason: 'bilet oluşturulmamalı');
    expect(ads.calls, 0, reason: 'reklam gösterilmemeli');
    expect(ads.ssvIds, isEmpty, reason: 'SSV user id gönderilmemeli');
    expect(credits.calls, 0, reason: 'kredi akışı başlatılmamalı');
  });
}
