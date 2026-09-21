import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OPERASYON BELGELERİ SÖZLEŞMESİ (6A, 6C1–6C3 kanıtıyla güncellendi).
///
/// Belgeler koddan ve canlı gerçeklikten bağımsız yaşayamaz. Monitoring panosu
/// bir kez "uygulandı" dediği için var olmayan bir Analytics boru hattını
/// anlatıyordu; v2.0 ise ERROR olaylarını hiç yakalamayan bir filtre kalıbı
/// öneriyordu. Runbook, production'da zaten aktif olan App Check
/// enforcement'ını "deploy ile açılacak" gibi anlatıyordu.
///
/// Markdown satır sarmasına dayanıklı eşleşme: anlamı kontrol eder,
/// paragrafın birebir biçimini değil.
String _flat(String source) => source
    .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// [heading] ile başlayan bölümü, aynı veya daha üst seviyedeki bir sonraki
/// başlığa kadar döndürür.
String _section(String doc, String heading) {
  final start = doc.indexOf(heading);
  if (start < 0) fail('bölüm bulunamadı: $heading');
  final level = RegExp(r'^#+').firstMatch(heading)!.group(0)!.length;
  final rest = doc.substring(start + heading.length);
  final end = RegExp('\\n#{1,$level} ').firstMatch(rest);
  return heading + (end == null ? rest : rest.substring(0, end.start));
}

/// `functions/src` içindeki olay adları. `log("<seviye>", <olay ifadesi>, ctx)`
/// çok satırlı ve üçlü (ternary) biçimleri ile doğrudan
/// `logger.<seviye>("<olay>")` çağrılarını kapsar.
Set<String> _codeEvents({String? level}) {
  final logCall = RegExp(
    r'\blog\(\s*"(debug|info|warn|error)",\s*([\s\S]*?),\s*(?:ctx|logCtx)\b',
  );
  final direct = RegExp(r'\blogger\.(debug|info|warn|error)\(\s*"([a-z_]+)"');
  final literal = RegExp(r'"([a-z][a-z0-9_]+)"');
  final events = <String>{};
  for (final entity in Directory('functions/src').listSync(recursive: true)) {
    if (entity is! File ||
        !entity.path.endsWith('.ts') ||
        entity.path.endsWith('.test.ts')) {
      continue;
    }
    final src = entity.readAsStringSync();
    for (final m in logCall.allMatches(src)) {
      if (level != null && m.group(1) != level) continue;
      events.addAll(literal.allMatches(m.group(2)!).map((x) => x.group(1)!));
    }
    for (final m in direct.allMatches(src)) {
      if (level != null && m.group(1) != level) continue;
      events.add(m.group(2)!);
    }
  }
  return events;
}

/// Tarihli düzeltme notları eski ifadeyi alıntılar; yasak-ifade taraması
/// bu blokları hariç tutar, yoksa düzeltmenin kendisi ihlal sayılır.
String _withoutCorrectionNotes(String doc) => doc.replaceAll(
      RegExp(r'^> \*\*Düzeltme[^\n]*\n(^>[^\n]*\n)*', multiLine: true),
      '',
    );

void main() {
  late String monitoring;
  late String monitoringBody;
  late String runbook;
  late String evidence;
  late String readme;

  setUpAll(() {
    monitoring = File('docs/MONITORING-PANOSU.md').readAsStringSync();
    // §0 ESKİ iddiaları DÜZELTMEK için alıntılar; yasak-iddia taraması
    // bu bölümü hariç tutmalı, yoksa düzeltmenin kendisi ihlal sayılır.
    monitoringBody = monitoring.substring(
      monitoring.indexOf('## 1. Bugün gerçekten uygulanmış olan'),
    );
    runbook = File('docs/RELEASE-RUNBOOK.md').readAsStringSync();
    evidence =
        File('docs/operations/RESTORE-DRILL-2026-09-14.md').readAsStringSync();
    readme = File('README.md').readAsStringSync();
  });

  group('monitoring panosu gerçekle uyumlu', () {
    test('Analytics SDK\'sı gerçekten YOK (kanıt)', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('firebase_analytics')));
    });

    test('Analytics AKTİF bir araç gibi sunulmuyor', () {
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

    test('production backend güncel olmadığı UYARISI var', () {
      expect(_flat(monitoring), contains('Production backend güncel değil'));
    });

    test('olay tablosu KODDAKİ olay adlarının TAMAMINI taşıyor', () {
      final events = _codeEvents();
      // Çok satırlı/ternary/doğrudan logger çağrıları da yakalanmalı.
      expect(
        events,
        containsAll([
          'analysis_completed',
          'analysis_superseded',
          'reward_callback',
          'reward_callback_invalid_signature',
        ]),
      );
      final table = _section(monitoring, '### 1.2 Üretilen olaylar');
      for (final event in events) {
        expect(table, contains('`$event`'), reason: 'tabloda yok: $event');
      }
    });

    test('olay tablosunda koddaki seviyeler doğru', () {
      final table = _section(monitoring, '### 1.2 Üretilen olaylar');
      for (final level in ['info', 'warn', 'error']) {
        for (final event in _codeEvents(level: level)) {
          expect(
            RegExp('\\| `$event` \\| $level \\|').hasMatch(table),
            isTrue,
            reason: '$event seviyesi $level olarak yazılmalı',
          );
        }
      }
    });

    test(
        'düzeltilmiş alan listeleri: `name` alanı yok, unexpected alanları var',
        () {
      final table = _section(monitoring, '### 1.2 Üretilen olaylar');
      for (final line in table.split('\n').where(
            (l) =>
                l.contains('`reservation_settlement_failed`') ||
                l.contains('`reservation_reconcile_failed`'),
          )) {
        expect(line, isNot(contains('`name`')), reason: line);
      }
      final unexpected = table
          .split('\n')
          .firstWhere((l) => l.contains('`request_failed_unexpected`'));
      expect(unexpected, contains('`errorCode`'));
      expect(unexpected, contains('`errorType`'));
    });
  });

  group('monitoring filtre sözleşmesi', () {
    test('ERROR olayları için anchored regex sözleşmesi var', () {
      expect(
        monitoringBody,
        contains(r'jsonPayload.message=~"^(Error: )?<olay>(\s|$)"'),
      );
      final filters =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri');
      for (final event in _codeEvents(level: 'error')) {
        if (!filters.contains('kk_$event ')) continue;
        expect(
          filters,
          contains('jsonPayload.message=~"^(Error: )?$event(\\s|\$)"'),
          reason: 'ERROR olayı regex kullanmalı: $event',
        );
      }
    });

    test('ERROR olaylarında birebir eşitlik ÖNERİLMİYOR', () {
      for (final event in _codeEvents(level: 'error')) {
        expect(
          monitoringBody.contains('jsonPayload.message="$event"'),
          isFalse,
          reason: 'ERROR olayı eşitlikle eşlenemez: $event',
        );
      }
    });

    test('exact olay eşlemesi için `:` operatörü önerilmiyor', () {
      expect(
        RegExp(r'jsonPayload\.message\s*:\s*"').hasMatch(monitoringBody),
        isFalse,
        reason: '`:` alt dize eşleştirir; olay filtresinde kullanılamaz',
      );
      expect(_flat(monitoringBody), contains('operatörü **kullanılmaz**'));
    });

    test('App Check filtresi mesaja değil verifications.app alanına dayanıyor',
        () {
      final line =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri')
              .split('\n')
              .firstWhere((l) => l.startsWith('kk_appcheck_reject'));
      expect(
        line,
        contains('jsonPayload.verifications.app=("MISSING" OR "INVALID")'),
      );
      expect(
        line,
        isNot(contains('severity')),
        reason: 'MISSING retleri DEBUG seviyesindedir',
      );
      expect(line, isNot(contains('jsonPayload.message')));
    });

    test('genel `severity>=ERROR` alarmı reddediliyor', () {
      expect(_flat(monitoringBody), contains('alarmı **kurulmaz**'));
      final filters =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri');
      for (final line
          in filters.split('\n').where((l) => l.contains('severity>=ERROR'))) {
        expect(
          line,
          contains('jsonPayload.message=~"^(Error: )?'),
          reason: 'olay koşulsuz severity filtresi: $line',
        );
      }
    });

    test('5xx için sıfıra yakın trafikte yüzde eşiği kullanılmıyor', () {
      expect(
        _flat(_section(monitoring, '### 3.5 Cloud Run 5xx')),
        contains('yüzde eşiği kullanılmaz'),
      );
    });

    test('tüm canlı filtreler proje, resource type ve servis kapsamı içeriyor',
        () {
      final scopes = _section(monitoring, '### 3.1 Kapsam');
      for (final macro in ['S_BOTH', 'S_AN', 'S_DEL']) {
        final def =
            scopes.split('\n').firstWhere((l) => l.startsWith('$macro '));
        expect(def, contains('resource.type="cloud_run_revision"'));
        expect(
          def,
          contains('resource.labels.project_id="karar-kocum-production"'),
        );
        expect(def, contains('resource.labels.service_name='));
        expect(def.toLowerCase(), isNot(contains('reward')));
      }
      final filters =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri');
      for (final line
          in filters.split('\n').where((l) => l.startsWith('kk_'))) {
        expect(
          RegExp(r'\bS_(BOTH|AN|DEL)\b').hasMatch(line),
          isTrue,
          reason: line,
        );
      }
    });
  });

  group('canlı monitoring durumu belgelenmiş (6C2/6C3)', () {
    Set<String> metricsIn(String text) => RegExp(r'`?(kk_[a-z_]+)`?')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toSet();

    test('9 log-based metric: tablo ve filtre listesi tutarlı', () {
      final table = _section(monitoring, '### 2.2 Log-based metric');
      final filters =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri');
      final listed = RegExp(r'^\| `(kk_[a-z_]+)`', multiLine: true)
          .allMatches(table)
          .map((m) => m.group(1)!)
          .toSet();
      expect(listed.length, 9);
      expect(
        metricsIn(
          filters.split('\n').where((l) => l.startsWith('kk_')).join('\n'),
        ),
        listed,
      );
      expect(
        _flat(table),
        contains('backfill etmez'),
        reason: 'metric\'lerin geçmişi saymadığı yazılmalı',
      );
    });

    test('9 alert policy: 8 bildirimli, AL-09 bildirimsiz', () {
      final table = _section(monitoring, '### 2.3 Alert policy');
      final rows = RegExp(r'^\| (AL-\d\d) \|([^\n]*)$', multiLine: true)
          .allMatches(table)
          .toList();
      expect(rows.map((r) => r.group(1)).toList(), [
        'AL-01',
        'AL-02',
        'AL-03',
        'AL-04',
        'AL-05',
        'AL-06',
        'AL-07',
        'AL-08',
        'AL-09',
      ]);
      final notifying =
          rows.where((r) => r.group(2)!.trim().endsWith('| e-posta |')).length;
      expect(notifying, 8);
      final al09 = rows.firstWhere((r) => r.group(1) == 'AL-09').group(2)!;
      expect(al09, contains('YOK'));
      expect(al09, contains('kk_appcheck_reject'));
    });

    test('analysis_completed yalnız baseline; alarmı yok', () {
      final policies = _section(monitoring, '### 2.3 Alert policy');
      final policyRows = RegExp(r'^\| AL-\d\d \|[^\n]*$', multiLine: true)
          .allMatches(policies)
          .map((m) => m.group(0)!);
      expect(
        policyRows.any((r) => r.contains('kk_analysis_completed')),
        isFalse,
      );
      expect(_flat(policies), contains('**alert policy yoktur**'));
    });

    test('README ve runbook aynı canlı sayıları söylüyor', () {
      expect(_flat(readme), contains('9 log-based metric ve 9 alert policy'));
      expect(
        _flat(_section(runbook, '## 6. Monitoring hazırlığı')),
        contains('9 adet'),
      );
    });

    test('budget harcamayı DURDURMAZ ve OpenAI maliyetini kapsamaz', () {
      final flat = _flat(monitoringBody);
      expect(flat, contains('Budget harcamayı durdurmaz'));
      expect(flat, contains("OpenAI maliyeti GCP budget'ına dahil değildir"));
      for (final doc in [monitoringBody, readme, runbook]) {
        expect(
          RegExp(r'harcamayı (durdurur|keser|engeller)\b').hasMatch(_flat(doc)),
          isFalse,
        );
      }
      expect(
        RegExp(r'\d+([.,]\d+)?\s*(TRY|TL|USD|₺)').hasMatch(monitoring),
        isFalse,
        reason: 'bütçe tutarı yayınlanmaz',
      );
    });

    test('backup freshness native sinyalmiş gibi sunulmuyor; checker AÇIK', () {
      final section = _flat(_section(monitoring, '## 4. Backup freshness'));
      expect(section, contains('native bir backup freshness metriği yoktur'));
      expect(section, contains('henüz YOK'));
      for (final doc in {
        'monitoring': monitoringBody,
        'runbook': runbook,
        'readme': readme,
      }.entries) {
        expect(
          RegExp(
            r'checker[^.|\n]{0,80}(kuruldu|tamamlandı|aktif)',
            caseSensitive: false,
          ).hasMatch(doc.value),
          isFalse,
          reason: '${doc.key}: checker kurulmuş gibi sunuluyor',
        );
      }
    });

    test('kaynak kimliği, e-posta ve uzun sayısal kimlik yayınlanmıyor', () {
      for (final doc
          in {'monitoring': monitoring, 'runbook': runbook}.entries) {
        for (final rule in <RegExp>[
          RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
          RegExp(r'(notificationChannels|alertPolicies|budgets)/[0-9a-f]'),
          RegExp(r'\b\d{9,}\b'),
        ]) {
          final hit = rule.firstMatch(doc.value);
          expect(hit, isNull, reason: '${doc.key}: "${hit?.group(0)}"');
        }
      }
    });
  });

  group('storage metriği günlük örneklenen bir metrik gibi anlatılmıyor', () {
    test('hiçbir belgede "günlük örnekleme" iddiası yok', () {
      final assertive = RegExp(
        r'(günlük|daily)\s+örnekle|≈\s*günlük|yaklaşık\s+\**günlük\**\s+örnekle',
        caseSensitive: false,
      );
      for (final doc in {
        'monitoring': monitoring,
        'runbook': runbook,
        'evidence': evidence,
        'readme': readme,
      }.entries) {
        expect(
          assertive.hasMatch(_withoutCorrectionNotes(doc.value)),
          isFalse,
          reason: '${doc.key}: storage metriği günlük örnekleniyor gibi',
        );
      }
    });

    test('descriptor periyodu ile gözlenen aralıklı yayın ayrılmış', () {
      for (final doc in {
        'monitoring': monitoring,
        'runbook': runbook,
        'evidence': evidence,
      }.entries) {
        final flat = _flat(doc.value);
        expect(flat, contains('60 saniye'), reason: doc.key);
        expect(flat.toLowerCase(), contains('aralıklı'), reason: doc.key);
      }
      expect(_flat(monitoring), contains('11–13 saat'));
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

    test('backup freshness checker eksikliği release riski olarak yazılı', () {
      final monitoringStage =
          _flat(_section(runbook, '## 6. Monitoring hazırlığı'));
      expect(monitoringStage, contains('Release riski'));
      expect(monitoringStage, contains('Backup freshness checker'));
    });
  });

  group('App Check: production enforcement GERÇEĞİ', () {
    test('production callable\'ları App Check\'i ZATEN enforce ediyor', () {
      final appCheck = _flat(_section(runbook, '## 7. App Check'));
      expect(appCheck, contains('zaten enforce ediyor'));
      expect(appCheck, contains("enforcement'ı ilk kez açmaz"));
      expect(_flat(monitoringBody), contains('zaten enforce ediliyor'));
    });

    test('"deploy enforcement\'ı ilk kez açar" anlatımı YOK', () {
      for (final doc in {
        'runbook': runbook,
        'monitoring': monitoringBody,
        'readme': readme,
      }.entries) {
        final flat = _flat(_withoutCorrectionNotes(doc.value));
        expect(
          flat.contains('deploy anında aktif olur'),
          isFalse,
          reason: doc.key,
        );
        expect(
          RegExp(r'ilk kez (açar|aktif olur|devreye girer)\b').hasMatch(flat),
          isFalse,
          reason: doc.key,
        );
        expect(
          RegExp(
            r'App Check[^.]{0,80}(henüz aktif değil|ileride açılacak|henüz açılmadı)',
            caseSensitive: false,
          ).hasMatch(flat),
          isFalse,
          reason: '${doc.key}: App Check kapalıymış gibi',
        );
      }
    });

    test('callable enforcement ile console enforcement AYRIŞTIRILMIŞ', () {
      expect(runbook, contains('bağımsızdır'));
      expect(runbook, contains('enforceAppCheck'));
      expect(
        _flat(runbook),
        contains("0 olması, callable kod seviyesindeki enforcement'ın kapalı "
            'olduğu anlamına gelmez'),
      );
    });

    test('provider ve gerçek cihaz doğrulaması hâlâ AÇIK release kapısı', () {
      final gate = _flat(
        _section(runbook, '### 7.1 Gerçek durum ve kalan release kapısı'),
      );
      expect(gate, contains('Kalan release kapısı'));
      for (final item in [
        'Provider kayıtlarının',
        'gerçek cihazdan',
        'reddetme oranının',
      ]) {
        expect(gate, contains(item), reason: item);
      }
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

  group('6C4 backup freshness checker: kod hazır, canlı DEĞİL', () {
    String section() =>
        _section(monitoring, '### 4.1 `checkBackupFreshness` sözleşmesi');

    test('olay sözleşmesi koddaki dört olayı da taşıyor', () {
      expect(
        _codeEvents(),
        containsAll([
          'backup_check_heartbeat',
          'backup_freshness_stale',
          'backup_state_unexpected',
          'backup_check_failed',
        ]),
      );
      for (final event in [
        'backup_check_heartbeat',
        'backup_freshness_stale',
        'backup_state_unexpected',
        'backup_check_failed',
      ]) {
        expect(section(), contains('`$event`'), reason: event);
      }
    });

    test('kadans, eşik ve kapsam yazılı', () {
      final flat = _flat(section());
      expect(flat, contains('Saatte bir'));
      expect(flat, contains('UTC'));
      expect(flat, contains('**30 saat**'));
      expect(flat, contains('`(default)`'));
    });

    test('heartbeat ile problem olayı AYRIŞTIRILMIŞ', () {
      final flat = _flat(section());
      expect(flat, contains('**tam bir**'));
      expect(flat, contains('hiç çalışmaması'));
      expect(flat, contains('sorun bulması'));
    });

    test('hata "yedek yok" veya "sağlıklı" sayılmıyor', () {
      final flat = _flat(section());
      expect(flat, contains('backup_check_failed'));
      expect(flat, contains('**dönüştürülmez**'));
      expect(flat.contains('403'), isTrue);
      expect(
        _flat(_section(runbook, '### 6.1 `checkBackupFreshness`')),
        contains('kontrol gerçekten çalıştı mı?'),
      );
    });

    test('adanmış kimlik ve secret yasağı yazılı', () {
      final flat = _flat(section());
      expect(flat, contains('**Adanmış**'));
      expect(flat, contains('hiçbir secret bağlanmaz'));
      expect(flat, contains('Hiçbir Firestore belgesi okunmaz'));
    });

    test('planlanan filtreler anchored regex kullanıyor, `:` kullanmıyor', () {
      expect(
        section(),
        contains(
          r'jsonPayload.message=~"^(Error: )?backup_check_heartbeat(\s|$)"',
        ),
      );
      expect(
        section(),
        contains(
          r'jsonPayload.message=~"^(Error: )?(backup_freshness_stale|'
          r'backup_state_unexpected|backup_check_failed)(\s|$)"',
        ),
      );
      expect(
        RegExp(r'jsonPayload\.message\s*:\s*"').hasMatch(section()),
        isFalse,
      );
    });

    test('checker metric/policy CANLI envantere eklenmemiş', () {
      final metrics = _section(monitoring, '### 2.2 Log-based metric');
      final policies = _section(monitoring, '### 2.3 Alert policy');
      final live = _section(monitoring, '### 3.7 Canlı log-based metric');
      for (final table in [metrics, policies, live]) {
        expect(
          table.contains('kk_backup'),
          isFalse,
          reason: table.split('\n').first,
        );
      }
      expect(policies.contains('AL-10'), isFalse);
      expect(policies.contains('AL-11'), isFalse);
    });

    test('"Henüz UYGULANMAMIŞ" tablosu yapılmış iş İDDİA EDEMEZ', () {
      final rows = _section(monitoring, '## 5. Henüz UYGULANMAMIŞ')
          .split('\n')
          .where((l) => l.startsWith('| ') && !l.startsWith('| Bileşen'))
          .where((l) => !l.startsWith('|---'));
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final status = row.split('|')[2].trim();
        expect(
          RegExp(r'^\*\*(Yok|Canlı değil|Uygulanmadı|Önerilmez)')
              .hasMatch(status),
          isTrue,
          reason: 'uygulanmamış bileşen "yapıldı" gibi: $row',
        );
      }
    });

    test('canlı olmadığı runbook ve monitoring\'de açıkça yazılı', () {
      expect(_flat(section()), contains('canlıda **mevcut değildir**'));
      final stage = _flat(_section(runbook, '## 6. Monitoring hazırlığı'));
      expect(stage, contains('Release riski'));
      expect(stage, contains('Backup freshness checker'));
      expect(stage, contains('**kapatmaz**'));
    });

    test('rollout sırası ve AL-11 kapatma kuralı yazılı', () {
      final stage = _flat(_section(runbook, '### 6.1 `checkBackupFreshness`'));
      expect(stage, contains('Scheduler API'));
      expect(stage, contains('hedefli'));
      expect(stage, contains('önce AL-11 devre'));
    });
  });
}
