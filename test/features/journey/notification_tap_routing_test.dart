import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/journey/data/local_notification_follow_up_scheduler.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/journey_providers.dart';
import 'package:karar_veriyorum/features/journey/presentation/providers/pending_check_in.dart';

/// SPRINT C.2 — bildirime dokunuş → kontrol rotası.
/// Uçtan uca hattın kırılgan halkası: callback widget ağacının DIŞINDA
/// çalışır, o yüzden yönlendirme bir durum üzerinden köprülenir.
void main() {
  late ProviderContainer container;
  late RecordingFollowUpScheduler scheduler;

  setUp(() {
    scheduler = RecordingFollowUpScheduler();
    container = ProviderContainer(
      overrides: [followUpSchedulerProvider.overrideWithValue(scheduler)],
    );
    addTearDown(container.dispose);
  });

  test('açılış planlayıcıyı kurar ve dokunma kancasını bağlar', () async {
    expect(scheduler.onTap, isNull);

    await container.read(journeyBootstrapProvider)();

    expect(scheduler.onTap, isNotNull);
  });

  test('bildirime dokunuş → bekleyen kontrol o karara işaret eder', () async {
    await container.read(journeyBootstrapProvider)();
    expect(container.read(pendingCheckInProvider), isNull);

    scheduler.simulateTap('d42'); // kullanıcı bildirime dokundu

    expect(container.read(pendingCheckInProvider), 'd42');
  });

  test('yönlendirme yapılınca istek tüketilir (iki kez tetiklenmez)', () async {
    await container.read(journeyBootstrapProvider)();
    scheduler.simulateTap('d42');

    container.read(pendingCheckInProvider.notifier).consume();

    expect(container.read(pendingCheckInProvider), isNull);
  });

  test('planlayıcı kurulumu patlarsa açılış YİNE de tamamlanır', () async {
    final failing = ProviderContainer(
      overrides: [
        followUpSchedulerProvider.overrideWithValue(_ExplodingScheduler()),
      ],
    );
    addTearDown(failing.dispose);

    // Fırlatmamalı: takip sistemi çökse bile uygulama açılmalı.
    await expectLater(failing.read(journeyBootstrapProvider)(), completes);
    expect(failing.read(pendingCheckInProvider), isNull);
  });
}

class _ExplodingScheduler extends RecordingFollowUpScheduler {
  @override
  Future<void> initialize({
    required void Function(String decisionId) onTap,
  }) async =>
      throw StateError('bildirim altyapısı kurulamadı');
}
