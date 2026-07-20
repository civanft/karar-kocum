import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/follow_up_scheduler.dart';

/// Yerel bildirim tabanlı planlayıcı (Sprint C.1).
///
/// FCM/Firebase KULLANMAZ — bildirim tamamen cihazda planlanır, ağ ve
/// Firestore maliyeti sıfırdır.
///
/// Bildirim kimliği karar kimliğinin hash'inden türetilir: eklenti int id
/// ister, kararlarımızın kimliği string'tir. Aynı karar → aynı id → aynı
/// kararı yeniden planlamak eskisini otomatik değiştirir (idempotent).
class LocalNotificationFollowUpScheduler implements FollowUpScheduler {
  LocalNotificationFollowUpScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'journey_follow_up';
  static const _channelName = 'Karar takibi';
  static const _channelDescription =
      'Verdiğin kararların bir hafta sonraki kontrolü';

  bool _ready = false;

  /// Bildirim kimliği — 32-bit pozitif aralığa sıkıştırılır (Android sınırı).
  static int notificationIdFor(String decisionId) =>
      decisionId.hashCode & 0x7fffffff;

  /// Eklenti + saat dilimi kurulumu ve izin isteği — İLK PLANLAMADA yapılır.
  /// Bilinçli tercih: izin dialogu uygulama açılışında değil, kullanıcı
  /// gerçekten "Evet, sor" dediğinde çıkar (istek bağlamı net olsun).
  Future<void> _ensureReady() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // İzni burada değil, aşağıda açıkça istiyoruz.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  @override
  Future<void> schedule({
    required String decisionId,
    required String decisionTitle,
    required DateTime at,
  }) async {
    await _ensureReady();
    await _plugin.zonedSchedule(
      notificationIdFor(decisionId),
      'Nasıl gitti?',
      '"$decisionTitle" kararını bir hafta önce vermiştin. Kontrol edelim mi?',
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Kesin alarm gerekmez; sistem uygun ana kaydırabilir. Bu sayede
      // Android 13+ SCHEDULE_EXACT_ALARM izni İSTENMEZ.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Bildirime dokunulduğunda hangi kararın açılacağını bilelim.
      payload: decisionId,
    );
  }

  @override
  Future<void> cancel(String decisionId) =>
      _plugin.cancel(notificationIdFor(decisionId));
}

/// Testler ve bildirim izni olmayan ortamlar için kayıt tutan sahte.
class RecordingFollowUpScheduler implements FollowUpScheduler {
  final scheduled = <String, DateTime>{};
  final cancelled = <String>[];

  @override
  Future<void> schedule({
    required String decisionId,
    required String decisionTitle,
    required DateTime at,
  }) async {
    scheduled[decisionId] = at;
  }

  @override
  Future<void> cancel(String decisionId) async {
    scheduled.remove(decisionId);
    cancelled.add(decisionId);
  }
}
