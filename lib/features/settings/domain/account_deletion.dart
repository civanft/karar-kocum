/// Hesap silme sözleşmeleri (PR-R1) — saf Dart, plugin/Firebase tipi YOK.
library;

/// Hatanın tekrar denemeye değip değmediği. UI yalnız bu ayrımı bilir.
enum AccountDeletionFailureKind {
  /// Geçici: ağ, sunucu meşgul, timeout. Kullanıcı tekrar deneyebilir.
  retryable,

  /// Kalıcı: oturum düşmüş, yetki yok. Tekrar denemek işe yaramaz.
  nonRetryable,
}

/// Kullanıcıya gösterilebilir silme hatası. [message] Türkçe ve
/// ürün-anlamlıdır; upstream/teknik detay ASLA içine konmaz.
class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure({required this.kind, required this.message});

  final AccountDeletionFailureKind kind;
  final String message;

  bool get isRetryable => kind == AccountDeletionFailureKind.retryable;

  @override
  String toString() => 'AccountDeletionFailure($kind): $message';
}

/// Sunucudaki hesap+veri kaskadını tetikleyen port.
abstract interface class AccountDeletionClient {
  /// Başarısızlıkta [AccountDeletionFailure] fırlatır.
  ///
  /// UID PARAMETRE DEĞİLDİR: sunucu kimliği doğrulanmış oturumdan alır,
  /// böylece istemci başka bir kullanıcının verisini hedefleyemez.
  Future<void> deleteAccount();
}

/// Cihazda kalan kullanıcı izlerini temizleyen port.
///
/// Settings domain'i hangi verinin nerede durduğunu BİLMEZ; bağlama
/// data katmanındaki adaptörde yapılır.
abstract interface class LocalUserDataCleaner {
  Future<void> clearAll();
}

/// Oturum yaşam döngüsünün silme akışının ihtiyaç duyduğu dar dilimi.
///
/// AuthRepository'nin tamamı yerine bu dar port kullanılır: silme akışı
/// Google/Apple girişini ya da oturum akışını görmek zorunda değil.
abstract interface class AccountSession {
  Future<void> signOut();

  /// Silme sonrası YENİ ve BOŞ misafir oturumu açar.
  Future<void> signInAnonymously();
}
