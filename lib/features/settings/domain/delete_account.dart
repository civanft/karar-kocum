import 'account_deletion.dart';

/// Hesap silme akışının tek sıralayıcısı (PR-R1).
///
/// SIRA KRİTİK:
///  1. Sunucu kaskadı — başarısızsa AKIŞ BURADA BİTER. Yerel veriyi silmek
///     ya da oturumu kapatmak, sunucudaki veri dururken kullanıcıyı
///     erişemez hâle getirirdi.
///  2. Cihazdaki izler (takip tercihleri + planlı bildirimler).
///  3. Eski oturumu kapat, yeni ve BOŞ misafir oturumu aç.
///
/// 1. adımdan SONRAKİ hatalar kullanıcıya hata olarak gösterilmez: veri
/// gerçekten silinmiştir; "silinemedi" demek yanlış olurdu. 2. adım
/// patlasa bile 3. adım çalışmalı — kullanıcı silinmiş hesapta kalmasın.
class DeleteAccount {
  const DeleteAccount({
    required this.client,
    required this.cleaner,
    required this.session,
  });

  final AccountDeletionClient client;
  final LocalUserDataCleaner cleaner;
  final AccountSession session;

  Future<void> call() async {
    await client.deleteAccount(); // hata → AccountDeletionFailure

    await _ignoringErrors(cleaner.clearAll);
    await _ignoringErrors(session.signOut);
    // Açılamazsa bir sonraki uygulama açılışında bootstrap kurar.
    await _ignoringErrors(session.signInAnonymously);
  }

  static Future<void> _ignoringErrors(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // Bilinçli yutma — gerekçesi sınıf dokümanında.
    }
  }
}
