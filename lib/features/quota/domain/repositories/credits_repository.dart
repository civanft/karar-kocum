import 'dart:async';

import '../../../../core/constants/limits.dart';

/// Analiz kredisi sözleşmesi (PR #6C-2).
///
/// İstemci krediyi YALNIZ OKUR: düşüm sunucu transaction'ında
/// (analyzeDecision), başlangıç değeri sunucu lazy-init'inde — rules
/// istemci yazımını tamamen engeller. Bu arayüzde yazma metodu
/// bulunmaması bilinçlidir (manipüle edilemezlik, derleme düzeyinde).
abstract interface class CreditsRepository {
  /// Kalan ücretsiz analiz kredisi; abone olunca mevcut değer hemen gelir.
  /// Alan hiç yazılmamışsa (yeni kullanıcı) başlangıç değeri yayımlanır.
  Stream<int> watchRemaining();
}

/// Yerel mod / test deposu: sabit başlangıç kredisi yayımlar.
class LocalCreditsRepository implements CreditsRepository {
  LocalCreditsRepository([this._remaining = Limits.freeAnalysisCredits]);

  final int _remaining;

  @override
  Stream<int> watchRemaining() => Stream.value(_remaining);
}

/// Release'de servise bağlanılamadığında kullanılan kredi deposu
/// (PR-RELEASE-1).
///
/// SAHTE KREDİ YAYINLAMAZ: [LocalCreditsRepository] sabit bir başlangıç
/// değeri (ör. 5) yayımlar; kullanıcı bunu gerçek hakkı sanır ve analiz
/// denediğinde başarısız olur. Burada akış açık bir hata ile başlar.
class UnavailableCreditsRepository implements CreditsRepository {
  const UnavailableCreditsRepository();

  static const String message =
      'Servise bağlanılamadı. Bağlantını kontrol edip tekrar dene.';

  @override
  Stream<int> watchRemaining() =>
      Stream.error(const CreditsUnavailableException());
}

/// Kullanıcıya gösterilebilir, teknik ayrıntı taşımayan hata.
class CreditsUnavailableException implements Exception {
  const CreditsUnavailableException();

  @override
  String toString() => UnavailableCreditsRepository.message;
}
