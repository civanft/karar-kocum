import '../../decision/domain/entities/decision.dart';
import 'follow_up_coordinator.dart';

/// Decision Journey — bir kararın 1 hafta kontrolünün "zamanı geldi mi"
/// politikası (Sprint C-4, Home koç kartı).
///
/// Saf domain: Flutter'a bağlı DEĞİL. Gecikme, tek ürün politikası olan
/// [FollowUpCoordinator.followUpDelay]'den gelir — Home kartı ile bildirim
/// planlaması AYNI gecikmeyi kullanır (yeni sabit üretilmez).
///
/// Bildirim tercihi (SharedPreferences opt-in) bu karara GİRMEZ: kart,
/// bildirim reddedilmiş/kapatılmış olsa da uygulama-içi giriş noktasıdır.
class CheckInDuePolicy {
  const CheckInDuePolicy();

  /// Kararın kontrol tarihi: taahhüt anı + gecikme. [Decision.decidedAt]
  /// yoksa null (henüz verilmemiş ya da alan eksik).
  DateTime? dueAt(Decision decision) {
    final decidedAt = decision.decidedAt;
    if (decidedAt == null) return null;
    return decidedAt.add(FollowUpCoordinator.followUpDelay);
  }

  /// [now] anında bu karar için kontrol zamanı gelmiş mi? Tüm koşullar:
  /// verilmiş · henüz cevaplanmamış · decidedAt dolu · now >= dueAt.
  bool isDue(Decision decision, DateTime now) {
    if (!decision.isDecided) return false;
    if (decision.hasCheckedIn) return false;
    final due = dueAt(decision);
    if (due == null) return false;
    return !now.isBefore(due); // now >= due
  }

  /// Listeden due kararlar; en uzun süredir bekleyenden (en eski decidedAt)
  /// başlar. Eşit decidedAt'te id ile deterministik sıralanır.
  List<Decision> dueDecisions(Iterable<Decision> decisions, DateTime now) {
    final due = [
      for (final d in decisions)
        if (isDue(d, now)) d,
    ]..sort((a, b) {
        final byDecidedAt = a.decidedAt!.compareTo(b.decidedAt!);
        return byDecidedAt != 0 ? byDecidedAt : a.id.compareTo(b.id);
      });
    return due;
  }
}
