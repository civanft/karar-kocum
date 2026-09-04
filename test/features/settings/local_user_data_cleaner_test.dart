import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/pending_analysis_request.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/data/prefs_follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_preferences.dart';
import 'package:karar_veriyorum/features/journey/domain/follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/settings/data/journey_local_user_data_cleaner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PR-R1 — cihazdaki kullanıcı izlerinin temizlenmesi.
///
/// Settings domain'i journey'i TANIMAZ: temizleme tek bir port
/// (LocalUserDataCleaner) arkasındadır; bu sınıf o portu journey
/// sözleşmelerine bağlayan data-katmanı adaptörüdür.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('takip tercihlerini VE planlı bildirimleri temizler', () async {
    final calls = <String>[];
    final cleaner = JourneyLocalUserDataCleaner(
      preferences: _RecordingPreferences(calls),
      scheduler: _RecordingScheduler(calls),
      pendingAnalysisRequests: _RecordingPending(calls),
    );

    await cleaner.clearAll();

    // İş Paketi 2: bekleyen analiz idempotency anahtarları da silinir.
    expect(calls, [
      'prefs:clearAll',
      'scheduler:cancelAll',
      'pending:clearAll',
    ]);
  });

  test('bildirim iptali patlasa da tercihler temizlenmiş kalır', () async {
    final calls = <String>[];
    final cleaner = JourneyLocalUserDataCleaner(
      preferences: _RecordingPreferences(calls),
      scheduler: _RecordingScheduler(calls, throwOnCancelAll: true),
      pendingAnalysisRequests: _RecordingPending(calls),
    );

    await expectLater(cleaner.clearAll(), completes);
    expect(calls, contains('prefs:clearAll'));
  });

  test(
      'PrefsFollowUpPreferences.clearAll journey.followUpOptedIn anahtarını '
      'siler', () async {
    SharedPreferences.setMockInitialValues({
      'journey.followUpOptedIn': ['karar-1', 'karar-2'],
      'baska.anahtar': 'korunmalı',
    });
    const prefs = PrefsFollowUpPreferences();

    expect(await prefs.isOptedIn('karar-1'), isTrue);
    await prefs.clearAll();

    expect(await prefs.isOptedIn('karar-1'), isFalse);
    final store = await SharedPreferences.getInstance();
    expect(store.containsKey('journey.followUpOptedIn'), isFalse);
    // Yalnız takip tercihi silinir; başka anahtarlara dokunulmaz.
    expect(store.getString('baska.anahtar'), 'korunmalı');
  });

  test('InMemoryFollowUpPreferences.clearAll tüm sözleri düşürür', () async {
    final prefs = InMemoryFollowUpPreferences();
    await prefs.setOptedIn('karar-1', value: true);

    await prefs.clearAll();

    expect(await prefs.isOptedIn('karar-1'), isFalse);
  });

  test('RecordingFollowUpScheduler.cancelAll planları düşürür', () async {
    final scheduler = RecordingFollowUpScheduler();
    await scheduler.schedule(
      decisionId: 'karar-1',
      decisionTitle: 'Başlık',
      at: DateTime(2026, 8, 21),
    );

    await scheduler.cancelAll();

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelledAll, isTrue);
  });
}

class _RecordingPreferences implements FollowUpPreferences {
  _RecordingPreferences(this.calls);
  final List<String> calls;

  @override
  Future<bool> isOptedIn(String decisionId) async => false;

  @override
  Future<void> setOptedIn(String decisionId, {required bool value}) async {}

  @override
  Future<void> clearAll() async => calls.add('prefs:clearAll');
}

class _RecordingScheduler implements FollowUpScheduler {
  _RecordingScheduler(this.calls, {this.throwOnCancelAll = false});
  final List<String> calls;
  final bool throwOnCancelAll;

  @override
  Future<void> initialize({
    required void Function(String decisionId) onTap,
  }) async {}

  @override
  Future<void> schedule({
    required String decisionId,
    required String decisionTitle,
    required DateTime at,
  }) async {}

  @override
  Future<void> cancel(String decisionId) async {}

  @override
  Future<void> cancelAll() async {
    calls.add('scheduler:cancelAll');
    if (throwOnCancelAll) throw StateError('bildirim eklentisi hatası');
  }
}

/// Bekleyen analiz isteklerinin temizlendiğini kaydeder.
class _RecordingPending implements PendingAnalysisRequestStore {
  _RecordingPending(this.calls);
  final List<String> calls;

  @override
  Future<void> clearAll() async => calls.add('pending:clearAll');

  @override
  Future<void> clear({
    required String uid,
    required String decisionId,
  }) async {}

  @override
  Future<String?> read({
    required String uid,
    required String decisionId,
  }) async =>
      null;

  @override
  Future<void> write({
    required String uid,
    required String decisionId,
    required String requestId,
  }) async {}
}
