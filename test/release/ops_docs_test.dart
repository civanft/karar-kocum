import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// İŞ PAKETİ 6A — OPERASYON BELGELERİ SÖZLEŞMESİ.
///
/// Belgeler koddan bağımsız yaşayamaz. Monitoring panosu bir kez
/// "uygulandı" dediği için gerçekte var olmayan bir Analytics boru hattını
/// anlatıyordu; runbook'ta ise App Check sıralaması yanlış yazılırsa canlı
/// deploy tüm istemci çağrılarını kesebilir.
/// Markdown satır sarmasına dayanıklı eşleşme: anlamı kontrol eder,
/// paragrafın birebir biçimini değil.
String _flat(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  late String monitoring;
  late String monitoringBody;
  late String runbook;

  setUpAll(() {
    monitoring = File('docs/MONITORING-PANOSU.md').readAsStringSync();
    // §0 ESKİ iddiaları DÜZELTMEK için alıntılar; yasak-iddia taraması
    // bu bölümü hariç tutmalı, yoksa düzeltmenin kendisi ihlal sayılır.
    monitoringBody = monitoring.substring(
      monitoring.indexOf('## 1. Bugün gerçekten uygulanmış olan'),
    );
    runbook = File('docs/RELEASE-RUNBOOK.md').readAsStringSync();
  });

  group('monitoring panosu gerçekle uyumlu', () {
    test('Analytics SDK\'sı gerçekten YOK (kanıt)', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('firebase_analytics')));
    });

    test('Analytics AKTİF bir araç gibi sunulmuyor', () {
      // "Araçlar: Firebase Analytics + ..." gibi bir künye kalmamalı.
      expect(
        RegExp(r'\*\*Araçlar\*\*[^\n]*Firebase Analytics')
            .hasMatch(monitoringBody),
        isFalse,
      );
      expect(
        monitoringBody.contains('──► Firebase Analytics'),
        isFalse,
        reason: 'var olmayan veri akışı şeması',
      );
    });

    test('kaldırılmış bileşenler "uygulandı" diye sunulmuyor', () {
      expect(
        RegExp(r'uygulandı[^\n]*analytics_service').hasMatch(monitoringBody),
        isFalse,
      );
      expect(
        monitoringBody.contains('analyticsConsentProvider'),
        isFalse,
        reason: 'var olmayan provider gövdede anılmamalı',
      );
    });

    test('analytics "kapalı" değil "uygulanmadı" olarak anlatılıyor', () {
      expect(monitoring, contains('SDK yoktur'));
      expect(monitoring.toLowerCase(), contains('uygulanmam'));
    });

    test('UYGULANMIŞ ve UYGULANMAMIŞ bölümleri AYRI', () {
      final applied = monitoring.indexOf('Bugün gerçekten uygulanmış olan');
      final missing = monitoring.indexOf('Henüz UYGULANMAMIŞ olanlar');
      expect(applied, greaterThan(-1));
      expect(missing, greaterThan(applied));
    });

    test('canlıda alarm/metric/kanal OLMADIĞI yazılı', () {
      for (final needed in [
        'Log-based metric',
        'Alert policy',
        'Notification channel',
        'Incident owner',
      ]) {
        expect(monitoring, contains(needed), reason: needed);
      }
      expect(_flat(monitoring), contains('başlangıç öneri'));
    });

    test('production backend güncel olmadığı UYARISI var', () {
      expect(_flat(monitoring), contains('Production backend güncel değil'));
    });

    test('olay tablosu KODDAKİ olay adlarını taşıyor', () {
      // Kaynaktan türet — belgedeki listeyi körü körüne kabul etme.
      final events = <String>{};
      for (final entity
          in Directory('functions/src').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.ts')) continue;
        events.addAll(
          RegExp(r'log\(\s*"\w+",\s*"([a-z_]+)"')
              .allMatches(entity.readAsStringSync())
              .map((m) => m.group(1)!),
        );
      }
      expect(events, isNotEmpty);
      for (final event in events) {
        expect(monitoring, contains('`$event`'), reason: 'belgede yok: $event');
      }
    });
  });

  group('release runbook zorunlu karar kapıları', () {
    test('gerekli aşamaların tamamı var', () {
      for (final stage in [
        'Preflight',
        'Kalıcı uygulama kimlikleri',
        'Version ve build number',
        'Test ve güvenlik kapıları',
        'Backup / RPO / RTO',
        'Restore tatbikatı',
        'Monitoring hazırlığı',
        'App Check',
        'İmzalı artifact',
        'Internal testing',
        'Fiziksel cihaz smoke matrisi',
        'Mağaza beyanları',
        'Aşamalı yayın',
        'Post-release gözlem',
        'Rollback ve roll-forward',
        'Incident ownership',
        'Release kapanışı',
      ]) {
        expect(runbook, contains(stage), reason: 'eksik aşama: $stage');
      }
    });

    test('KARAR kapıları açıkça işaretli', () {
      expect(runbook, contains('[KARAR]'));
      expect(runbook, contains('[CANLI]'));
      expect(runbook, contains('[REPO]'));
    });

    test('uygulama kimlikleri "kalıcılık onayı bekleniyor" olarak yazılı', () {
      expect(_flat(runbook), contains('kalıcılık onayı beklenmektedir'));
      expect(
        _flat(runbook),
        contains('değişiklik önerilmemiştir'),
        reason: 'kimlik değiştirme önerisi olmamalı',
      );
    });
  });

  group('App Check ↔ deploy sıralaması GÜVENLİ', () {
    test('güncel Functions deploy\'unun App Check etkisi UYARILIYOR', () {
      expect(_flat(runbook), contains('GÜVENLİ DEĞİLDİR'));
      expect(_flat(runbook), contains('deploy anında aktif olur'));
    });

    test('callable enforcement ile console enforcement AYRIŞTIRILMIŞ', () {
      expect(runbook, contains('bağımsızdır'));
      expect(runbook, contains('enforceAppCheck'));
    });

    test('karar ağacı ve cihaz bağımlılığı var', () {
      expect(runbook.toLowerCase(), contains('karar ağacı'));
      expect(runbook, contains('Play Integrity'));
      expect(runbook, contains('App Attest'));
      expect(
        runbook,
        contains('simulator/emulator'),
        reason: 'fiziksel cihaz zorunluluğu yazılmalı',
      );
    });

    test('B seçeneği AYRI PR ve açık karar gerektiriyor', () {
      expect(_flat(runbook), contains('ayrı bir PR'));
    });
  });

  group('rollback sınırları doğru', () {
    test('katman katman ayrılmış', () {
      for (final layer in [
        'Firestore rules',
        'Firestore indexes',
        'Veri şeması',
        'Mobil binary',
        'Backup\'tan restore',
      ]) {
        expect(runbook, contains(layer), reason: 'eksik katman: $layer');
      }
    });

    test('mobil rollback\'in anlık OLMADIĞI yazılı', () {
      expect(_flat(runbook), contains('anlık DEĞİLDİR'));
    });

    test('backup restore ≠ uygulama rollback', () {
      expect(_flat(runbook), contains('Uygulama rollback\'i DEĞİLDİR'));
    });

    test('index geri alımının anlık olmadığı yazılı', () {
      expect(_flat(runbook), contains('anında geri alınamaz'));
    });

    test('canlı komutlar proje doğrulama kapısı ister', () {
      expect(runbook, contains('--project <PROJE_ID>'));
      expect(_flat(runbook), contains('varsayılan projeye'));
    });
  });

  group('dürüst sınırlar kayıtlı', () {
    test('git tag\'in commit değişmezliği sağlamadığı yazılı', () {
      expect(_flat(runbook), contains('yeniden işaretlenebilir'));
    });

    test('imzalı Release paketleme iddiası YAPILMIYOR', () {
      expect(runbook, contains('6F'));
      expect(runbook, contains('--no-codesign'));
    });
  });
}
