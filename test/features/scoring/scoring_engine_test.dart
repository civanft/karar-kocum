import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/scoring/domain/entities/scoring_types.dart';
import 'package:karar_veriyorum/features/scoring/domain/usecases/scoring_engine.dart';

void main() {
  const engine = ScoringEngine();

  const optA = ScoringOption(id: 'a', title: 'Seçenek A');
  const optB = ScoringOption(id: 'b', title: 'Seçenek B');

  const price = ScoringCriterion(id: 'price', name: 'Fiyat', weight: 10);
  const camera = ScoringCriterion(id: 'camera', name: 'Kamera', weight: 5);

  ScoreMatrix matrix(Map<String, Map<String, int>> m) => m;

  group('ScoringEngine.compute', () {
    test('tüm 10 puanlar → 100, tüm 1 puanlar → 0', () {
      final result = engine.compute(
        options: [optA, optB],
        criteria: [price, camera],
        scores: matrix({
          'a': {'price': 10, 'camera': 10},
          'b': {'price': 1, 'camera': 1},
        }),
      );
      expect(result.ranking[0].score, closeTo(100, 0.001));
      expect(result.ranking[1].score, closeTo(0, 0.001));
      expect(result.recommendedOptionId, 'a');
    });

    test('ağırlık normalizasyonu: yüksek ağırlıklı kriter baskın gelir', () {
      // A fiyatta iyi (ağırlık 10), B kamerada iyi (ağırlık 5) → A kazanmalı
      final result = engine.compute(
        options: [optA, optB],
        criteria: [price, camera],
        scores: matrix({
          'a': {'price': 9, 'camera': 3},
          'b': {'price': 3, 'camera': 9},
        }),
      );
      expect(result.recommendedOptionId, 'a');
    });

    test('eşit skorlar deterministik sıralanır ve düşük güven döner', () {
      final result = engine.compute(
        options: [optA, optB],
        criteria: [price],
        scores: matrix({
          'a': {'price': 5},
          'b': {'price': 5},
        }),
      );
      expect(result.ranking[0].score, result.ranking[1].score);
      expect(result.confidence, Confidence.low);
    });

    test('büyük fark + ≥3 kriter → yüksek güven', () {
      const battery =
          ScoringCriterion(id: 'battery', name: 'Batarya', weight: 7);
      final result = engine.compute(
        options: [optA, optB],
        criteria: [price, camera, battery],
        scores: matrix({
          'a': {'price': 9, 'camera': 9, 'battery': 9},
          'b': {'price': 4, 'camera': 4, 'battery': 4},
        }),
      );
      expect(result.confidence, Confidence.high);
    });

    test('eksik hücre → IncompleteScoreMatrixException (partial analiz yok)',
        () {
      expect(
        () => engine.compute(
          options: [optA, optB],
          criteria: [price, camera],
          scores: matrix({
            'a': {'price': 8}, // camera eksik
            'b': {'price': 5, 'camera': 6},
          }),
        ),
        throwsA(isA<IncompleteScoreMatrixException>()),
      );
    });

    test('aralık dışı puan → ArgumentError', () {
      expect(
        () => engine.compute(
          options: [optA, optB],
          criteria: [price],
          scores: matrix({
            'a': {'price': 11},
            'b': {'price': 5},
          }),
        ),
        throwsArgumentError,
      );
    });

    test('tek seçenek → ArgumentError (min 2 kuralı)', () {
      expect(
        () => engine.compute(
          options: [optA],
          criteria: [price],
          scores: matrix({
            'a': {'price': 5},
          }),
        ),
        throwsArgumentError,
      );
    });

    test('kriter yok → ArgumentError', () {
      expect(
        () => engine.compute(
          options: [optA, optB],
          criteria: [],
          scores: matrix({}),
        ),
        throwsArgumentError,
      );
    });
  });
}
