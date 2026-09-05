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
  const AccountDeletionFailure({
    required this.kind,
    required this.message,
    this.ambiguous = false,
  });

  final AccountDeletionFailureKind kind;
  final String message;

  /// Sunucunun işi TAMAMLAMIŞ olabileceği, ama cevabın istemciye
  /// ulaşmadığı durum (timeout, bağlantı kopması, 5xx). Yalnız bu
  /// durumda "hesap gerçekten silindi mi?" doğrulaması yapılır.
  ///
  /// `unauthenticated` gibi kesin hatalar ambiguous DEĞİLDİR: çağrı
  /// sunucuya hiç ulaşmamış olabilir ve kör biçimde "silindi" saymak
  /// kullanıcının yerel verisini haksız yere siler.
  final bool ambiguous;

  bool get isRetryable => kind == AccountDeletionFailureKind.retryable;

  @override
  String toString() => 'AccountDeletionFailure($kind): $message';
}

/// Silme BAŞARILI olduktan sonraki oturum durumu.
///
/// İkisi de "hesap silindi" demektir; fark, kullanıcının uygulamayı
/// kullanmaya hemen devam edip edemeyeceğidir. Bu ayrım UI'da mesaj
/// farkına dönüşür — kurulmamış bir oturum "başlattık" diye duyurulmaz.
enum AccountDeletionOutcome {
  /// Yeni ve boş misafir oturumu açıldı; kullanıcı devam edebilir.
  deletedAndReady,

  /// Veri silindi ama yeni oturum açılamadı (ağ vb.). Uygulama yeniden
  /// açıldığında bootstrap oturumu kurar.
  deletedNeedsRestart,
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

/// BELİRSİZ SONUÇ doğrulamasının cevabı (İş Paketi 3).
///
/// Callable sunucuda TAMAMLANIP istemciye cevap ulaşmayabilir (timeout,
/// bağlantı kopması). O durumda "silindi mi?" sorusunun tek güvenilir
/// cevabı Auth'un kendisidir.
enum AccountExistenceCheck {
  /// Auth açıkça "böyle kullanıcı yok" dedi → sunucu silmesi TAMAMLANDI.
  deleted,

  /// Kullanıcı hâlâ duruyor → silme tamamlanmadı, tekrar denenmeli.
  stillPresent,

  /// Doğrulama da başarısız (ağ vb.) → BAŞARI VARSAYILMAZ.
  unknown,
}

/// Oturum yaşam döngüsünün silme akışının ihtiyaç duyduğu dar dilimi.
///
/// AuthRepository'nin tamamı yerine bu dar port kullanılır: silme akışı
/// Google/Apple girişini ya da oturum akışını görmek zorunda değil.
abstract interface class AccountSession {
  Future<void> signOut();

  /// Silme sonrası YENİ ve BOŞ misafir oturumu açar.
  Future<void> signInAnonymously();

  /// Mevcut kullanıcıyı sunucudan TAZELEYEREK hesabın hâlâ var olup
  /// olmadığını sorar. Belirsiz kalırsa [AccountExistenceCheck.unknown].
  Future<AccountExistenceCheck> verifyAccountDeleted();
}
