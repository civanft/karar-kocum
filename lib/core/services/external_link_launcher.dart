import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/legal_links.dart';

/// Dış bağlantı açma portu (PR-LEGAL-1).
///
/// Arayüz saf tutulur ki ekran testleri gerçek platform kanalına
/// dokunmadan davranışı doğrulayabilsin.
abstract interface class ExternalLinkLauncher {
  /// Başarılıysa `true`. Fırlatmaz: çağıran taraf sonsuz beklemeye ya da
  /// yakalanmamış hataya düşmez.
  Future<bool> open(String url);
}

/// Platform çağrısını yapan imza — testte sahtelenebilir.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// Allowlist'i KENDİ İÇİNDE uygulayan adapter.
///
/// Denetim burada durur: çağıran taraf yanlış bir adres geçse bile platform
/// kanalına hiçbir şey gitmez (open redirect ve kimlik avı koruması).
class AllowlistedLinkLauncher implements ExternalLinkLauncher {
  AllowlistedLinkLauncher({UrlOpener? openUrl})
      : _openUrl = openUrl ?? _defaultOpener;

  final UrlOpener _openUrl;

  static Future<bool> _defaultOpener(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<bool> open(String url) async {
    if (!LegalLinks.isAllowed(url)) return false;
    try {
      return await _openUrl(Uri.parse(url));
    } catch (_) {
      // Kanal yoksa / tarayıcı bulunamazsa çökme değil, sessiz başarısızlık:
      // çağıran katman kullanıcıya Türkçe hata gösterir.
      return false;
    }
  }
}

/// Testlerde override edilebilir bağlama noktası.
final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>(
  (_) => AllowlistedLinkLauncher(),
);
