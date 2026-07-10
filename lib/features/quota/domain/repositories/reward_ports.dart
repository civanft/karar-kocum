/// Ödüllü reklam port'ları (PR #7A).
///
/// GÜVENLİK NOTU: İstemci hiçbir koşulda kredi YAZMAZ. Akış:
/// bilet aç (callable) → reklamı SSV seçenekleriyle göster → ödülü
/// AdMob'un sunucusu imzalı callback'le verir → kredi Firestore
/// akışından (watchRemaining) kendiliğinden düşer.
library;

abstract interface class RewardTicketPort {
  /// createRewardTicket callable'ı — reklamdan ÖNCE çağrılır.
  Future<String> createTicket();
}

enum AdOutcome {
  /// Kullanıcı reklamı sonuna kadar izledi (ödülü SSV doğrulayacak).
  completed,

  /// Erken kapattı — "reklam tamamlanmadan kredi yok".
  dismissed,

  /// Reklam yüklenemedi/gösterilemedi.
  failed,
}

abstract interface class RewardedAdPort {
  bool get isAvailable;

  /// [ticketId] SSV custom_data'sına, [ssvUserId] user_id'ye konur.
  Future<AdOutcome> show({
    required String ssvUserId,
    required String ticketId,
  });
}

/// AdMob SDK'sı henüz yapılandırılmadı (AdMob hesabı + uygulama kimlikleri
/// gerekir — kullanıcı kurulumu). Buton bu portta GİZLİ kalır.
class UnavailableRewardedAdPort implements RewardedAdPort {
  const UnavailableRewardedAdPort();

  @override
  bool get isAvailable => false;

  @override
  Future<AdOutcome> show({
    required String ssvUserId,
    required String ticketId,
  }) async =>
      AdOutcome.failed;
}

/// Yerel mod: bilet ucu yok.
class UnavailableRewardTicketPort implements RewardTicketPort {
  const UnavailableRewardTicketPort();

  @override
  Future<String> createTicket() =>
      throw StateError('Ödül bileti bu ortamda kullanılamaz');
}
