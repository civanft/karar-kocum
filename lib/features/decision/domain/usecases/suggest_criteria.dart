import '../entities/decision.dart';

/// Kriter öneri motoru — SPRINT-A §1.2 (PR-A2).
///
/// SAF ve DETERMİNİSTİK: AI/ağ/Firestore yok; aynı girdi aynı çıktıyı
/// üretir. Kaynak önceliği: şablon kriterleri > başlık anahtar kelime
/// kümesi > genel dolgu. Gelecekteki AI destekli öneri, aynı arayüzün
/// Future tabanlı ikinci sağlayıcısı olur; bu sınıf onun çevrimdışı/
/// anında fallback'i olarak kalır.
enum SuggestionOrigin { template, keyword, generic }

class CriterionSuggestion {
  const CriterionSuggestion({required this.name, required this.origin});

  final String name;
  final SuggestionOrigin origin;
}

class CriterionSuggester {
  const CriterionSuggester();

  static const int _maxSuggestions = 6;

  /// Başlık sözlüğü: anahtar kelime kümesi → kriter listesi.
  /// Sıra ÖNEMLİDİR (ilk eşleşen kazanır) — determinizmin parçası.
  static const _keywordSets = <(List<String>, List<String>)>[
    (
      ['telefon', 'iphone', 'samsung', 'pixel', 'xiaomi'],
      ['Fiyat', 'Kamera', 'Batarya', 'Ekosistem uyumu', 'Dayanıklılık'],
    ),
    (
      ['araba', 'araç', 'otomobil'],
      ['Fiyat', 'Yakıt ekonomisi', 'Güvenlik', 'Konfor', 'İkinci el değeri'],
    ),
    (
      ['iş', 'teklif', 'maaş', 'kariyer', 'şirket', 'pozisyon'],
      [
        'Maaş',
        'Kariyer gelişimi',
        'İş-yaşam dengesi',
        'Şirket kültürü',
        'Uzaktan çalışma',
      ],
    ),
    (
      ['üniversite', 'bölüm', 'okul', 'lisans', 'eğitim'],
      [
        'İlgi uyumu',
        'Kariyer olanakları',
        'Eğitim kalitesi',
        'Maliyet',
        'Şehir yaşamı',
      ],
    ),
    (
      ['şehir', 'taşın', 'ülke', 'yurtdışı', 'semt'],
      [
        'Yaşam maliyeti',
        'İş fırsatları',
        'Sosyal çevre',
        'Yaşam kalitesi',
        'Ulaşım',
      ],
    ),
    (
      ['tatil', 'gezi', 'seyahat', 'otel'],
      ['Bütçe', 'Deneyim', 'Dinlenme', 'Ulaşım kolaylığı', 'Mevsim'],
    ),
  ];

  /// Genel dolgu — hiçbir küme eşleşmezse.
  static const _genericSet = ['Maliyet', 'Kalite', 'Risk', 'Zaman', 'Mutluluk'];

  List<CriterionSuggestion> suggest({
    required Decision decision,
    List<({String name, int weight})> templateCriteria = const [],
  }) {
    final taken = <String>{
      for (final c in decision.criteria) _normalize(c.name),
    };
    final result = <CriterionSuggestion>[];

    void addAll(Iterable<String> names, SuggestionOrigin origin) {
      for (final name in names) {
        if (result.length >= _maxSuggestions) return;
        final key = _normalize(name);
        if (taken.contains(key)) continue;
        taken.add(key); // kaynaklar arası çift öneri imkânsız
        result.add(CriterionSuggestion(name: name, origin: origin));
      }
    }

    // 1) Şablon kriterleri (şablonla başlayıp silen / sonradan gelenler).
    addAll(templateCriteria.map((c) => c.name), SuggestionOrigin.template);

    // 2) Başlık anahtar kelime kümesi — ilk eşleşen küme kazanır.
    final title = _normalize(decision.title);
    for (final (keywords, criteria) in _keywordSets) {
      if (keywords.any(title.contains)) {
        addAll(criteria, SuggestionOrigin.keyword);
        break;
      }
    }

    // 3) Genel dolgu YALNIZ hiç başlık eşleşmesi yoksa (kümeyi sulandırma).
    if (result.every((s) => s.origin == SuggestionOrigin.template) &&
        !_keywordSets.any((set) => set.$1.any(title.contains))) {
      addAll(_genericSet, SuggestionOrigin.generic);
    }

    return result;
  }

  /// TR-locale güvenli normalizasyon: 'İ'→'i', 'I'→'ı' ÖNCE eşlenir
  /// (Dart toLowerCase 'İ'yi noktalı birleşik i'ye çevirir — "FİYAT" ≠
  /// "fiyat" tuzağı), sonra küçük harf + kırp.
  static String _normalize(String value) =>
      value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
}
