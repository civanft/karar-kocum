/// AI işleme izni — SÜRÜMLÜ sözleşme (İş Paketi 5).
///
/// Analytics izninden ve genel kullanım koşullarından AYRIDIR: burada
/// izin verilen şey, karar içeriğinin analiz için üçüncü taraf bir
/// sağlayıcıya (OpenAI) sunucu üzerinden AKTARILMASIDIR.
library;

/// Geçerli izin metni sürümü.
///
/// `functions/src/privacy/ai_consent.ts` içindeki `AI_CONSENT_VERSION` ile
/// SENKRON olmalıdır; tutarlılık `test/release/privacy_consistency_test.dart`
/// ile kilitlidir.
///
/// YÜKSELTME KURALI: disclosure metni ya da gizlilik politikasının AI
/// aktarım bölümü MADDİ olarak değişirse artır — eski onaylar o değişikliği
/// kapsamaz ve yeniden izin istenir. Yazım düzeltmesi sürümü yükseltmez.
const int currentAiConsentVersion = 1;

class AiConsent {
  const AiConsent({
    required this.granted,
    required this.version,
    this.updatedAt,
  });

  final bool granted;
  final int version;

  /// SUNUCU zaman damgası. İstemci saatine güvenilmez; Firestore rules
  /// `request.time` zorunlu kılar.
  final DateTime? updatedAt;

  /// Bugünkü aktarım için yeterli mi?
  ///
  /// Eski sürüm onayı YETMEZ. Daha yeni sürüm (istemci güncel değil)
  /// kabul edilir — kullanıcı zaten daha geniş bir metni onaylamıştır.
  bool get isSatisfied => granted && version >= currentAiConsentVersion;

  @override
  bool operator ==(Object other) =>
      other is AiConsent &&
      other.granted == granted &&
      other.version == version &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(granted, version, updatedAt);
}
