/// Mağaza zorunlusu yasal bağlantılar — TEK KAYNAK (PR-LEGAL-1).
///
/// Saf Dart: Flutter ya da plugin bağımlılığı YOKTUR, bu yüzden domain
/// dâhil her katmandan güvenle okunabilir ve testte kurulum gerektirmez.
/// Ekranlar sabit URL dizesi taşımaz; bir adres değişirse tek yer değişir.
library;

abstract final class LegalLinks {
  static const String _base = 'https://karar-kocum-production.web.app';

  /// Gizlilik Politikası — App Store ve Play Console'da zorunlu alan.
  static const String privacy = '$_base/privacy';

  /// Kullanım Koşulları.
  static const String terms = '$_base/terms';

  /// Destek sayfası — iletişim ve hesap silme talimatı.
  static const String support = '$_base/support';

  /// Uygulamanın açmasına izin verilen TEK adres kümesi.
  static const List<String> all = [privacy, terms, support];

  /// Allowlist denetimi: tam eşleşme aranır.
  ///
  /// Ön ek/host karşılaştırması yapılmaz — `.../privacy?next=...` gibi bir
  /// adres host'u doğru olduğu hâlde open redirect taşıyabilir.
  static bool isAllowed(String url) => all.contains(url);
}
