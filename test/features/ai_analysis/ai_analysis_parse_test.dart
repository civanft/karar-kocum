import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';

/// analyzeDecision callable yanıtının parse'ı (AiAnalysis.fromMap).
void main() {
  test('tam yanıt tüm alanları eşler', () {
    final analysis = AiAnalysis.fromMap({
      'summary': 'Dengeli değerlendirme.',
      'strengths': ['güçlü 1', 'güçlü 2'],
      'weaknesses': ['zayıf 1'],
      'risks': ['risk 1'],
      'recommendation': 'Veriler A gösteriyor.',
      'confidence': 'high',
      'model': 'gemini-2.0-flash',
    });

    expect(analysis.summary, 'Dengeli değerlendirme.');
    expect(analysis.strengths, ['güçlü 1', 'güçlü 2']);
    expect(analysis.weaknesses, ['zayıf 1']);
    expect(analysis.risks, ['risk 1']);
    expect(analysis.recommendation, 'Veriler A gösteriyor.');
    expect(analysis.confidence, AnalysisConfidence.high);
  });

  test('confidence eşlemesi: low/medium/high + bilinmeyen → medium', () {
    expect(
      AiAnalysis.fromMap({'confidence': 'low'}).confidence,
      AnalysisConfidence.low,
    );
    expect(
      AiAnalysis.fromMap({'confidence': 'medium'}).confidence,
      AnalysisConfidence.medium,
    );
    expect(
      AiAnalysis.fromMap({'confidence': 'saçma'}).confidence,
      AnalysisConfidence.medium,
    );
  });

  test('eksik/bozuk alanlar güvenli varsayılana düşer (UI çökmez)', () {
    final analysis = AiAnalysis.fromMap({'summary': 'yalnız özet'});
    expect(analysis.summary, 'yalnız özet');
    expect(analysis.strengths, isEmpty);
    expect(analysis.weaknesses, isEmpty);
    expect(analysis.risks, isEmpty);
    expect(analysis.recommendation, '');
    expect(analysis.confidence, AnalysisConfidence.medium);
  });

  test('liste olmayan alanlar boş listeye düşer', () {
    final analysis = AiAnalysis.fromMap({
      'strengths': 'liste değil',
      'risks': 42,
    });
    expect(analysis.strengths, isEmpty);
    expect(analysis.risks, isEmpty);
  });
}
