import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_notification_follow_up_scheduler.dart';
import '../../data/prefs_follow_up_preferences.dart';
import '../../domain/follow_up_coordinator.dart';
import '../../domain/follow_up_preferences.dart';
import '../../domain/follow_up_scheduler.dart';

/// Takip sözü tercihi — testlerde InMemory ile override edilir.
final followUpPreferencesProvider = Provider<FollowUpPreferences>(
  (_) => const PrefsFollowUpPreferences(),
);

/// Yerel bildirim eklentisi — testlerde bu katmana hiç inilmez
/// (scheduler override edilir).
final localNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>(
  (_) => FlutterLocalNotificationsPlugin(),
);

/// Bildirim planlayıcı — testlerde Recording ile override edilir.
final followUpSchedulerProvider = Provider<FollowUpScheduler>(
  (ref) => LocalNotificationFollowUpScheduler(
    ref.watch(localNotificationsPluginProvider),
  ),
);

/// Takip sözü politikasının tek giriş noktası.
final followUpCoordinatorProvider = Provider<FollowUpCoordinator>(
  (ref) => FollowUpCoordinator(
    preferences: ref.watch(followUpPreferencesProvider),
    scheduler: ref.watch(followUpSchedulerProvider),
  ),
);
