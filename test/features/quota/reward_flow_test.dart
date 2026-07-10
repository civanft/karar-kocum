import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/credits_repository.dart';
import 'package:karar_veriyorum/features/quota/domain/repositories/reward_ports.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/reward_flow_controller.dart';

/// SSV callback'inin Firestore yazımını simüle eden kredi deposu:
/// grant() çağrılınca akış artan değeri yayımlar.
class StreamingCreditsRepository implements CreditsRepository {
  StreamingCreditsRepository(this._value);
  int _value;
  final _controller = StreamController<int>.broadcast();

  void grant() {
    _value += 1;
    _controller.add(_value);
  }

  @override
  Stream<int> watchRemaining() async* {
    yield _value;
    yield* _controller.stream;
  }
}

class FakeTicketPort implements RewardTicketPort {
  int created = 0;
  @override
  Future<String> createTicket() async {
    created++;
    return 'ticket-$created';
  }
}

/// Reklam portu: sonucu ve "tamamlanınca SSV ödülü" davranışı enjekte edilir.
class FakeAdPort implements RewardedAdPort {
  FakeAdPort(this.outcome, {this.onCompleted});
  final AdOutcome outcome;
  final void Function()? onCompleted;
  String? lastTicketId;

  @override
  bool get isAvailable => true;

  @override
  Future<AdOutcome> show({
    required String ssvUserId,
    required String ticketId,
  }) async {
    lastTicketId = ticketId;
    if (outcome == AdOutcome.completed) onCompleted?.call();
    return outcome;
  }
}

void main() {
  ProviderContainer make({
    required FakeAdPort ad,
    required StreamingCreditsRepository credits,
    Duration timeout = const Duration(seconds: 5),
  }) {
    final container = ProviderContainer(
      overrides: [
        rewardTicketPortProvider.overrideWithValue(FakeTicketPort()),
        rewardedAdPortProvider.overrideWithValue(ad),
        creditsRepositoryProvider.overrideWithValue(credits),
        rewardVerifyTimeoutProvider.overrideWithValue(timeout),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose koruması: dinleyici olmadan Notifier imha edilip
    // watchAd sonrası Idle'a sıfırlanmış görünür.
    final sub = container.listen(rewardFlowProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  test('mutlu yol: bilet → reklam tamam → SSV kredisi → Earned', () async {
    final credits = StreamingCreditsRepository(0);
    // Reklam tamamlanınca AdMob callback'inin yazması simüle edilir:
    final ad = FakeAdPort(
      AdOutcome.completed,
      onCompleted: () => Future<void>.delayed(
        const Duration(milliseconds: 20),
        credits.grant,
      ),
    );
    final c = make(ad: ad, credits: credits);

    await c.read(rewardFlowProvider.notifier).watchAd();

    expect(c.read(rewardFlowProvider), isA<RewardEarned>());
    expect(ad.lastTicketId, 'ticket-1'); // bilet reklama iliştirildi
  });

  test('erken kapatma: kredi YOK, açıklayıcı hata', () async {
    final credits = StreamingCreditsRepository(0);
    final c = make(ad: FakeAdPort(AdOutcome.dismissed), credits: credits);

    await c.read(rewardFlowProvider.notifier).watchAd();

    final state = c.read(rewardFlowProvider);
    expect(state, isA<RewardFailed>());
    expect((state as RewardFailed).message, contains('tamamlanmadı'));
    expect(await credits.watchRemaining().first, 0); // kredi eklenmedi
  });

  test('reklam tamam ama SSV gecikti: timeout → bilgilendirici hata', () async {
    final credits = StreamingCreditsRepository(0);
    // onCompleted YOK: callback hiç gelmiyor.
    final c = make(
      ad: FakeAdPort(AdOutcome.completed),
      credits: credits,
      timeout: const Duration(milliseconds: 50),
    );

    await c.read(rewardFlowProvider.notifier).watchAd();

    final state = c.read(rewardFlowProvider);
    expect(state, isA<RewardFailed>());
    expect((state as RewardFailed).message, contains('gecikti'));
  });

  test('reset: hata durumundan Idle\'a döner', () async {
    final credits = StreamingCreditsRepository(0);
    final c = make(ad: FakeAdPort(AdOutcome.failed), credits: credits);

    await c.read(rewardFlowProvider.notifier).watchAd();
    expect(c.read(rewardFlowProvider), isA<RewardFailed>());

    c.read(rewardFlowProvider.notifier).reset();
    expect(c.read(rewardFlowProvider), isA<RewardIdle>());
  });

  test('varsayılan ortam: reklam altyapısı KAPALI (buton gizli)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(rewardAdsAvailableProvider), isFalse);
  });
}
