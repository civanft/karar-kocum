import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/validators/decision_validator.dart';

void main() {
  final now = DateTime(2026, 7, 8);

  Decision base({
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

  group('title', () {
    test('3-100 karakter geçerli', () {
      expect(DecisionValidator.title('abc'), isNull);
      expect(DecisionValidator.title('a' * 100), isNull);
    });
    test('kısa/uzun/boşluklu reddedilir', () {
      expect(DecisionValidator.title('ab'), isNotNull);
      expect(DecisionValidator.title('  a  '), isNotNull); // trim sonrası 1
      expect(DecisionValidator.title('a' * 101), isNotNull);
    });
  });

  group('prosConsItem', () {
    test('1-140 karakter geçerli, boş ve 141 reddedilir', () {
      expect(DecisionValidator.prosConsItem('iyi kamera'), isNull);
      expect(DecisionValidator.prosConsItem('x' * 140), isNull);
      expect(DecisionValidator.prosConsItem('   '), isNotNull);
      expect(DecisionValidator.prosConsItem('x' * 141), isNotNull);
    });
  });

  group('criterionWeight / cellScore', () {
    test('1-10 geçerli, dışı reddedilir', () {
      for (var v = 1; v <= 10; v++) {
        expect(DecisionValidator.criterionWeight(v), isNull);
        expect(DecisionValidator.cellScore(v), isNull);
      }
      expect(DecisionValidator.criterionWeight(0), isNotNull);
      expect(DecisionValidator.criterionWeight(11), isNotNull);
      expect(DecisionValidator.cellScore(0), isNotNull);
      expect(DecisionValidator.cellScore(11), isNotNull);
    });
  });

  group('readyForResult', () {
    const optA = Option(id: 'a', title: 'A');
    const optB = Option(id: 'b', title: 'B');
    const crit = Criterion(id: 'c1', name: 'Fiyat', weight: 5);

    test('seçenek < 2 → engel', () {
      final failures = DecisionValidator.readyForResult(
        base(options: const [optA], criteria: const [crit]),
      );
      expect(failures.map((f) => f.field), contains('options'));
    });

    test('kriter yok → engel', () {
      final failures = DecisionValidator.readyForResult(
        base(options: const [optA, optB]),
      );
      expect(failures.map((f) => f.field), contains('criteria'));
    });

    test('eksik puan → scores engeli', () {
      final failures = DecisionValidator.readyForResult(
        base(
          options: const [optA, optB],
          criteria: const [crit],
          scores: const {
            'a': {'c1': CellScore(value: 8)},
            // b puansız
          },
        ),
      );
      expect(failures.map((f) => f.field), contains('scores'));
    });

    test('tam matris → hazır (boş liste)', () {
      final failures = DecisionValidator.readyForResult(
        base(
          options: const [optA, optB],
          criteria: const [crit],
          scores: const {
            'a': {'c1': CellScore(value: 8)},
            'b': {'c1': CellScore(value: 4)},
          },
        ),
      );
      expect(failures, isEmpty);
    });
  });

  group('canAddOption', () {
    test('10 seçenekte kapanır', () {
      final ten = [
        for (var i = 0; i < 10; i++) Option(id: 'o$i', title: 'O$i'),
      ];
      expect(DecisionValidator.canAddOption(base(options: ten)), isFalse);
      expect(
        DecisionValidator.canAddOption(
          base(options: ten.sublist(0, 9)),
        ),
        isTrue,
      );
    });
  });
}
