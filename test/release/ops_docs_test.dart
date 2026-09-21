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
  late String rollout;
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
    rollout = File('docs/operations/BACKUP-CHECKER-ROLLOUT-2026-09-21.md')
        .readAsStringSync();
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

    test('production backend deploy durumu GERÇEĞE uygun', () {
      final flat = _flat(monitoring);
      expect(flat, contains('Production backend güncel (6B0'));
      expect(
        flat.contains('Production backend güncel değil'),
        isFalse,
        reason: 'deploy sonrası bayat uyarı kalmamalı',
      );
      // Deploy durumunu ANLATAN paragrafın kendisi, deploy EDİLMEYEN
      // yüzeyi de söylemek zorundadır. Kısıtlamayı belgenin başka bir
      // yerindeki bir cümleyle karşılamak yeterli değildir: okuyucu
      // "backend güncel" cümlesini tek başına okur.
      for (final doc in {
        'monitoring': monitoring,
        'runbook': runbook,
        'readme': readme,
      }.entries) {
        final paragraph = doc.value.split(RegExp(r'\n\s*\n')).firstWhere(
              (b) =>
                  b.contains('Production backend') ||
                  b.contains('production backend') ||
                  b.contains('Ödüllü reklam fonksiyonları'),
              orElse: () => '',
            );
        expect(
          RegExp(r'[Öö]düllü reklam fonksiyonları[^.]{0,80}yayında değil')
              .hasMatch(_flat(paragraph)),
          isTrue,
          reason: '${doc.key}: deploy durumu paragrafı eksik yüzeyi saklıyor',
        );
      }
      // Hiçbir belge tüm yüzeyin canlı olduğunu iddia edemez.
      for (final doc in {
        'monitoring': monitoring,
        'runbook': runbook,
        'readme': readme,
      }.entries) {
        expect(
          RegExp(
            r'(Tüm|Bütün|Her) (fonksiyon|callable)[^.]{0,40}(yayında|deploy)',
            caseSensitive: false,
          ).hasMatch(_flat(doc.value)),
          isFalse,
          reason: '${doc.key}: tüm yüzey canlıymış gibi',
        );
      }
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
      for (final macro in ['S_BOTH', 'S_AN', 'S_DEL', 'S_BK']) {
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
          RegExp(r'\bS_(BOTH|AN|DEL|BK)\b').hasMatch(line),
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

    test('11 log-based metric: tablo ve filtre listesi tutarlı', () {
      final table = _section(monitoring, '### 2.2 Log-based metric');
      final filters =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri');
      final listed = RegExp(r'^\| `(kk_[a-z_]+)`', multiLine: true)
          .allMatches(table)
          .map((m) => m.group(1)!)
          .toSet();
      expect(listed.length, 11);
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

    test('11 alert policy: 10 bildirimli, AL-09 bildirimsiz', () {
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
        'AL-10',
        'AL-11',
      ]);
      final notifying =
          rows.where((r) => r.group(2)!.trim().endsWith('| e-posta |')).length;
      expect(notifying, 10);
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
      expect(
        _flat(readme),
        contains('11 log-based metric ve 11 alert policy'),
      );
      expect(
        _flat(_section(runbook, '## 6. Monitoring hazırlığı')),
        contains('11 adet'),
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

    test('backup freshness hâlâ native sinyalmiş gibi sunulmuyor', () {
      final section = _flat(_section(monitoring, '## 4. Backup freshness'));
      expect(section, contains('native bir backup freshness metriği yoktur'));
      expect(
        section,
        contains('uygulama kodu ölçer'),
        reason: 'tazeliğin nereden geldiği açık yazılmalı',
      );
    });

    test('kaynak kimliği, e-posta ve uzun sayısal kimlik yayınlanmıyor', () {
      for (final doc in {
        'monitoring': monitoring,
        'runbook': runbook,
        'rollout': rollout,
      }.entries) {
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

    test('backup freshness artık release riski DEĞİL ama sınırı yazılı', () {
      final stage = _flat(_section(runbook, '## 6. Monitoring hazırlığı'));
      expect(stage, contains('Kapanan release riski'));
      expect(stage, contains('Kalan dürüst sınır'));
      expect(
        stage,
        contains('**canlıda tetiklendiği gözlenmemiştir**'),
        reason: 'AL-11 tetiklenmesi doğrulanmış gibi sunulamaz',
      );
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

  group('6C4 backup freshness checker: CANLI', () {
    String section() => _section(monitoring, '### 4.2 `checkBackupFreshness`');

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
      expect(_flat(runbook), contains('Tazelik eşiği **30 saattir**'));
    });

    test('heartbeat ile problem olayı AYRIŞTIRILMIŞ', () {
      final flat = _flat(section());
      expect(flat, contains('**tam bir**'));
      expect(flat, contains('AL-11'));
      expect(flat, contains('AL-10'));
      expect(flat, contains('hiç çalışmamasını'));
      expect(flat, contains('sorun bulmasını'));
    });

    test('hata "yedek yok" veya "sağlıklı" sayılmıyor', () {
      final flat = _flat(section());
      expect(flat, contains('backup_check_failed'));
      expect(flat, contains('**dönüştürülmez**'));
      expect(flat.contains('403'), isTrue);
      final stage = _flat(_section(runbook, '### 6.1 `checkBackupFreshness`'));
      expect(stage, contains('kontrol çalıştı mı?'));
      expect(stage, contains('anlamına GELMEZ'));
      expect(_flat(rollout), contains('403 "yedek yok" anlamına gelmez'));
    });

    test('adanmış kimlik ve secret yasağı yazılı', () {
      final flat = _flat(section());
      expect(flat, contains('**Adanmış**'));
      expect(flat, contains('hiçbir secret bağlı değil'));
      expect(flat, contains('Hiçbir Firestore belgesi okunmaz'));
      expect(_flat(rollout), contains('En az yetki'));
    });

    test('canlı filtreler anchored regex kullanıyor, `:` kullanmıyor', () {
      final filters =
          _section(monitoring, '### 3.7 Canlı log-based metric filtreleri');
      expect(
        filters,
        contains(
          r'jsonPayload.message=~"^(Error: )?backup_check_heartbeat(\s|$)"',
        ),
      );
      expect(
        filters,
        contains(
          r'jsonPayload.message=~"^(Error: )?(backup_freshness_stale|'
          r'backup_state_unexpected|backup_check_failed)(\s|$)"',
        ),
      );
      expect(
        RegExp(r'jsonPayload\.message\s*:\s*"').hasMatch(filters),
        isFalse,
      );
    });

    test('checker metric ve policy CANLI envanterde', () {
      final metrics = _section(monitoring, '### 2.2 Log-based metric');
      final policies = _section(monitoring, '### 2.3 Alert policy');
      expect(metrics, contains('`kk_backup_check_heartbeat`'));
      expect(metrics, contains('`kk_backup_freshness_problem`'));
      final al10 =
          policies.split('\n').firstWhere((l) => l.startsWith('| AL-10 '));
      final al11 =
          policies.split('\n').firstWhere((l) => l.startsWith('| AL-11 '));
      expect(al10, contains('`kk_backup_freshness_problem`'));
      expect(al10, contains('60 dk'));
      expect(al10.trim(), endsWith('| e-posta |'));
      expect(al11, contains('`kk_backup_check_heartbeat`'));
      expect(al11, contains('3 saat'));
      expect(al11.trim(), endsWith('| e-posta |'));
    });

    test('AL-11 tetiklenmesi DOĞRULANMIŞ gibi sunulmuyor', () {
      for (final doc in {
        'monitoring': monitoring,
        'runbook': runbook,
        'rollout': rollout,
        'readme': readme,
      }.entries) {
        expect(
          RegExp(
            r'AL-11[^.|\n]{0,80}(test edildi|tetiklendiği doğrulandı)',
            caseSensitive: false,
          ).hasMatch(doc.value),
          isFalse,
          reason: doc.key,
        );
      }
      expect(_flat(monitoring), contains('canlıda gözlenmedi'));
      expect(_flat(rollout), contains('canlıda gözlenmedi'));
    });

    test('problem olayları CODE-CONTRACT-ONLY olarak işaretli', () {
      final table = _section(monitoring, '### 1.2 Üretilen olaylar');
      for (final event in [
        'backup_freshness_stale',
        'backup_state_unexpected',
        'backup_check_failed',
      ]) {
        final row = table.split('\n').firstWhere((l) => l.contains('`$event`'));
        expect(row.trim(), endsWith('| CODE-CONTRACT-ONLY |'), reason: event);
      }
      final heartbeat = table
          .split('\n')
          .firstWhere((l) => l.contains('`backup_check_heartbeat`'));
      expect(heartbeat.trim(), endsWith('| VERIFIED |'));
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
          RegExp(
            r'^\*\*(Yok|Canlı değil|Uygulanmadı|Önerilmez)',
          ).hasMatch(status),
          isTrue,
          reason: 'uygulanmamış bileşen "yapıldı" gibi: $row',
        );
      }
    });

    test('hedefli deploy mevcut callable\'ları dışarıda bıraktı', () {
      final flat = _flat(rollout);
      expect(flat, contains('mevcut callable adlarını **içermez**'));
      expect(flat, contains('`updateTime` değerleri'));
      expect(flat, contains('birebir aynı'));
      final target =
          File('functions/src/core/deployment.ts').readAsStringSync();
      final match = RegExp(r'BACKUP_CHECKER_DEPLOY_TARGET =\s*\n?\s*"([^"]+)"')
          .firstMatch(target);
      expect(match, isNotNull);
      final value = match!.group(1)!;
      expect(value, 'functions:checkBackupFreshness');
      for (final existing in ['analyzeDecision', 'deleteAccount']) {
        expect(value.contains(existing), isFalse);
      }
    });

    test('rollback sırası ve AL-11 kapatma kuralı yazılı', () {
      final stage = _flat(_section(runbook, '### 6.1 `checkBackupFreshness`'));
      expect(stage, contains('**Önce AL-11\'i devre dışı bırak**'));
      expect(stage, contains('backfill edilmez'));
      expect(
        stage,
        contains('Geri açarken sıra terstir'),
        reason: 'yeniden açma sırası da yazılmalı',
      );
    });

    test('kanıt belgesi sanitize ve PASS iddiası dürüst', () {
      expect(_flat(rollout), contains('BAŞARILI'));
      expect(_flat(rollout), contains('Bu belgedeki tüm saatler **UTC**'));
      expect(rollout, isNot(contains('karar-backup-checker@')));
      expect(
        RegExp(r'\d+([.,]\d+)?\s*(TRY|TL|USD|₺)').hasMatch(rollout),
        isFalse,
        reason: 'bütçe tutarı yayınlanmaz',
      );
    });
  });

  group('6B0 production backend deploy kanıtı', () {
    late String deploy;

    setUpAll(() {
      deploy = File('docs/operations/PRODUCTION-BACKEND-DEPLOY-2026-09-21.md')
          .readAsStringSync();
    });

    test('yalnız iki callable deploy edildiği yazılı', () {
      final flat = _flat(deploy);
      expect(flat, contains('`analyzeDecision`'));
      expect(flat, contains('`deleteAccount`'));
      expect(flat, contains('**değişmedi**'));
      expect(flat, contains('checkBackupFreshness'));
    });

    test('izin kapısının artifact kanıtı ve SIRASI yazılı', () {
      final flat = _flat(deploy);
      expect(flat, contains('`assertAiConsent(...)`'));
      expect(flat, contains('karar içeriği ilk kez okunur'));
      expect(
        flat,
        contains('İzin yoksa bunların **hiçbiri** çalışmaz'),
        reason: 'sıfır yan etki iddiası açık yazılmalı',
      );
    });

    test('config eşitliği ve App Check korunumu yazılı', () {
      final flat = _flat(deploy);
      expect(flat, contains('yalnız `revision` ve'));
      expect(flat, contains('secret bağları'));
      expect(flat, contains('enforceAppCheck'));
    });

    test('smoke SINIRLARI dürüstçe yazılı', () {
      final flat = _flat(deploy);
      expect(flat, contains('Uçtan uca pozitif akış test EDİLEMEDİ'));
      expect(flat, contains('gerçek bir cihazdan alınmış geçerli App Check'));
      expect(
        flat,
        contains('canlıda gerçekten tetiklendiği gözlenmedi'),
        reason: 'izin kapısının canlı kanıtı iddia edilemez',
      );
    });

    test('revizyon başlangıcı ERROR kayıtları açıklanmış', () {
      final flat = _flat(deploy);
      expect(flat, contains('probe'));
      expect(flat, contains('AL-01 filtresiyle'));
      expect(flat, contains('Hiçbir alarm'));
    });

    test('rollback yolu yazılı ama çalıştırılmadığı belirtilmiş', () {
      final flat = _flat(deploy);
      expect(flat, contains('Önceki revizyonlar ayakta'));
      expect(flat, contains('gerekmedi ve çalıştırılmadı'));
    });

    test('kanıt belgesi sanitize', () {
      for (final rule in <RegExp>[
        RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
        RegExp(r'(notificationChannels|alertPolicies|budgets)/[0-9a-f]'),
        RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'),
        RegExp(r'\b\d{9,}\b'),
      ]) {
        final hit = rule.firstMatch(deploy);
        expect(hit, isNull, reason: 'sızıntı: "${hit?.group(0)}"');
      }
    });
  });
}
