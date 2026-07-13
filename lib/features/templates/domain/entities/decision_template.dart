/// Hazır karar şablonu — SPRINT-A-TASARIM §1.1 (PR-A1).
///
/// Saf Dart, freezed GEREKMEZ: serileşmez, `const` katalog verisidir.
/// Şablon karara dönüşürken kriter/seçenek id'leri UYGULAMA ANINDA
/// üretilir (CreateDecision) — bu yüzden TemplateCriterion, Criterion'dan
/// bilinçli olarak ayrıdır (id/source taşımaz; çakışma imkânsız olur).
library;

enum TemplateCategory { shopping, career, education, lifestyle }

class TemplateCriterion {
  const TemplateCriterion(this.name, this.weight);

  final String name;
  final int weight; // 1-10, Limits ile katalog testinde doğrulanır
}

class DecisionTemplate {
  const DecisionTemplate({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.category,
    required this.criteria,
    this.sampleOptions = const [],
  });

  /// Katalog kimliği — analytics'e yazılır (içerik/PII değildir).
  final String id;
  final String emoji;

  /// Oluşturulacak kararın ön-dolu başlığı (kullanıcı sheet'te düzenler).
  final String title;
  final String description;
  final TemplateCategory category;
  final List<TemplateCriterion> criteria;

  /// İsteğe bağlı örnek seçenekler — önizlemede gösterilir, karara yazılır.
  final List<String> sampleOptions;
}
