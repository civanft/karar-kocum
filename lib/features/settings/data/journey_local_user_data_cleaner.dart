import '../../ai_analysis/domain/pending_analysis_request.dart';
import '../../journey/domain/follow_up_preferences.dart';
import '../../journey/domain/follow_up_scheduler.dart';
import '../domain/account_deletion.dart';

/// [LocalUserDataCleaner] ↔ journey sözleşmeleri adaptörü (PR-R1).
///
/// Cihazda tutulan tek kullanıcı verisi takip sözleridir (Firestore'a
/// yazılmaz) ve bunların karşılığı planlanmış yerel bildirimlerdir.
/// Settings domain'i bunu bilmez; bağ yalnız burada kurulur.
///
/// Adımlar birbirini engellemez: tercih temizliği yapıldıysa bildirim
/// iptali patlasa bile temizlik kaybolmaz (bildirimler tetiklendiğinde
/// karar bulunamaz, akış zaten güvenli sonlanır).
class JourneyLocalUserDataCleaner implements LocalUserDataCleaner {
  const JourneyLocalUserDataCleaner({
    required this.preferences,
    required this.scheduler,
    required this.pendingAnalysisRequests,
  });

  final FollowUpPreferences preferences;
  final FollowUpScheduler scheduler;

  /// İş Paketi 2: cihazda kalan bekleyen analiz idempotency anahtarları.
  final PendingAnalysisRequestStore pendingAnalysisRequests;

  @override
  Future<void> clearAll() async {
    await _ignoringErrors(preferences.clearAll);
    await _ignoringErrors(scheduler.cancelAll);
    await _ignoringErrors(pendingAnalysisRequests.clearAll);
  }

  static Future<void> _ignoringErrors(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // Yerel temizlik en iyi çaba; sunucu verisi zaten silinmiş olur.
    }
  }
}
