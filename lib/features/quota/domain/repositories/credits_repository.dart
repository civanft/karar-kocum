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
