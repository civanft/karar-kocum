import '../entities/ai_consent.dart';

/// İzin kaydının okunması/yazılması — Firestore tipleri adaptörün arkasında.
abstract interface class AiConsentRepository {
  /// Canlı izin durumu. Kayıt hiç yoksa `null` yayınlar: "hiç sorulmadı"
  /// ile "reddedildi" AYRI durumlardır.
  Stream<AiConsent?> watch();

  /// Güncel sürüm için izin ver. Zaman damgasını SUNUCU yazar.
  Future<void> grant();

  /// İzni geri al. Kayıt SİLİNMEZ — `granted:false` yazılır, böylece
  /// geri alma "hiç sorulmadı" hâline dönmez.
  Future<void> withdraw();
}

/// FAIL-CLOSED varyant: Firebase hazır değilken ya da oturum yokken.
///
/// `null` yayınlar (izin yok) ve yazma denemesi HATA verir — sahte bir
/// "izin verildi" durumu üretmez.
class UnavailableAiConsentRepository implements AiConsentRepository {
  const UnavailableAiConsentRepository();

  @override
  Stream<AiConsent?> watch() => Stream<AiConsent?>.value(null);

  @override
  Future<void> grant() async => throw const AiConsentUnavailable();

  @override
  Future<void> withdraw() async => throw const AiConsentUnavailable();
}

/// İzin yazılamadı — kullanıcıya GÜVENLİ mesajla yansıtılır.
class AiConsentUnavailable implements Exception {
  const AiConsentUnavailable();
}
