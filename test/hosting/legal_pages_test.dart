import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PR-LEGAL-1 — barındırılan yasal sayfaların statik içerik sözleşmesi.
///
/// Ağ isteği YAPILMAZ; yalnız repodaki dosyalar denetlenir. Amaç, mağaza
/// incelemesini düşüren üç hatayı engellemek: placeholder metin, üçüncü
/// taraf tracker ve yanlış iletişim adresi.
const _support = 'civanyonetim@gmail.com';
const _pages = <String, String>{
  'privacy': 'hosting/privacy/index.html',
  'terms': 'hosting/terms/index.html',
  'support': 'hosting/support/index.html',
};

void main() {
  group('sayfa varlığı', () {
    test('üç yasal sayfa ve ana sayfa mevcut', () {
      for (final path in [..._pages.values, 'hosting/index.html']) {
        expect(File(path).existsSync(), isTrue, reason: '$path yok');
      }
    });
  });

  group('içerik sözleşmesi', () {
    test('placeholder/TODO metni YOK', () {
      for (final entry in _pages.entries) {
        final html = _read(entry.value).toLowerCase();
        for (final bad in [
          'todo',
          'lorem ipsum',
          'placeholder',
          'buraya yaz',
          'xxx',
          '{{',
        ]) {
          expect(
            html.contains(bad),
            isFalse,
            reason: '${entry.key} içinde "$bad" kalmış',
          );
        }
      }
    });

    test('destek e-postası doğru yazılır', () {
      for (final entry in _pages.entries) {
        expect(
          _read(entry.value),
          contains(_support),
          reason: '${entry.key} destek adresini içermiyor',
        );
      }
    });

    test('destek sayfasında erişilebilir mailto bağlantısı var', () {
      expect(_read(_pages['support']!), contains('mailto:$_support'));
    });

    test('uygulama adı ve veri sorumlusu her sayfada', () {
      for (final entry in _pages.entries) {
        final html = _read(entry.value);
        expect(html, contains('Karar Koçum'), reason: entry.key);
        expect(html, contains('Civan FIRAT'), reason: entry.key);
      }
    });

    test('yürürlük tarihi 26 Ağustos 2026', () {
      for (final key in ['privacy', 'terms']) {
        expect(_read(_pages[key]!), contains('26 Ağustos 2026'), reason: key);
      }
    });

    test('gizlilik politikası gerçek mimariyi anlatır', () {
      final html = _read(_pages['privacy']!);
      for (final needed in [
        'App Check',
        'Crashlytics',
        'Cloud Functions',
        'Firestore',
        'OpenAI',
        'Secret Manager',
        'anonim',
      ]) {
        expect(html, contains(needed), reason: '"$needed" anlatılmamış');
      }
      expect(html, contains('satılmaz'));
      expect(html, contains('13'));
    });

    test('kullanım koşulları aktif olmayan özelliği vaat etmez', () {
      final html = _read(_pages['terms']!).toLowerCase();
      for (final bad in ['revenuecat', 'abonelik ücreti', 'reklam izleyerek']) {
        expect(html.contains(bad), isFalse, reason: '"$bad" henüz aktif değil');
      }
    });

    test('koşullar tavsiye/sorumluluk sınırını belirtir', () {
      final html = _read(_pages['terms']!);
      expect(html, contains('13'));
      for (final needed in ['finansal', 'hukuki', 'tıbbi']) {
        expect(html, contains(needed), reason: '"$needed" reddi eksik');
      }
    });
  });

  group('güvenlik ve gizlilik', () {
    test('üçüncü taraf script/CDN/font/tracker YOK', () {
      for (final entry in {..._pages, 'index': 'hosting/index.html'}.entries) {
        final html = _read(entry.value);
        for (final bad in [
          '<script',
          'googletagmanager',
          'google-analytics',
          'gtag(',
          'fonts.googleapis.com',
          'fonts.gstatic.com',
          'cdn.',
          'https://unpkg',
          'onclick=',
          'onload=',
        ]) {
          expect(
            html.contains(bad),
            isFalse,
            reason: '${entry.key} içinde "$bad" var',
          );
        }
      }
    });

    test('harici kaynak yalnız mailto olabilir', () {
      for (final entry in {..._pages, 'index': 'hosting/index.html'}.entries) {
        final external = RegExp(r'''(?:src|href)\s*=\s*["'](https?://[^"']+)''')
            .allMatches(_read(entry.value))
            .map((m) => m.group(1)!)
            .toList();
        expect(external, isEmpty, reason: '${entry.key}: $external');
      }
    });
  });

  group('erişilebilirlik ve mobil uyum', () {
    test('lang, charset, viewport ve title tanımlı', () {
      for (final entry in {..._pages, 'index': 'hosting/index.html'}.entries) {
        final html = _read(entry.value);
        expect(html, contains('lang="tr"'), reason: entry.key);
        expect(html, contains('charset="utf-8"'), reason: entry.key);
        expect(html, contains('name="viewport"'), reason: entry.key);
        expect(html, contains('<title>'), reason: entry.key);
      }
    });

    test('semantik başlık yapısı: tam bir h1', () {
      for (final entry in {..._pages, 'index': 'hosting/index.html'}.entries) {
        expect(
          RegExp('<h1[ >]').allMatches(_read(entry.value)).length,
          1,
          reason: '${entry.key} tek h1 içermeli',
        );
      }
    });

    test('ana sayfa üç belgeye de bağlantı verir', () {
      final html = _read('hosting/index.html');
      for (final slug in ['/privacy', '/terms', '/support']) {
        expect(html, contains(slug), reason: '$slug bağlantısı yok');
      }
    });

    test('her yasal sayfa diğer belgelere dönüş bağlantısı taşır', () {
      expect(_read(_pages['support']!), contains('/privacy'));
      expect(_read(_pages['support']!), contains('/terms'));
    });
  });

  group('firebase.json hosting yapılandırması', () {
    test('hosting bloğu legal siteyi işaret eder ve güvenlik başlıkları var',
        () {
      final raw = _read('firebase.json');
      expect(raw, contains('"hosting"'));
      expect(raw, contains('"public": "hosting"'));
      for (final header in [
        'X-Content-Type-Options',
        'X-Frame-Options',
        'Referrer-Policy',
        'Permissions-Policy',
        'Content-Security-Policy',
      ]) {
        expect(raw, contains(header), reason: '$header eksik');
      }
      expect(raw, contains('nosniff'));
      expect(raw, contains('DENY'));
      expect(raw, contains('no-referrer'));
    });

    test('firestore/functions yapılandırması korunur', () {
      final raw = _read('firebase.json');
      for (final key in ['"firestore"', '"functions"', '"flutter"']) {
        expect(raw, contains(key), reason: '$key düştü');
      }
    });
  });
}

String _read(String path) => File(path).readAsStringSync();
