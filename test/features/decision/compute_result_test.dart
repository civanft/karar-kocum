import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/usecases/compute_result.dart';
import 'package:karar_veriyorum/features/scoring/domain/entities/scoring_types.dart'
    show IncompleteScoreMatrixException;

void main() {
  const usecase = ComputeResult();
  final now = DateTime(2026, 7, 8);

  Decision decision({required ScoreMatrix scores}) => Decision(
        id: 'd1',
        ownerUid: 'u1',
        title: 'Şehir seçimi',
        options: const [
          Option(id: 'ist', title: 'İstanbul'),
          Option(id: 'izm', title: 'İzmir'),
        ],
        criteria: const [
          Criterion(id: 'maas', name: 'Maaş', weight: 8),
          Criterion(id: 'yasam', name: 'Yaşam kalitesi', weight: 4),
        ],
        scores: scores,
        createdAt: now,
        updatedAt: now,
      );

  test('Decision entity\'sini motora köprüler ve doğru sıralama döner', () {
    final result = usecase(
      decision(
        scores: const {
          'ist': {
            'maas': CellScore(value: 9),
            'yasam': CellScore(value: 4),
          },
          'izm': {
            'maas': CellScore(value: 6),
            'yasam': CellScore(value: 9, source: ScoreSource.ai),
          },
        },
      ),
    );

    // Maaş ağırlığı (8) yaşamın (4) iki katı → İstanbul önde olmalı
    expect(result.recommendedOptionId, 'ist');
    expect(result.ranking, hasLength(2));
    expect(
      result.ranking[0].score,
      greaterThan(result.ranking[1].score),
    );
  });

  test('eksik matris motor sözleşmesini korur: exception fırlar', () {
    expect(
      () => usecase(
        decision(
          scores: const {
            'ist': {'maas': CellScore(value: 9)},
          },
        ),
      ),
      throwsA(isA<IncompleteScoreMatrixException>()),
    );
  });

  test('isScoreMatrixComplete: tam matriste true, eksikte false', () {
    final complete = decision(
      scores: const {
        'ist': {
          'maas': CellScore(value: 9),
          'yasam': CellScore(value: 4),
        },
        'izm': {
          'maas': CellScore(value: 6),
          'yasam': CellScore(value: 9),
        },
      },
    );
    expect(complete.isScoreMatrixComplete, isTrue);

    final incomplete = decision(
      scores: const {
        'ist': {'maas': CellScore(value: 9)},
      },
    );
    expect(incomplete.isScoreMatrixComplete, isFalse);
  });

  test('Decision JSON gidiş-dönüşü kayıpsızdır (Firestore hazırlığı)', () {
    final original = decision(
      scores: const {
        'ist': {
          'maas': CellScore(value: 9),
          'yasam': CellScore(value: 4),
        },
        'izm': {
          'maas': CellScore(value: 6),
          'yasam': CellScore(value: 9, source: ScoreSource.ai),
        },
      },
    );

    final restored = Decision.fromJson(original.toJson());
    expect(restored, original);
    expect(
      restored.scores['izm']!['yasam']!.source,
      ScoreSource.ai,
    );
  });
}
