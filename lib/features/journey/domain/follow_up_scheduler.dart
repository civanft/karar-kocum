/// Decision Journey — takip bildirimi planlayıcı portu (Sprint C.1).
///
/// Saf domain sözleşmesi: hiçbir plugin/Firebase tipine bağlı DEĞİLDİR.
/// Gerçek uygulama yerel bildirim eklentisini kullanır, testler kayıt
/// tutan bir sahte uygulama kullanır.
abstract interface class FollowUpScheduler {
  /// Uygulama açılışında BİR KEZ çağrılır (Sprint C.2). Bildirime
  /// dokunulduğunda [onTap] ilgili karar kimliğiyle tetiklenir.
  /// Soğuk açılış (uygulama bildirimle açıldı) da bu yoldan gelir.
  Future<void> initialize({
    required void Function(String decisionId) onTap,
  });

  /// [decisionId] için [at] anına bir takip bildirimi planlar.
  /// Aynı karar için önceki plan varsa ÜZERİNE YAZAR (idempotent).
  Future<void> schedule({
    required String decisionId,
    required String decisionTitle,
    required DateTime at,
  });

  /// Bu karara ait planlı bildirimi iptal eder. Plan yoksa sessizce geçer.
  Future<void> cancel(String decisionId);

  /// Bu uygulamanın planladığı TÜM bildirimleri iptal eder (PR-R1 hesap
  /// silme). Silinen hesabın kararları için bildirim düşmemeli.
  Future<void> cancelAll();
}
