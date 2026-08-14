/// Decision Journey — takip sözü tercihi (Sprint C).
///
/// Kullanıcı taahhüt anında "1 hafta sonra sorayım mı?" sorusuna cevap
/// verir. Bu tercih CİHAZ KAPSAMLIDIR ve Firestore'a YAZILMAZ:
///  - bildirimler yerel planlanır (cihaz başına), senkron anlamsız olur
///  - Firestore yazım maliyeti artmaz (Sprint C kuralı)
///
/// Saf domain sözleşmesi; yerel depolama data katmanında.
abstract interface class FollowUpPreferences {
  /// Bu karar için takip sözü verilmiş mi?
  Future<bool> isOptedIn(String decisionId);

  /// Sözü kaydet/kaldır.
  Future<void> setOptedIn(String decisionId, {required bool value});

  /// Cihazdaki TÜM takip sözlerini siler (PR-R1 hesap silme).
  /// Yalnız bu tercihi hedefler; başka yerel ayarlara dokunmaz.
  Future<void> clearAll();
}
