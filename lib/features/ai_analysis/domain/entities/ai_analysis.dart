/// AI analiz okuma modeli — AI-MVP-MIMARI şeması (6B):
/// {summary, strengths, weaknesses, risks, recommendation, confidence}
/// Saf Dart; Firestore eşlemesi 6D-2'de data katmanına gelir.
enum AnalysisConfidence { low, medium, high }

class AiAnalysis {
  const AiAnalysis({
    required this.summary,
    required this.strengths,
    required this.weaknesses,
    required this.risks,
    required this.recommendation,
    required this.confidence,
    this.generatedAt,
  });

  final String summary;
  final List<String> strengths;
  final List<String> weaknesses;
  final List<String> risks;
  final String recommendation;
  final AnalysisConfidence confidence;
  final DateTime? generatedAt;

  /// analyzeDecision callable yanıtındaki `analysis` alanından üretir
  /// (AI-MVP-MIMARI §4 düz şeması). Eksik/bozuk alanlar güvenli
  /// varsayılana düşer — kısmi yanıt UI'ı çökertmesin.
  factory AiAnalysis.fromMap(Map<Object?, Object?> map) {
    List<String> strList(Object? v) =>
        v is List ? v.whereType<Object?>().map((e) => '$e').toList() : const [];
    return AiAnalysis(
      summary: (map['summary'] as String?) ?? '',
      strengths: strList(map['strengths']),
      weaknesses: strList(map['weaknesses']),
      risks: strList(map['risks']),
      recommendation: (map['recommendation'] as String?) ?? '',
      confidence: switch (map['confidence']) {
        'high' => AnalysisConfidence.high,
        'low' => AnalysisConfidence.low,
        _ => AnalysisConfidence.medium,
      },
    );
  }

  /// 6D-1 mock verisi — gerçekçi içerik, UI durum tasarımı için.
  factory AiAnalysis.mock() => AiAnalysis(
        summary: 'Kriterlerine göre iki seçenek arasında anlamlı bir fark var. '
            'Maaş ve iş bulma kolaylığına verdiğin yüksek ağırlık, büyük '
            'şehir seçeneğini öne çıkarıyor; yaşam maliyeti ise en güçlü '
            'karşı argüman olarak duruyor.',
        strengths: [
          'Kriter ağırlıkların net ve tutarlı — sonuç güvenilir',
          'Öne çıkan seçenek, en önemli 2 kriterinde açık ara önde',
          'Artı/eksi listelerin dengeli; tek taraflı bakmamışsın',
        ],
        weaknesses: [
          'Yaşam maliyeti kriterini görece düşük tartmışsın',
          'İkinci seçeneğin uzun vadeli avantajları listende az yer buluyor',
        ],
        risks: [
          'Kira artışları bütçe varsayımını 6 ayda geçersiz kılabilir',
          'Sosyal çevre değişiminin etkisini kriterlere hiç koymamışsın',
        ],
        recommendation:
            'Veriler İstanbul seçeneğini gösteriyor: en yüksek ağırlıklı '
            'iki kriterinde belirgin fark var. Karar öncesi yaşam maliyeti '
            'ağırlığını bir kez daha gözden geçirmen sonucu netleştirir.',
        confidence: AnalysisConfidence.medium,
        generatedAt: DateTime(2026, 7, 9, 14, 30),
      );
}

/// Kalıcı analiz belgesinin KATI eşlemesi (İş Paketi 4 / Dilim A).
///
/// [AiAnalysis.fromMap] callable YANITI içindir ve eksik alanları güvenli
/// varsayılana düşürür — kısmi yanıt UI'ı çökertmesin diye. Kalıcı belge
/// için bu davranış YANLIŞTIR: bozuk bir belge sessizce "boş ama başarılı"
/// bir analiz gibi görünür ve kullanıcı ödediği sonucu kaybettiğini
/// anlamazdı. Bu yüzden okuma katmanı zorunlu alanları DOĞRULAR ve
/// eksik/yanlış tipli belgeyi reddeder.
class AiAnalysisMapper {
  const AiAnalysisMapper._();

  static AiAnalysis fromStored(Map<String, Object?>? data) {
    if (data == null) throw const StoredAnalysisFormatException();

    final summary = data['summary'];
    final recommendation = data['recommendation'];
    if (summary is! String || summary.trim().isEmpty) {
      throw const StoredAnalysisFormatException();
    }
    if (recommendation is! String || recommendation.trim().isEmpty) {
      throw const StoredAnalysisFormatException();
    }

    List<String> requireStringList(Object? value) {
      if (value is! List) throw const StoredAnalysisFormatException();
      for (final item in value) {
        if (item is! String) throw const StoredAnalysisFormatException();
      }
      return value.cast<String>();
    }

    final confidence = switch (data['confidence']) {
      'high' => AnalysisConfidence.high,
      'medium' => AnalysisConfidence.medium,
      'low' => AnalysisConfidence.low,
      _ => throw const StoredAnalysisFormatException(),
    };

    return AiAnalysis(
      summary: summary,
      strengths: requireStringList(data['strengths']),
      weaknesses: requireStringList(data['weaknesses']),
      risks: requireStringList(data['risks']),
      recommendation: recommendation,
      confidence: confidence,
      generatedAt: _readTimestamp(data['generatedAt']),
    );
  }

  /// Firestore `Timestamp` tipini domain'e sızdırmadan okur. Tanınmayan tip
  /// belgeyi geçersiz KILMAZ: `generatedAt` zorunlu bir alan değildir.
  static DateTime? _readTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      // Firestore `Timestamp` tipini domain'e IMPORT ETMEDEN okur.
      // ignore: avoid_dynamic_calls
      final result = (value as dynamic).toDate();
      return result is DateTime ? result : null;
    } catch (_) {
      return null;
    }
  }
}

/// Kalıcı analiz belgesi okunabilir bir analize dönüştürülemedi.
class StoredAnalysisFormatException implements Exception {
  const StoredAnalysisFormatException();
}
