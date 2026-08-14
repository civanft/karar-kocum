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

  bool _permissionAsked = false;

  /// Bildirim kimliği — 32-bit pozitif aralığa sıkıştırılır (Android sınırı).
  static int notificationIdFor(String decisionId) =>
      decisionId.hashCode & 0x7fffffff;

  /// AÇILIŞTA çağrılır (Sprint C.2). Eklentiyi kurar ve dokunma
  /// callback'ini bağlar.
  ///
  /// NEDEN AÇILIŞTA: kurulumu ilk planlamaya ertelemek dokunma yolunu
  /// çalışmaz kılar — soğuk açılışta hiç schedule() çağrılmaz, dolayısıyla
  /// initialize() de çağrılmaz ve bildirime dokunuş kaybolur.
  ///
  /// İzin İSTENMEZ: o hâlâ ilk planlamada (kullanıcı "Evet, sor" dediğinde)
  /// sorulur — açılışta bağlamsız izin dialogu çıkmasın diye.
  ///
  /// Soğuk açılış: uygulama bildirime dokunularak açıldıysa callback
  /// tetiklenmeyebilir; [getNotificationAppLaunchDetails] ile telafi edilir.
  @override
  Future<void> initialize({
    required void Function(String decisionId) onTap,
  }) async {
    tz_data.initializeTimeZones();
    void handle(String? payload) {
      if (payload != null && payload.isNotEmpty) onTap(payload);
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // İzni burada değil, ilk planlamada istiyoruz.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => handle(r.payload),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      handle(launch!.notificationResponse?.payload);
    }
  }

  /// İzin isteği — İLK PLANLAMADA, yani kullanıcı sözü verdiği anda.
  Future<void> _ensurePermission() async {
    // initialize() çağrılmamış olabilir (ör. planlama başka bir yoldan
    // tetiklendi) — tz.local'sız zonedSchedule patlar. İdempotent.
    tz_data.initializeTimeZones();
    if (_permissionAsked) return;
    _permissionAsked = true;
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<void> schedule({
    required String decisionId,
    required String decisionTitle,
    required DateTime at,
  }) async {
    await _ensurePermission();
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

  /// Hesap silmede kullanılır: kanal bu uygulamaya ait olduğundan
  /// cancelAll yalnız bizim planladıklarımızı düşürür.
  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Testler ve bildirim izni olmayan ortamlar için kayıt tutan sahte.
class RecordingFollowUpScheduler implements FollowUpScheduler {
  final scheduled = <String, DateTime>{};
  final cancelled = <String>[];

  /// cancelAll() çağrıldı mı (PR-R1 hesap silme testleri).
  bool cancelledAll = false;

  /// initialize() ile bağlanan dokunma kancası — testler bunu çağırarak
  /// gerçek bir bildirim dokunuşunu taklit eder.
  void Function(String decisionId)? onTap;

  @override
  Future<void> initialize({
    required void Function(String decisionId) onTap,
  }) async {
    this.onTap = onTap;
  }

  /// Testte "kullanıcı bildirime dokundu".
  void simulateTap(String decisionId) => onTap?.call(decisionId);

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

  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
    cancelled.addAll(scheduled.keys);
    scheduled.clear();
  }
}
