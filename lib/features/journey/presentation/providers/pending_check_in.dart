import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'journey_providers.dart';

/// Bildirime dokunulduğunda gidilecek karar (Sprint C.2).
///
/// NEDEN BÖYLE: bildirim callback'i widget ağacının DIŞINDA çalışır —
/// elde BuildContext yoktur. Router'a global anahtar takmak yerine
/// dokunulan karar kimliği buraya düşer; ağaç içindeki bir dinleyici
/// yönlendirmeyi yapar. Soğuk açılış da aynı yoldan gelir, tek yol olur.
class PendingCheckIn extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String decisionId) => state = decisionId;

  /// Yönlendirme yapıldıktan sonra çağrılır — aynı istek iki kez
  /// tetiklenmesin (ör. tema değişiminde yeniden kurulum).
  void consume() => state = null;
}

final pendingCheckInProvider =
    NotifierProvider<PendingCheckIn, String?>(PendingCheckIn.new);

/// Açılışta bildirim altyapısını kurar; dokunuşu [pendingCheckInProvider]'a
/// bağlar. Hata yutulur: takip sistemi çökse bile uygulama açılmalı.
final journeyBootstrapProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(followUpSchedulerProvider).initialize(
            onTap: (decisionId) =>
                ref.read(pendingCheckInProvider.notifier).request(decisionId),
          );
    } catch (_) {
      // Bildirim altyapısı kurulamadı — karar akışı etkilenmez.
    }
  };
});
