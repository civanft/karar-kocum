import 'account_deletion.dart';

/// Hesap silme akışının tek sıralayıcısı (PR-R1, sertleştirme PR-R1B).
///
/// SIRA KRİTİK:
///  1. Sunucu kaskadı — başarısızsa AKIŞ BURADA BİTER ve
///     [AccountDeletionFailure] fırlatılır. Yerel veriyi silmek ya da
///     oturumu kapatmak, sunucudaki veri dururken kullanıcıyı erişemez
///     hâle getirirdi.
///  2. Cihazdaki izler (takip tercihleri + planlı bildirimler).
///  3. Eski oturumu kapat, yeni ve BOŞ misafir oturumu aç.
///
/// 1. adımdan SONRAKİ hatalar "silinemedi" DEĞİLDİR: veri gerçekten
/// silinmiştir. Yalnız 3. adımın sonucu [AccountDeletionOutcome] olarak
/// raporlanır; UI buna göre farklı mesaj gösterir.
///
/// 2. adım patlasa bile 3. adım çalışır ve signOut patlasa bile yeni
/// oturum denenir — kullanıcı silinmiş hesapta mahsur kalmasın.
class DeleteAccount {
  const DeleteAccount({
    required this.client,
    required this.cleaner,
    required this.session,
  });

  final AccountDeletionClient client;
  final LocalUserDataCleaner cleaner;
  final AccountSession session;

  Future<AccountDeletionOutcome> call() async {
    await _deleteOnServer(); // hata → AccountDeletionFailure

    await _ignoringErrors(cleaner.clearAll);
    await _ignoringErrors(session.signOut);

    try {
      await session.signInAnonymously();
      return AccountDeletionOutcome.deletedAndReady;
    } catch (_) {
      return AccountDeletionOutcome.deletedNeedsRestart;
    }
  }

  /// Sunucu silmesi + BELİRSİZ SONUÇ doğrulaması (İş Paketi 3).
  ///
  /// Callable sunucuda tamamlanıp cevabı istemciye ulaşmayabilir. O zaman
  /// tek kesin sinyal Auth'un kendisidir: hesap gerçekten yoksa silme
  /// BAŞARILI sayılır ve yerel temizlik çalışır. Hesap duruyorsa ya da
  /// doğrulama da belirsiz kalırsa BAŞARI VARSAYILMAZ — yerel veri
  /// silinmez ve kullanıcıya tekrar denenebilir hata gösterilir.
  Future<void> _deleteOnServer() async {
    try {
      await client.deleteAccount();
    } on AccountDeletionFailure catch (failure) {
      if (!failure.ambiguous) rethrow;
      final check = await _verifyQuietly();
      if (check != AccountExistenceCheck.deleted) rethrow;
      // Doğrulandı: sunucu işi bitirmiş, yalnız cevap kaybolmuş.
    }
  }

  Future<AccountExistenceCheck> _verifyQuietly() async {
    try {
      return await session.verifyAccountDeleted();
    } catch (_) {
      // Doğrulama da patladıysa BAŞARI VARSAYILMAZ.
      return AccountExistenceCheck.unknown;
    }
  }

  static Future<void> _ignoringErrors(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // Bilinçli yutma — gerekçesi sınıf dokümanında.
    }
  }
}
