import '../domain/entities/decision_template.dart';
import '../domain/repositories/template_catalog.dart';

/// v1 katalog: uygulama içi sabit 6 şablon (SPRINT-A-TASARIM §1.1).
///
/// Neden statik: Firestore şeması değişmez, çevrimdışı ilk açılışta
/// (in-memory repo modunda) da çalışır, içerik uygulama sürümüyle taşınır.
/// İçerik değişmezleri static_template_catalog_test.dart ile korunur
/// (id benzersiz, kriter 1-6, ağırlık/başlık Limits içinde).
class StaticTemplateCatalog implements TemplateCatalog {
  const StaticTemplateCatalog();

  static const _templates = <DecisionTemplate>[
    DecisionTemplate(
      id: 'phone-purchase',
      emoji: '📱',
      title: 'Hangi telefonu almalıyım?',
      description: 'Fiyat, kamera ve pil dengesine göre telefon karşılaştır.',
      category: TemplateCategory.shopping,
      criteria: [
        TemplateCriterion('Fiyat', 8),
        TemplateCriterion('Kamera', 7),
        TemplateCriterion('Pil ömrü', 7),
        TemplateCriterion('Ekosistem uyumu', 5),
        TemplateCriterion('Dayanıklılık', 5),
      ],
      sampleOptions: ['iPhone', 'Samsung'],
    ),
    DecisionTemplate(
      id: 'job-offer',
      emoji: '💼',
      title: 'Hangi iş teklifini kabul etmeliyim?',
      description: 'Teklifleri maaştan fazlasıyla, dengeli kriterlerle tart.',
      category: TemplateCategory.career,
      criteria: [
        TemplateCriterion('Maaş ve yan haklar', 8),
        TemplateCriterion('Kariyer gelişimi', 7),
        TemplateCriterion('İş-yaşam dengesi', 7),
        TemplateCriterion('Şirket kültürü', 6),
        TemplateCriterion('Konum / uzaktan çalışma', 5),
      ],
    ),
    DecisionTemplate(
      id: 'study-major',
      emoji: '🎓',
      title: 'Hangi bölümü seçmeliyim?',
      description: 'Bölümleri gelecek, ilgi ve koşullara göre karşılaştır.',
      category: TemplateCategory.education,
      criteria: [
        TemplateCriterion('İlgi ve yetenek uyumu', 8),
        TemplateCriterion('Kariyer olanakları', 7),
        TemplateCriterion('Eğitim kalitesi', 6),
        TemplateCriterion('Şehir / kampüs yaşamı', 5),
        TemplateCriterion('Maliyet', 6),
      ],
    ),
    DecisionTemplate(
      id: 'city-move',
      emoji: '🏙️',
      title: 'Hangi şehirde yaşamalıyım?',
      description: 'Taşınma kararını iş, maliyet ve yaşam kalitesiyle değerlendir.',
      category: TemplateCategory.lifestyle,
      criteria: [
        TemplateCriterion('Yaşam maliyeti', 8),
        TemplateCriterion('İş fırsatları', 7),
        TemplateCriterion('Sosyal çevre ve aile', 7),
        TemplateCriterion('Yaşam kalitesi', 6),
        TemplateCriterion('Ulaşım', 4),
      ],
    ),
    DecisionTemplate(
      id: 'car-purchase',
      emoji: '🚗',
      title: 'Hangi arabayı almalıyım?',
      description: 'Araçları bütçe ve kullanım ihtiyacına göre puanla.',
      category: TemplateCategory.shopping,
      criteria: [
        TemplateCriterion('Fiyat', 8),
        TemplateCriterion('Yakıt / şarj ekonomisi', 7),
        TemplateCriterion('Güvenlik', 7),
        TemplateCriterion('Konfor', 5),
        TemplateCriterion('İkinci el değeri', 5),
      ],
    ),
    DecisionTemplate(
      id: 'vacation-plan',
      emoji: '✈️',
      title: 'Tatilde nereye gitmeliyim?',
      description: 'Tatil seçeneklerini bütçe ve deneyime göre karşılaştır.',
      category: TemplateCategory.lifestyle,
      criteria: [
        TemplateCriterion('Bütçe', 8),
        TemplateCriterion('Deneyim çeşitliliği', 7),
        TemplateCriterion('Dinlenme faktörü', 6),
        TemplateCriterion('Ulaşım kolaylığı', 5),
        TemplateCriterion('Mevsim uygunluğu', 5),
      ],
    ),
  ];

  @override
  List<DecisionTemplate> all() => _templates;

  @override
  DecisionTemplate? byId(String id) {
    for (final template in _templates) {
      if (template.id == id) return template;
    }
    return null;
  }
}
