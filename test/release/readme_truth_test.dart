import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// README DOĞRULUK SÖZLEŞMESİ.
///
/// README GitHub'daki vitrindir; eskidiğinde projeyi olduğundan farklı
/// gösterir. Önceki sürüm "Sprint 2" anlatısında kalmıştı: AI'ı bağlanmamış,
/// veriyi bellekte tutulan bir uygulama gibi tarif ediyordu. Bu testler
/// README'nin bilinen canlı gerçeklikten tekrar kopmasını engeller.
///
/// Paragraf birebir eşlenmez; başlık, tablo satırı ve değişmez düzeyinde
/// kontrol edilir.
String _flat(String source) => source
    // Markdown alıntı işaretçisi ("> ") satır ortasına girip eşleşmeyi bozmasın.
    .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  late String readme;
  late String flat;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
    flat = _flat(readme);
  });

  group('eski sprint anlatısı yok', () {
    test('"Sprint N" durumu kalmadı', () {
      expect(
        RegExp(r'Sprint\s*\d', caseSensitive: false).hasMatch(readme),
        isFalse,
        reason: 'eski sprint durumu README\'ye geri dönmüş',
      );
    });

    test('hızla eskiyen sabit test sayısı yazılmamış', () {
      expect(
        RegExp(
          r'\b\d+\s*(/\s*\d+\s*)?(test|tests|testler|testi)\b',
          caseSensitive: false,
        ).hasMatch(readme),
        isFalse,
        reason: 'sabit test sayısı README\'yi eskitir',
      );
    });
  });

  group('yayın durumu dürüst', () {
    test('public mağaza yayını yapılmadığı açıkça yazılı', () {
      expect(
        flat,
        contains("henüz App Store veya Google Play'de public olarak "
            'yayınlanmadı'),
      );
      expect(
        RegExp(r'\|\s*Store submission\s*\|[^\n]*\|\s*Yapılmadı\s*\|')
            .hasMatch(readme),
        isTrue,
        reason: 'store submission satırı "Yapılmadı" olmalı',
      );
    });

    test('mağazada yayında gibi bir iddia veya mağaza bağlantısı yok', () {
      expect(
        RegExp(
          r'(App Store|Google Play)[^.\n]{0,60}'
          r'(yayında|yayınlandı\b|indirilebilir|indir\b)',
          caseSensitive: false,
        ).hasMatch(readme),
        isFalse,
        reason: 'uygulama mağazada yayındaymış gibi sunuluyor',
      );
      expect(
        RegExp(r'apps\.apple\.com|play\.google\.com/store').hasMatch(readme),
        isFalse,
        reason: 'yayınlanmamış uygulamaya mağaza bağlantısı olamaz',
      );
    });
  });

  group('paket durum tablosu', () {
    Map<String, String> statusRows() {
      final rows = <String, String>{};
      for (final m in RegExp(
        r'^\|\s*(Paket [0-9A-Z]+|Store submission)\s*\|'
        r'[^|\n]*\|\s*([^|\n]+?)\s*\|\s*$',
        multiLine: true,
      ).allMatches(readme)) {
        rows[m.group(1)!] = m.group(2)!;
      }
      return rows;
    }

    test('tüm paketler tabloda', () {
      final rows = statusRows();
      for (final pkg in [
        'Paket 1',
        'Paket 2',
        'Paket 3',
        'Paket 4',
        'Paket 5',
        'Paket 6A',
        'Paket 6B',
        'Paket 6C',
        'Paket 6E',
        'Paket 6F',
        'Store submission',
      ]) {
        expect(rows.containsKey(pkg), isTrue, reason: 'eksik satır: $pkg');
      }
    });

    test('6B tamamlandı', () {
      expect(statusRows()['Paket 6B'], 'Tamamlandı');
    });

    test('6C tamamlandı; backup freshness kontrolü canlı', () {
      final row = statusRows()['Paket 6C'] ?? '';
      expect(row, startsWith('Tamamlandı'));
      expect(
        RegExp(r'backup freshness[^.|]{0,60}canlı', caseSensitive: false)
            .hasMatch(row),
        isTrue,
        reason: 'checker canlı iş olarak görünmeli',
      );
      expect(
        RegExp(r'\|\s*Backup freshness kontrolü\s*\|\s*Açık[^|]*30 saat')
            .hasMatch(readme),
        isTrue,
        reason: 'backup tablosunda kadans ve eşik yazmalı',
      );
    });

    test('kontrolün kapsamı ve fail-closed davranışı yazılı', () {
      final flat = _flat(readme);
      expect(flat, contains('saatlik'));
      expect(
        flat,
        contains('yetki hatası "yedek yok" sayılmaz'),
        reason: '403 fail-closed davranışı README\'de görünmeli',
      );
      expect(
        flat,
        contains('hiçbir uygulama verisine erişmez'),
        reason: 'checker veri erişimi sınırı yazılmalı',
      );
      expect(flat, contains('en az yetkili'));
    });

    test('alarmın TETİKLENDİĞİ iddia edilmiyor', () {
      expect(
        RegExp(
          r'(alarm|AL-1[01])[^.|\n]{0,60}(test edildi|tetiklendiği doğrulandı)',
          caseSensitive: false,
        ).hasMatch(readme),
        isFalse,
        reason: 'gözlenmemiş bir tetiklenme iddia edilemez',
      );
      expect(
        _flat(readme),
        contains('alarmın ateşlendiği doğrulanmadı'),
        reason: 'dürüst sınır bilinen sınırlarda yazılmalı',
      );
    });

    test('6E ve 6F bekliyor', () {
      expect(statusRows()['Paket 6E'], 'Bekliyor');
      expect(statusRows()['Paket 6F'], 'Bekliyor');
    });
  });

  group('güvenlik ve gizlilik iddiaları kanıtla uyumlu', () {
    test('App Check production callable\'larda ZATEN enforce ediliyor', () {
      expect(flat, contains('zaten enforce ediyor'));
      expect(
        RegExp(
          r'App Check[^.\n]{0,80}'
          r'(henüz aktif değil|aktif değil|ileride açılacak|henüz açılmadı)',
          caseSensitive: false,
        ).hasMatch(readme),
        isFalse,
        reason: 'App Check enforcement kapalıymış gibi sunuluyor',
      );
      expect(
        RegExp(
          r'provider[^.]{0,120}hâlâ açık bir release kapısı',
          caseSensitive: false,
        ).hasMatch(flat),
        isTrue,
        reason: 'provider/cihaz doğrulamasının açık kapı olduğu yazılmalı',
      );
    });

    test('Analytics SDK yokluğu doğru ve kodla tutarlı', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('firebase_analytics')));
      expect(flat, contains("Analytics SDK'sı yok"));
    });

    test('puan matrisinin AI\'a gönderilmediği yazılı', () {
      expect(flat, contains('puan matrisi'));
      expect(
        RegExp(r'Gönderilmeyen:\*\*[^.]{0,60}puan', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
      );
    });

    test('budget harcamayı durdurmaz; OpenAI maliyeti dahil değil', () {
      expect(flat, contains('harcamayı durdurmaz'));
      expect(
        RegExp(r'harcamayı (durdurur|keser|engeller)\b').hasMatch(flat),
        isFalse,
        reason: 'budget harcamayı durduruyormuş gibi sunuluyor',
      );
      expect(flat, contains("OpenAI maliyeti GCP budget'ına dahil değildir"));
    });
  });

  group('CI ve belge bağlantıları gerçek', () {
    test('CI badge gerçek workflow dosyasını gösteriyor', () {
      final badge = RegExp(
        r'https://github\.com/civanft/karar-kocum/actions/workflows/'
        r'([A-Za-z0-9_.-]+)/badge\.svg',
      ).firstMatch(readme);
      expect(badge, isNotNull, reason: 'CI badge yok');
      final workflow = File('.github/workflows/${badge!.group(1)}');
      expect(
        workflow.existsSync(),
        isTrue,
        reason: 'badge olmayan workflow gösteriyor',
      );
      expect(workflow.readAsStringSync(), contains('name: CI'));
    });

    test('zorunlu belge bağlantıları var ve hedefleri mevcut', () {
      final links = RegExp(r'\]\(([^)#\s]+)\)')
          .allMatches(readme)
          .map((m) => m.group(1)!)
          .where((l) => !l.startsWith('http'))
          .toSet();
      for (final required in [
        'docs/TEKNIK-MIMARI.md',
        'docs/RELEASE-RUNBOOK.md',
        'docs/MONITORING-PANOSU.md',
        'docs/privacy/DATA-FLOW-INVENTORY.md',
        'hosting/privacy/index.html',
        'docs/store/GOOGLE-PLAY-DATA-SAFETY.md',
        'docs/store/APP-STORE-PRIVACY.md',
        'docs/operations/RESTORE-DRILL-2026-09-14.md',
        'docs/operations/BACKUP-CHECKER-ROLLOUT-2026-09-21.md',
      ]) {
        expect(links, contains(required), reason: 'eksik bağlantı: $required');
      }
      for (final link in links) {
        final exists = File(link).existsSync() || Directory(link).existsSync();
        expect(exists, isTrue, reason: 'kırık bağlantı: $link');
      }
    });

    test('Flutter sürümü .flutter-version\'a bağlanıyor, sabit değil', () {
      expect(readme, contains('.flutter-version'));
      final pinned = File('.flutter-version').readAsStringSync().trim();
      expect(
        readme,
        isNot(contains(pinned)),
        reason: 'sürüm README\'ye kopyalanırsa eskir',
      );
    });
  });

  group('public repo veri minimizasyonu', () {
    test('e-posta, UUID, hesap/kaynak kimliği ve tutar YOK', () {
      final forbidden = <String, RegExp>{
        'e-posta': RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
        'UUID': RegExp(
          r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        ),
        'billing account kimliği':
            RegExp(r'\b[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}\b'),
        'proje numarası / uzun sayısal kimlik': RegExp(r'\b\d{9,}\b'),
        'monitoring/budget kaynak adı':
            RegExp(r'(notificationChannels|alertPolicies|budgets)/'),
        'para tutarı': RegExp(r'\d+([.,]\d+)?\s*(TRY|TL|USD|₺|\$)'),
      };
      for (final rule in forbidden.entries) {
        final hit = rule.value.firstMatch(readme);
        expect(hit, isNull, reason: '${rule.key} → "${hit?.group(0)}"');
      }
    });
  });
}
