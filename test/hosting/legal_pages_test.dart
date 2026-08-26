import 'dart:convert';
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

    test('destek sayfası "öneri" izlenimi vermez', () {
      final html = _read(_pages['support']!);
      expect(
        html,
        isNot(contains('Sonuçlar bir öneridir')),
        reason: 'diğer belgelerle çelişen tavsiye ifadesi',
      );
      expect(html, contains('bilgilendirme'));
      expect(html, contains('fikir üretme'));
      expect(html, contains('nihai karar'));
    });

    test('hiçbir sayfa profesyonel tavsiye izlenimi vermez', () {
      for (final entry in _pages.entries) {
        final html = _read(entry.value).toLowerCase();
        for (final bad in [
          'tavsiye ederiz',
          'öneririz',
          'size tavsiye',
          'uzman görüşü sunar',
          'danışmanlık sunar',
        ]) {
          expect(
            html.contains(bad),
            isFalse,
            reason: '${entry.key} içinde "$bad" var',
          );
        }
      }
    });

    test('v1 binary ile uyum: Analytics AKTİF SAĞLAYICI olarak yazılmaz', () {
      final html = _read(_pages['privacy']!);
      expect(
        html,
        isNot(contains('Firebase Analytics')),
        reason: 'SDK v1 binary\'de yok; sağlayıcı listesinde durmamalı',
      );
      expect(
        html.contains('izin verirseniz') || html.contains('onayınız varsa'),
        isFalse,
        reason: 'consent ile toplama vaadi kaldı',
      );
    });

    test('reklam ve tracking yapılmadığı açıkça yazılır', () {
      final html = _read(_pages['privacy']!);
      expect(html, contains('reklam'));
      expect(html.toLowerCase(), contains('takip'));
    });

    test('Crashlytics teşhis verisi ve silme kapsamı doğru anlatılır', () {
      final html = _read(_pages['privacy']!);
      expect(html, contains('Crashlytics'));
      expect(
        html.contains('çökme kayıtları hesap silme') ||
            html.contains('teşhis kayıtları'),
        isTrue,
        reason: 'Crashlytics kayıtlarının kaskad dışında olduğu belirtilmeli',
      );
    });

    test('ödeme/abonelik/reklam SDK adı hiçbir sayfada geçmez', () {
      for (final entry in _pages.entries) {
        final html = _read(entry.value).toLowerCase();
        for (final bad in [
          // YALNIZ SDK/ürün adları: "reklam kimliği kullanılmaz" gibi
          // OLUMSUZLAMA cümleleri istenen ifadedir, yasak değil.
          'revenuecat',
          'admob',
          'google sign-in',
        ]) {
          expect(html.contains(bad), isFalse, reason: '${entry.key}: $bad');
        }
      }
    });

    test('OpenAI sunucu tarafı aktarımı KORUNUR', () {
      final html = _read(_pages['privacy']!);
      expect(html, contains('OpenAI'));
      expect(html, contains('Secret Manager'));
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
    // JSON PARSE EDİLİR: ham metin araması, anahtar başka bir blokta ya da
    // yorum içinde geçtiğinde sahte başarı üretir.
    late Map<String, dynamic> config;
    late Map<String, dynamic> hosting;

    setUpAll(() {
      config = jsonDecode(_read('firebase.json')) as Map<String, dynamic>;
      hosting = config['hosting'] as Map<String, dynamic>;
    });

    test('public dizini yalnız legal siteyi işaret eder', () {
      expect(hosting['public'], 'hosting');
    });

    test('clean URL sözleşmesi: /privacy uzantısız çalışır', () {
      // cleanUrls kapanırsa uygulamadaki üç bağlantı 404 verir.
      expect(hosting['cleanUrls'], isTrue);
      expect(hosting['trailingSlash'], isFalse);
    });

    test('güvenlik başlıkları tüm yollara uygulanır', () {
      final headers = (hosting['headers'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((h) => h['source'] == '**');
      final byKey = {
        for (final h
            in (headers['headers'] as List).cast<Map<String, dynamic>>())
          h['key'] as String: h['value'] as String,
      };
      expect(byKey['X-Content-Type-Options'], 'nosniff');
      expect(byKey['X-Frame-Options'], 'DENY');
      expect(byKey['Referrer-Policy'], 'no-referrer');
      expect(byKey['Permissions-Policy'], contains('camera=()'));
      expect(byKey['Permissions-Policy'], contains('geolocation=()'));
      expect(byKey['Content-Security-Policy'], contains("default-src 'none'"));
      const csp = 'Content-Security-Policy';
      expect(byKey[csp], contains("frame-ancestors 'none'"));
    });

    test('HTML UTF-8 olarak sunulur', () {
      final html = (hosting['headers'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((h) => (h['source'] as String).endsWith('.html'));
      final byKey = {
        for (final h in (html['headers'] as List).cast<Map<String, dynamic>>())
          h['key'] as String: h['value'] as String,
      };
      expect(byKey['Content-Type'], contains('charset=utf-8'));
    });

    test('firestore/functions/flutter/emulator yapılandırması korunur', () {
      for (final key in ['firestore', 'functions', 'flutter', 'emulators']) {
        expect(config.containsKey(key), isTrue, reason: '$key düştü');
      }
      final fs = config['firestore'] as Map<String, dynamic>;
      expect(fs['rules'], 'firestore.rules');
      expect(fs['indexes'], 'firestore.indexes.json');
      expect((config['functions'] as Map)['source'], 'functions');
    });
  });
}

String _read(String path) => File(path).readAsStringSync();
