import 'follow_up_preferences.dart';
import 'follow_up_scheduler.dart';

/// Decision Journey — takip sözünün TEK politika noktası (Sprint C.1).
///
/// Verilen söz ("1 hafta sonra sorayım mı?") burada tutulur. Kural seti:
///  - taahhüt + söz var  → +7 gün bildirim planla (üzerine yazarak)
///  - taahhüt + söz yok  → planlı bildirim varsa iptal et
///  - karar geri alındı  → iptal et (ortada tutulacak söz kalmadı)
///  - karar silindi      → iptal et + tercihi temizle (yetim kayıt bırakma)
///
/// Zaman [clock] üzerinden alınır; testler sabit saat verir.
class FollowUpCoordinator {
  FollowUpCoordinator({
    required FollowUpPreferences preferences,
    required FollowUpScheduler scheduler,
    DateTime Function()? clock,
    void Function(Object error, StackTrace stack)? onError,
  })  : _preferences = preferences,
        _scheduler = scheduler,
        _clock = clock ?? DateTime.now,
        _onError = onError;

  final FollowUpPreferences _preferences;
  final FollowUpScheduler _scheduler;
  final DateTime Function() _clock;
  final void Function(Object error, StackTrace stack)? _onError;

  /// Sözün vadesi. Ürün kararı: taahhütten 1 hafta sonra.
  static const followUpDelay = Duration(days: 7);

  /// Takip bildirimi EN İYİ ÇABA'dır: yerel depolama ya da bildirim izni
  /// erişilemezse kullanıcının kararını verememesine ASLA yol açmamalı.
  /// Bu yüzden tüm yan etkiler burada yalıtılır.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, s) {
      _onError?.call(e, s);
    }
  }

  /// Kullanıcı söz sorusunu cevapladığında çağrılır (söz ekranı).
  /// Tercihi kaydeder ve bildirimi buna göre planlar/iptal eder.
  Future<void> answerPromise({
    required String decisionId,
    required String decisionTitle,
    required bool optIn,
  }) =>
      _guard(() async {
        await _preferences.setOptedIn(decisionId, value: optIn);
        if (optIn) {
          await _scheduler.schedule(
            decisionId: decisionId,
            decisionTitle: decisionTitle,
            at: _clock().add(followUpDelay),
          );
        } else {
          await _scheduler.cancel(decisionId);
        }
      });

  /// Karar (yeniden) taahhüt edildiğinde çağrılır. Söz zaten verilmişse
  /// vade YENİ taahhüt anından başlar — revert → tekrar karar akışında
  /// bildirim böylece yeniden planlanır.
  Future<void> onCommitted({
    required String decisionId,
    required String decisionTitle,
  }) =>
      _guard(() async {
        if (!await _preferences.isOptedIn(decisionId)) return;
        await _scheduler.schedule(
          decisionId: decisionId,
          decisionTitle: decisionTitle,
          at: _clock().add(followUpDelay),
        );
      });

  /// Karar geri alındığında çağrılır. Tercih KORUNUR: kullanıcı aynı kararı
  /// tekrar verdiğinde tekrar sorulmadan yeniden planlanabilsin diye.
  Future<void> onReverted(String decisionId) =>
      _guard(() => _scheduler.cancel(decisionId));

  /// Karar silindiğinde çağrılır — bildirim iptal, tercih temizlenir.
  Future<void> onDeleted(String decisionId) => _guard(() async {
        await _scheduler.cancel(decisionId);
        await _preferences.setOptedIn(decisionId, value: false);
      });
}
