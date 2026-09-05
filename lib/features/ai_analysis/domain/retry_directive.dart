/// Bir analiz hatasından sonra idempotency anahtarının ne olacağını söyleyen
/// AÇIK yönerge (İş Paketi 2B).
///
/// Neden boolean `retryable` yetmedi: "tekrar denenebilir" ile "AYNI
/// requestId ile tekrar denenebilir" farklı şeylerdir. Sunucudaki journal
/// bir isteği kalıcı olarak tükettiğinde (`uncertain`, `terminal_failed`),
/// aynı anahtarla yapılan her deneme aynı hatayı döndürür. Bunu "retryable"
/// işaretlemek kullanıcıyı bitmeyen bir döngüye sokar.
library;

enum RetryDirective {
  /// İş sunucuda hiç başlamadı ya da tamamlanmayı bekliyor: AYNI requestId
  /// ile tekrar denemek güvenlidir ve eksik kalanı TAMAMLAR.
  sameRequest,

  /// Bu requestId tükendi. Kullanıcı isterse YENİ bir analiz başlatır;
  /// eski anahtar bir daha gönderilmez.
  newRequest,

  /// Tekrar denemek sonucu değiştirmez.
  none,
}

/// Sunucunun `details.retry` alanı ("same" | "new" | "none").
RetryDirective? _fromServer(String? value) => switch (value) {
      'same' => RetryDirective.sameRequest,
      'new' => RetryDirective.newRequest,
      'none' => RetryDirective.none,
      // Tanınmayan değer YOK SAYILIR: eski/yeni sürüm karışımında istemci
      // kod tablosuna güvenle düşer.
      _ => null,
    };

/// Backend hata kodu → yönerge.
///
/// [serverDirective] verilmişse o kazanır: sunucu journal durumunu bilir,
/// istemci yalnız hata kodunu görür. Kod tablosu, sunucu yönerge
/// göndermediğinde (eski revizyon, taşıma hatası) kullanılan güvenli
/// varsayılandır.
RetryDirective retryDirectiveFor(
  String? appCode, {
  String? serverDirective,
}) {
  final explicit = _fromServer(serverDirective);
  if (explicit != null) return explicit;

  return switch (appCode) {
    // İş journal'a ULAŞMADAN reddedildi → anahtar hâlâ temiz.
    'app-check-replay' => RetryDirective.sameRequest,
    'unauthenticated' => RetryDirective.sameRequest,
    // Finalization bekliyor olabilir → aynı anahtar tamamlar.
    'internal' => RetryDirective.sameRequest,

    // Kabul kontrolü reddetti: hiçbir sayaç tüketilmedi, ama sözleşme
    // yalınlığı için yeni anahtarla devam edilir.
    'rate-limited' => RetryDirective.newRequest,
    'ai-unavailable' => RetryDirective.newRequest,
    // Bu requestId sunucuda tükendi.
    'ai-uncertain' => RetryDirective.newRequest,
    'ai-failed' => RetryDirective.newRequest,
    'superseded' => RetryDirective.newRequest,

    // Tekrar denemek sonucu değiştirmez.
    'quota-exceeded' => RetryDirective.none,
    'daily-limit' => RetryDirective.none,
    'moderated' => RetryDirective.none,
    'invalid-argument' => RetryDirective.none,

    // Bilinmeyen kod ya da hiç kod yok (ağ hatası): çağrının sunucuya ulaşıp
    // ulaşmadığını bilmiyoruz. GÜVENLİ taraf aynı anahtardır — iş tamamlandıysa
    // saklanan sonuç döner, hiç başlamadıysa baştan çalışır.
    _ => RetryDirective.sameRequest,
  };
}
