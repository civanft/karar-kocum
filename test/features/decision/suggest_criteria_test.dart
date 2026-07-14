import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/domain/usecases/suggest_criteria.dart';

/// CriterionSuggester (SPRINT-A §1.2/§4.1): saf, deterministik, AI'sız.
/// Kaynak önceliği: şablon > başlık anahtar kelimesi > genel dolgu.
void main() {
  final now = DateTime(2026, 7, 14);

  Decision decision({
    String title = 'Karar başlığı',
    List<Criterion> criteria = const [],
  }) =>
      Decision(
        id: 'd1',
        ownerUid: 'u1',
        title: title,
        criteria: criteria,
        createdAt: now,
        updatedAt: now,
      );

  Criterion criterion(String name) =>
      Criterion(id: 'c-$name', name: name, weight: 5);

  const suggester = CriterionSuggester();

  group('kaynak önceliği', () {
    test('şablon kriterleri önce ve origin: template', () {
      final result = suggester.suggest(
        decision: decision(title: 'Hangi telefonu almalıyım?'),
        templateCriteria: const [
          (name: 'Fiyat', weight: 8),
          (name: 'Kamera', weight: 7),
        ],
      );

      expect(result.first.name, 'Fiyat');
      expect(result[1].name, 'Kamera');
      expect(result[0].origin, SuggestionOrigin.template);
      expect(result[1].origin, SuggestionOrigin.template);
      // Şablondan sonra başlık eşleşmeleri gelir (telefon kümesi).
      expect(
        result.skip(2).every((s) => s.origin != SuggestionOrigin.template),
        isTrue,
      );
    });

    test('başlık "iPhone mu Samsung mu?" → telefon kümesi (origin: keyword)',
        () {
      final result =
          suggester.suggest(decision: decision(title: 'iPhone mu Samsung mu?'));

      expect(result, isNotEmpty);
      expect(result.every((s) => s.origin == SuggestionOrigin.keyword), isTrue);
      // Telefon kümesinden beklenen en az bir tanıdık kriter:
      expect(result.map((s) => s.name), contains('Fiyat'));
    });

    test('eşleşme yoksa genel set (origin: generic)', () {
      final result = suggester.suggest(
        decision: decision(title: 'Zorlu bir seçim yapacağım'),
      );

      expect(result, isNotEmpty);
      expect(result.every((s) => s.origin == SuggestionOrigin.generic), isTrue);
    });
  });

  group('eleme kuralları', () {
    test('eklenmiş kriter önerilmez (harf-duyarsız)', () {
      final result = suggester.suggest(
        decision: decision(
          title: 'iPhone mu Samsung mu?',
          criteria: [criterion('fiyat')],
        ),
      );

      expect(result.map((s) => s.name), isNot(contains('Fiyat')));
    });

    test('TR locale: "FİYAT" varken "Fiyat" önerilmez (İ/i vakası)', () {
      final result = suggester.suggest(
        decision: decision(
          title: 'iPhone mu Samsung mu?',
          criteria: [criterion('FİYAT')],
        ),
      );

      expect(result.map((s) => s.name), isNot(contains('Fiyat')));
    });

    test('şablon + başlık kümesi çakışırsa tek kez ve şablon kaynaklı', () {
      final result = suggester.suggest(
        decision: decision(title: 'Hangi telefonu almalıyım?'),
        templateCriteria: const [(name: 'Fiyat', weight: 8)],
      );

      final fiyatlar = result.where((s) => s.name == 'Fiyat').toList();
      expect(fiyatlar, hasLength(1));
      expect(fiyatlar.single.origin, SuggestionOrigin.template);
    });

    test('en fazla 6 öneri döner', () {
      final result = suggester.suggest(
        decision: decision(title: 'Hangi telefonu almalıyım?'),
        templateCriteria: const [
          (name: 'A', weight: 5),
          (name: 'B', weight: 5),
          (name: 'C', weight: 5),
          (name: 'D', weight: 5),
          (name: 'E', weight: 5),
        ],
      );

      expect(result.length, lessThanOrEqualTo(6));
    });
  });

  group('determinizm ve kenarlar', () {
    test('aynı girdi → aynı sıra (deterministik)', () {
      final d = decision(title: 'Hangi iş teklifini kabul etmeliyim?');
      final a = suggester.suggest(decision: d).map((s) => s.name).toList();
      final b = suggester.suggest(decision: d).map((s) => s.name).toList();
      expect(a, b);
    });

    test('tüm öneriler elendiyse boş liste (genel dolgu ZORLANMAZ)', () {
      // Genel setin tamamı zaten ekli → boş dönmeli; motor "ne olursa
      // olsun 6 doldur" davranışına kaçmamalı.
      final generic = suggester.suggest(
        decision: decision(title: 'Bilinmeyen konu'),
      );
      final all = [
        for (final s in generic) criterion(s.name),
      ];
      final result = suggester.suggest(
        decision: decision(title: 'Bilinmeyen konu', criteria: all),
      );
      expect(result, isEmpty);
    });

    test('iş başlığı → kariyer kümesi (ikinci sözlük kontrolü)', () {
      final result = suggester.suggest(
        decision: decision(title: 'Hangi iş teklifini kabul etmeliyim?'),
      );
      expect(result.map((s) => s.name), contains('Maaş'));
      expect(result.every((s) => s.origin == SuggestionOrigin.keyword), isTrue);
    });
  });
}
