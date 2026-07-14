import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';

/// PR-A3 türetilmiş getter'lar (SPRINT-A §4.1): totalScoreCells /
/// filledScoreCells / filledScoreCellsFor / scoringCompletionPercent /
/// isScoringComplete. JSON'a girmez — Firestore şeması değişmez.
void main() {
  final now = DateTime(2026, 7, 14);

  Option option(String id) => Option(id: id, title: 'Seçenek $id');
  Criterion criterion(String id) => Criterion(id: id, name: 'K$id', weight: 5);

  Decision decision({
    List<Option> options = const [],
    List<Criterion> criteria = const [],
    ScoreMatrix scores = const {},
  }) =>
      Decision(
        id: 'd1',
        ownerUid: 'u1',
        title: 'Test kararı',
        options: options,
        criteria: criteria,
        scores: scores,
        createdAt: now,
        updatedAt: now,
      );

  group('totalScoreCells', () {
    test('seçenek × kriter', () {
      final d = decision(
        options: [option('a'), option('b'), option('c')],
        criteria: [criterion('x'), criterion('y')],
      );
      expect(d.totalScoreCells, 6);
    });

    test('boş karar → 0', () {
      expect(decision().totalScoreCells, 0);
    });
  });

  group('filledScoreCells', () {
    test('boş matris → 0', () {
      final d = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x')],
      );
      expect(d.filledScoreCells, 0);
    });

    test('kısmi matris doğru sayar', () {
      final d = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x'), criterion('y')],
        scores: {
          'a': {'x': const CellScore(value: 7)},
          'b': {'y': const CellScore(value: 3)},
        },
      );
      expect(d.filledScoreCells, 2);
    });

    test('silinmiş seçeneğin/kriterin hayalet puanı SAYILMAZ', () {
      // scores'ta var ama options/criteria'da olmayan anahtar (silme
      // artığı senaryosu) toplamı şişirmemeli.
      final d = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x')],
        scores: {
          'a': {'x': const CellScore(value: 7)},
          'silinmis-secenek': {'x': const CellScore(value: 9)},
          'b': {'silinmis-kriter': const CellScore(value: 4)},
        },
      );
      expect(d.filledScoreCells, 1);
    });

    test('tam matris: filled == total ∧ isScoreMatrixComplete uyumu', () {
      final d = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x')],
        scores: {
          'a': {'x': const CellScore(value: 7)},
          'b': {'x': const CellScore(value: 3)},
        },
      );
      expect(d.filledScoreCells, d.totalScoreCells);
      expect(d.isScoreMatrixComplete, isTrue);
      expect(d.isScoringComplete, isTrue);
    });
  });

  group('filledScoreCellsFor (seçenek rozeti)', () {
    test('seçenek bazlı sayım', () {
      final d = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x'), criterion('y')],
        scores: {
          'a': {
            'x': const CellScore(value: 7),
            'y': const CellScore(value: 5),
          },
          'b': {'x': const CellScore(value: 3)},
        },
      );
      expect(d.filledScoreCellsFor('a'), 2);
      expect(d.filledScoreCellsFor('b'), 1);
      expect(d.filledScoreCellsFor('yok'), 0);
    });
  });

  group('scoringCompletionPercent', () {
    test('boş → 0.0, kısmi → oran, tam → 1.0', () {
      final base = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x'), criterion('y')],
      );
      expect(base.scoringCompletionPercent, 0.0);

      final half = decision(
        options: [option('a'), option('b')],
        criteria: [criterion('x'), criterion('y')],
        scores: {
          'a': {
            'x': const CellScore(value: 7),
            'y': const CellScore(value: 5),
          },
        },
      );
      expect(half.scoringCompletionPercent, 0.5);
    });

    test('total 0 iken sıfıra bölme YOK → 0.0', () {
      expect(decision().scoringCompletionPercent, 0.0);
    });
  });

  group('isScoringComplete', () {
    test('boş kararda false (total 0 "tamam" DEĞİLDİR)', () {
      expect(decision().isScoringComplete, isFalse);
    });

    test(
        'tek seçenekte bile matris dolunca true (UI tanımı) — '
        'isScoreMatrixComplete ise false kalır (sonuç kapısı tanımı)', () {
      final d = decision(
        options: [option('a')],
        criteria: [criterion('x')],
        scores: {
          'a': {'x': const CellScore(value: 7)},
        },
      );
      expect(d.isScoringComplete, isTrue); // ilerleme UI'ı: hücreler bitti
      expect(d.isScoreMatrixComplete, isFalse); // kapı: min 2 seçenek şartı
    });
  });
}
