import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/constants/limits.dart';
import 'package:karar_veriyorum/features/templates/data/static_template_catalog.dart';

/// Katalog DEĞİŞMEZLERİ (SPRINT-A-TASARIM §4.1): içerik değişse de
/// kırılmaması gereken sözleşmeler. Yeni şablon eklerken bu testler
/// içeriğin Limits ile uyumunu otomatik korur.
void main() {
  const catalog = StaticTemplateCatalog();

  test('katalog boş değil ve en az 4 şablon içerir (boş-durum ızgarası)', () {
    expect(catalog.all().length, greaterThanOrEqualTo(4));
  });

  test('her şablonun id\'si benzersiz', () {
    final ids = catalog.all().map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('kriter sayısı 1-6 arası (tasarım kararı: aşırı yükleme yok)', () {
    for (final t in catalog.all()) {
      expect(
        t.criteria.length,
        inInclusiveRange(1, 6),
        reason: 'şablon: ${t.id}',
      );
    }
  });

  test('her kriter ağırlığı Limits aralığında', () {
    for (final t in catalog.all()) {
      for (final c in t.criteria) {
        expect(
          c.weight,
          inInclusiveRange(
            Limits.criterionWeightMin,
            Limits.criterionWeightMax,
          ),
          reason: '${t.id} → ${c.name}',
        );
      }
    }
  });

  test('şablon başlıkları geçerli karar başlığıdır (Limits uyumu)', () {
    for (final t in catalog.all()) {
      expect(
        t.title.trim().length,
        inInclusiveRange(Limits.titleMinLength, Limits.titleMaxLength),
        reason: 'şablon: ${t.id}',
      );
    }
  });

  test('örnek seçenek sayısı maxOptions sınırının altında', () {
    for (final t in catalog.all()) {
      expect(
        t.sampleOptions.length,
        lessThanOrEqualTo(Limits.maxOptions),
        reason: 'şablon: ${t.id}',
      );
    }
  });

  test('kriter adları şablon içinde benzersiz (çift chip/karışıklık önlenir)',
      () {
    for (final t in catalog.all()) {
      final names = t.criteria.map((c) => c.name.toLowerCase()).toList();
      expect(names.toSet().length, names.length, reason: 'şablon: ${t.id}');
    }
  });

  test('byId: bilinen id şablonu, bilinmeyen id null döner', () {
    final first = catalog.all().first;
    expect(catalog.byId(first.id), same(first));
    expect(catalog.byId('yok-boyle-sablon'), isNull);
  });
}
