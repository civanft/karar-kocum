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
