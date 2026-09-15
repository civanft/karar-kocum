import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// İŞ PAKETİ 6B3 — BACKUP/RESTORE OPERASYON SÖZLEŞMESİ.
///
/// 6B2'de canlı bir restore tatbikatı yapıldı ve PASS aldı. Bu testler o
/// tatbikattan çıkan **tehlikeli varyasyonları** reddeder:
///
/// - `--destination-database` `(default)` değerini sözdizimsel olarak kabul
///   eder; yanlış yazılmış tek bir destination production'ı hedefler.
/// - Hedefi önceden oluşturmak restore'u başarısız kılar.
/// - `sourceInfo.progress=COMPLETED` tek başına başarı kanıtı değildir.
/// - Silme için delete protection yalnız drill hedefinde kapatılabilir.
/// - Bir HTTP 403 "kayıt yok" diye okunursa eksik doğrulama "temiz" raporlanır.
///
/// Testler paragrafı birebir eşlemez; başlık/alan/değişmez (invariant)
/// düzeyinde çalışır ve satır sarmasına dayanıklıdır.
String _flat(String source) => source
    // Markdown alıntı işaretçisi ("> ") satır ortasına girip eşleşmeyi
    // bozmasın; anlam kontrol edilir, biçim değil.
    .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// [heading] ile başlayan bölümü, **aynı ya da daha üst** seviyedeki bir
/// sonraki başlığa kadar döndürür. Alt bölümler (`###`) içeride kalır.
String _section(String doc, String heading) {
  final start = doc.indexOf(heading);
  if (start < 0) fail('bölüm bulunamadı: $heading');
  final level = RegExp(r'^#+').firstMatch(heading)!.group(0)!.length;
  final rest = doc.substring(start + heading.length);
  final end = RegExp('\\n#{1,$level} ').firstMatch(rest);
  return heading + (end == null ? rest : rest.substring(0, end.start));
}

/// Public repoya asla yazılmaması gereken tanımlayıcılar.
const _evidencePath = 'docs/operations/RESTORE-DRILL-2026-09-14.md';

void main() {
  late String runbook;
  late String evidence;

  setUpAll(() {
    runbook = File('docs/RELEASE-RUNBOOK.md').readAsStringSync();
    evidence = File(_evidencePath).readAsStringSync();
  });

  group('restore hedefi — production\'a sızmayı engelleyen kapılar', () {
    test('hedef veritabanı ÖNCEDEN OLUŞTURULMAZ', () {
      final flat = _flat(_section(runbook, '### 5.1'));
      expect(flat, contains('oluşturulmaz'));
      expect(
        RegExp(r'operation.{0,60}oluşturur', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
        reason: 'hedefi restore operation\'ının oluşturduğu yazılmalı',
      );
    });

    test('hiçbir belge hedefi önceden oluşturmayı ÖNERMİYOR', () {
      // "Önce target database oluştur" gibi bir yönerge felakete davettir.
      final preCreate = RegExp(
        r'(hedef|target|destination)[^.\n]{0,60}'
        r'(oluşturulur|oluşturun|oluşturulmalı|oluştur(?![a-zçğıöşüA-ZÇĞIİÖŞÜ]))',
        caseSensitive: false,
      );
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        final hit = preCreate.firstMatch(doc.value);
        expect(
          hit,
          isNull,
          reason: '${doc.key}: ön-oluşturma yönergesi → "${hit?.group(0)}"',
        );
      }
    });

    test('destination ASLA `(default)` olamaz', () {
      final flat = _flat(_section(runbook, '### 5.1'));
      // Yasak açıkça yazılı ve CLI\'ın kabul ettiği uyarısı var.
      expect(flat, contains('(default)'));
      expect(
        RegExp(r'sözdizimsel olarak kabul eder').hasMatch(flat),
        isTrue,
        reason: 'CLI\'ın (default) değerini reddetmediği uyarısı olmalı',
      );
      expect(
        RegExp(r'destination `\(default\)` ise komut çalıştırılmaz')
            .hasMatch(flat),
        isTrue,
        reason: 'programatik ret kuralı olmalı',
      );
      // Hiçbir belgede (default) hedef gösteren bir komut/örnek olmamalı.
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        expect(
          RegExp(r'--destination-database[=\s]+`?\(default\)')
              .hasMatch(_flat(doc.value)),
          isFalse,
          reason: '${doc.key}: (default) hedefli restore komutu',
        );
        expect(
          RegExp(
            r'(destination|hedef)[^.\n]{0,40}`?\(default\)`?[^.\n]{0,30}'
            r'(olur|olabilir|seçilir|kullanılır)',
            caseSensitive: false,
          ).hasMatch(_flat(doc.value)),
          isFalse,
          reason: '${doc.key}: (default) hedef olarak sunuluyor',
        );
      }
    });

    test('aynı destination için İKİNCİ restore yasak', () {
      expect(
        RegExp(
          r'ikinci[^.]{0,40}restore[^.]{0,40}(başlatılmaz|başlatılmamalı|yasak)',
          caseSensitive: false,
        ).hasMatch(_flat(runbook)),
        isTrue,
      );
    });
  });

  group('başarı otoritesi — hangi sinyale güvenilir', () {
    test('long-running operation `done=true` + hatasızlık kapısı VAR', () {
      final flat = _flat(_section(runbook, '### 5.2'));
      expect(
        RegExp(r'done\s*=\s*true').hasMatch(flat),
        isTrue,
        reason: 'done=true kapısı kaldırılmış',
      );
      expect(flat, contains('SUCCESSFUL'));
      expect(
        RegExp(r'hatas[ıi]z', caseSensitive: false).hasMatch(flat),
        isTrue,
        reason: 'hatasızlık koşulu yazılmalı',
      );
      // Kanıt belgesi de aynı otoriteyi kullanmalı.
      expect(RegExp(r'done\s*=\s*true').hasMatch(_flat(evidence)), isTrue);
    });

    test('`sourceInfo.progress=COMPLETED` TEK BAŞINA yeterli değil', () {
      final flat = _flat(_section(runbook, '### 5.2'));
      expect(flat, contains('sourceInfo.progress'));
      expect(
        RegExp(r'[Tt]ek başına yeterli DEĞİLDİR').hasMatch(flat),
        isTrue,
        reason: 'describe çıktısı başarı otoritesi sayılıyor',
      );
      // İki yüzeyin ayrışabildiği kayıtlı olmalı.
      expect(
        RegExp(r'PROCESSING').hasMatch(flat),
        isTrue,
        reason: 'operation ile describe ayrışması anlatılmalı',
      );
    });

    test('sabit 15 dakika başarısızlık ölçütü DEĞİL', () {
      final flat = _flat(_section(runbook, '### 5.3'));
      expect(
        RegExp(r'15 dakika[^.]{0,60}başarısız SAYILMAZ', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
      );
      // Uzayan operation: iptal/yeniden başlatma/silme yok.
      expect(
        RegExp(r'iptal etme', caseSensitive: false).hasMatch(flat),
        isTrue,
      );
      expect(
        RegExp(r'(foreground|bounded|sınırlı)', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
        reason: 'polling kontrollü ve sınırlı olmalı',
      );
    });
  });

  group('temizleme — delete protection dar kapsamlı', () {
    test('delete protection YALNIZ drill hedefi için kapatılır', () {
      final flat = _flat(_section(runbook, '### 5.5'));
      expect(
        flat,
        contains('yalnız drill veritabanı için'),
        reason: 'kapatma kapsamı genişletilmiş',
      );
      // (default) ile kapatmayı ilişkilendiren hiçbir ifade olmamalı.
      expect(
        RegExp(r'`--database`[^.]{0,80}drill').hasMatch(flat),
        isTrue,
        reason: 'kapatma komutunun hedefi drill olarak doğrulanmalı',
      );
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        final f = _flat(doc.value);
        expect(
          RegExp(r'--database[=\s]+`?\(default\)').hasMatch(f),
          isFalse,
          reason: '${doc.key}: (default) hedefli --database komutu',
        );
        expect(
          RegExp(
            r'\(default\)[^.]{0,80}(delete protection|koruma)[^.]{0,40}'
            r'(kapatılır|kapatılacak|kapatılmalı|kapatılabilir|kapatın)',
            caseSensitive: false,
          ).hasMatch(f),
          isFalse,
          reason: '${doc.key}: (default) delete protection kapatılıyor',
        );
        expect(
          RegExp(
            r'delete protection[^.]{0,60}\(default\)[^.]{0,40}'
            r'(kapatılır|kapatılacak|kapatılmalı|kapatılabilir|kapatın)',
            caseSensitive: false,
          ).hasMatch(f),
          isFalse,
          reason: '${doc.key}: (default) delete protection kapatılıyor',
        );
      }
    });

    test('kaynak `(default)` delete protection\'ı KORUNUR', () {
      final flat = _flat(_section(runbook, '### 5.5'));
      expect(
        RegExp(r'\(default\)[^.]{0,80}DOKUNULMAZ', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
        reason: 'kaynak korumasının dokunulmazlığı yazılmalı',
      );
      expect(
        RegExp(r'(hâlâ|hala) \*\*açık\*\*', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
        reason: 'kapatma sonrası kaynak korumasının doğrulandığı yazılmalı',
      );
    });

    test('temizleme KOŞULLU — FAIL/belirsizde veritabanı korunur', () {
      final flat = _flat(_section(runbook, '### 5.5'));
      expect(flat, contains('yalnız tüm zorunlu kontroller PASS ise'));
      expect(
        RegExp(
          r'(FAIL|belirsiz|doğrulanamaz)[^.]{0,60}korunur',
          caseSensitive: false,
        ).hasMatch(flat),
        isTrue,
      );
    });

    test('restore edilen veritabanının delete protection AÇIK geldiği kayıtlı',
        () {
      expect(
        RegExp(r'delete protection[^.]{0,20}(AÇIK|açık)').hasMatch(runbook),
        isTrue,
      );
      expect(
        RegExp(r'delete protection[^.]{0,20}(AÇIK|açık)').hasMatch(evidence),
        isTrue,
      );
    });
  });

  group('backup kapsamı — ne gelir, ne gelmez', () {
    test('index DAHİL; rules ve TTL kapsam DIŞI', () {
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        final flat = _flat(doc.value);
        expect(
          RegExp(r'[Cc]omposite index[^|]{0,60}\| \*\*Evet\*\*').hasMatch(flat),
          isTrue,
          reason: '${doc.key}: index\'in backup ile geldiği yazılmalı',
        );
        expect(
          RegExp(r'Security Rules[^|]{0,40}\| \*\*Hayır\*\*').hasMatch(flat),
          isTrue,
          reason: '${doc.key}: rules\'ın gelmediği yazılmalı',
        );
        expect(
          RegExp(r'TTL polic[^|]{0,40}\| \*\*Hayır\*\*').hasMatch(flat),
          isTrue,
          reason: '${doc.key}: TTL\'in gelmediği yazılmalı',
        );
      }
    });

    test('rules gelmediği için restore TEK BAŞINA servis edilebilir değil', () {
      expect(
        RegExp(
          r'rules[^.]{0,80}(servis edilebilir durumda değildir)',
          caseSensitive: false,
        ).hasMatch(_flat(runbook)),
        isTrue,
      );
    });

    test('kaynakta aktif TTL yokken TTL sonucunun ZAYIF kanıt olduğu yazılı',
        () {
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        expect(
          RegExp(
            r'aktif TTL.{0,250}tek başına güçlü bir restore kanıtı '
            r'değildir',
            caseSensitive: false,
          ).hasMatch(_flat(doc.value)),
          isTrue,
          reason: '${doc.key}: beklenen sonuç güçlü kanıt sanılıyor',
        );
      }
    });
  });

  group('doğrulama yöntemi — neyin kanıt sayıldığı', () {
    test('HTTP 403/hata yanıtı BOŞ LİSTE sayılmaz', () {
      final badRead = RegExp(
        r'403[^.]{0,80}boş liste[^.]{0,40}'
        r'(sayılır|kabul edil|yorumlanır|demektir|anlamına)',
        caseSensitive: false,
      );
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        final hit = badRead.firstMatch(_flat(doc.value));
        expect(
          hit,
          isNull,
          reason: '${doc.key}: 403 boş liste sayılıyor → "${hit?.group(0)}"',
        );
      }
      expect(
        _flat(runbook),
        contains('boş liste sayılmaz'),
        reason: 'kural runbook\'tan kaldırılmış',
      );
      expect(
        RegExp(
          r'HTTP durum kodu[^.]{0,60}(ayrıştırıl|parse)',
          caseSensitive: false,
        ).hasMatch(_flat(runbook)),
        isTrue,
        reason: 'structured error ayrıştırma kuralı olmalı',
      );
    });

    test('production izolasyonu write-count metriğiyle KANITLANMAZ', () {
      expect(
        RegExp(r'write-count metri.{0,40}kanıtlanmaz', caseSensitive: false)
            .hasMatch(_flat(runbook)),
        isTrue,
      );
      expect(
        RegExp(r'write-count metri.{0,60}kanıtlanmadı', caseSensitive: false)
            .hasMatch(_flat(evidence)),
        isTrue,
      );
    });

    test('audit log doğrulaması TAM HEDEF KİMLİĞİNİ kontrol ediyor', () {
      final flat = _flat(_section(evidence, '## 7. Production izolasyon'));
      expect(flat.toLowerCase(), contains('audit log'));
      expect(
        flat.toLowerCase(),
        contains('tam hedef kimliğ'),
        reason: 'audit kaydında hedef kimliği doğrulanmalı',
      );
      expect(
        RegExp(r'(resourceName|databaseId)').hasMatch(flat),
        isTrue,
        reason: 'hangi alanın kontrol edildiği yazılmalı',
      );
      expect(
        RegExp(r'operation metadata', caseSensitive: false).hasMatch(flat),
        isTrue,
      );
    });

    test('gecikmeli storage metriği YANLIŞ NEGATİF üretmiyor', () {
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        expect(
          RegExp(
            r'(storage|depolama) metri.{0,250}'
            r'(restore başarısızlığı değildir|yanlış negatif|'
            r'başarısızlığı olarak yorumlanmadı)',
            caseSensitive: false,
          ).hasMatch(_flat(doc.value)),
          isTrue,
          reason: '${doc.key}: metrik gecikmesi başarısızlık sayılıyor',
        );
      }
    });

    test('kota sorunu GLOBAL CLI yapılandırmasını değiştirmiyor', () {
      expect(
        RegExp(
          r'global CLI yapılandırması değiştirilmez',
          caseSensitive: false,
        ).hasMatch(_flat(runbook)),
        isTrue,
      );
      expect(_flat(runbook), contains('x-goog-user-project'));
    });
  });

  group('kanıt belgesi — dürüst, eksiksiz ve sanitize', () {
    test('zorunlu bölümlerin tamamı var', () {
      for (final heading in [
        '## 1. Amaç ve kapsam',
        '## 2. Onaylanan kaynak ve hedef',
        '## 3. Zaman çizelgesi',
        '## 4. Restore sonucunun özeti',
        '## 5. PASS/FAIL matrisi',
        '## 6. Index / TTL / rules gözlemleri',
        '## 7. Production izolasyon kanıtının yöntemi',
        '## 8. Koşullu temizleme sonucu',
        '## 9. Öğrenilen dersler',
        '## 10. Sonraki tatbikat',
        '## 11. Açık kalan işler',
      ]) {
        expect(evidence, contains(heading), reason: 'eksik bölüm: $heading');
      }
    });

    test('sonuç PASS ve matriste FAIL yok', () {
      expect(
        RegExp(r'\*\*Sonuç\*\* \| \*\*PASS\*\*').hasMatch(evidence),
        isTrue,
      );
      final matrix = _section(evidence, '## 5. PASS/FAIL matrisi');
      expect(
        matrix,
        contains('Zorunlu kontrollerin tamamı PASS'),
        reason: 'toplu sonuç ifadesi olmalı',
      );
      expect(
        RegExp(r'\|\s*\*\*FAIL\*\*\s*\|').hasMatch(matrix),
        isFalse,
        reason: 'PASS ilan edilirken matriste FAIL var',
      );
    });

    test('drill veritabanının SİLİNDİĞİ ve production\'ın KORUNDUĞU yazılı',
        () {
      final flat = _flat(_section(evidence, '## 8. Koşullu temizleme sonucu'));
      expect(
        RegExp(r'\*\*Silindi\*\*').hasMatch(flat),
        isTrue,
        reason: 'drill veritabanının silindiği yazılmalı',
      );
      expect(
        RegExp(r'\(default\).{0,400}değişmedi', caseSensitive: false)
            .hasMatch(flat),
        isTrue,
        reason: 'production korunma ifadesi kaldırılmış',
      );
      expect(
        RegExp(
          r'(yedek|backup)[^.]{0,80}(READY|korundu|silinmedi)',
          caseSensitive: false,
        ).hasMatch(flat),
        isTrue,
        reason: 'yedeklerin korunduğu yazılmalı',
      );
      expect(flat, contains('Net kalıcı drill kaynağı: yok'));
    });

    test('yasaklı hassas tanımlayıcı HİÇBİR belgede yok', () {
      final forbidden = <String, RegExp>{
        'UUID (database uid / backup / operation kimliği)': RegExp(
          r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        ),
        'tam backup/operation kaynak adı':
            RegExp(r'projects/[^\s`]*/(backups|operations)/\S'),
        'e-posta adresi':
            RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
        'billing account kimliği':
            RegExp(r'\b[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}\b'),
        'quota/consumer proje numarası': RegExp(r'\b\d{9,}\b'),
        'yerel dosya yolu': RegExp(r'(/Users/|/home/|/private/tmp)'),
        'credential veya token': RegExp(
          r'(AIza[0-9A-Za-z_\-]{20,}|ya29\.|BEGIN [A-Z ]*PRIVATE KEY'
          r'|Bearer\s+[A-Za-z0-9._-]{10,})',
        ),
      };
      for (final doc in {
        _evidencePath: evidence,
        'docs/RELEASE-RUNBOOK.md': runbook,
      }.entries) {
        for (final rule in forbidden.entries) {
          final hit = rule.value.firstMatch(doc.value);
          expect(
            hit,
            isNull,
            reason: '${doc.key}: ${rule.key} → "${hit?.group(0)}"',
          );
        }
      }
    });

    test('redakte edilen kimlikler AÇIKÇA işaretli', () {
      expect(evidence, contains('redacted'));
      expect(
        RegExp(r'(sanitize|veri minimizasyonu)', caseSensitive: false)
            .hasMatch(evidence),
        isTrue,
      );
      expect(
        RegExp(r'UID[^\n]{0,40}\*\*farklı\*\*').hasMatch(evidence),
        isTrue,
        reason: 'UID\'ler yazılmadan "farklı" olduğu belirtilmeli',
      );
    });

    test('ölçülen süre SLA gibi sunulmuyor', () {
      for (final doc in {'runbook': runbook, 'kanıt': evidence}.entries) {
        final flat = _flat(doc.value);
        expect(flat, contains('16 dakika 56 saniye'));
        expect(
          RegExp(
            r'16 dakika 56 saniye.{0,400}(taahhüt değildir|SLA değildir|'
            r'tek bir gözlem)',
            caseSensitive: false,
          ).hasMatch(flat),
          isTrue,
          reason: '${doc.key}: süre garanti gibi sunuluyor',
        );
      }
    });
  });

  group('6C alarm işi TAMAMLANMIŞ gibi gösterilmiyor', () {
    test('yedek başarı alarmı ve notification channel YOK olarak yazılı', () {
      final openRaw = _section(evidence, '## 11. Açık kalan işler');
      final open = _flat(openRaw);
      expect(
        RegExp(r'alarm[^\n]{0,60}\*\*YOK', caseSensitive: false)
            .hasMatch(openRaw),
        isTrue,
        reason: 'yedek alarmı eksik olarak yazılmalı',
      );
      expect(
        RegExp(r'[Nn]otification channel[^\n]{0,60}\*\*YOK').hasMatch(openRaw),
        isTrue,
      );
      expect(open, contains('6C'));
      expect(
        RegExp(r'sessizce', caseSensitive: false).hasMatch(open),
        isTrue,
        reason: 'başarısız yedeğin sessizce kaybolduğu yazılmalı',
      );
    });

    test('tatbikat açık işleri KAPATMIŞ gibi gösterilmiyor', () {
      expect(
        _flat(evidence),
        contains('Bu tatbikat, yukarıdaki işlerin hiçbirini kapatmamıştır'),
      );
      expect(
        RegExp(
          r'(yedek başarı alarmı|notification channel)[^.]{0,60}'
          r'(kuruldu|aktif|hazır|tamamlandı)',
          caseSensitive: false,
        ).hasMatch(_flat(evidence)),
        isFalse,
      );
    });

    test('Auth ve imzalama materyali DR kapsam dışı olarak kayıtlı', () {
      final open = _flat(_section(evidence, '## 11. Açık kalan işler'));
      expect(open, contains('Auth'));
      expect(
        RegExp(
          r'(signing key|imzalama materyali|provisioning profile)',
          caseSensitive: false,
        ).hasMatch(open),
        isTrue,
      );
      expect(
        RegExp(r'(Auth|imzalama)', caseSensitive: false)
            .hasMatch(_flat(runbook)),
        isTrue,
        reason: 'runbook bilinen sınırlarda da anmalı',
      );
    });
  });

  group('RPO / RTO / tatbikat sıklığı kararları kayıtlı', () {
    test('canlı yedekleme yapılandırması runbook\'ta', () {
      final section = _section(runbook, '## 4. Backup / RPO / RTO');
      final flat = _flat(section);
      for (final value in [
        '7 gün',
        '28 gün',
        'Pazar',
        'eur3',
      ]) {
        expect(flat, contains(value), reason: 'eksik değer: $value');
      }
      expect(
        RegExp(r'PITR[^\n]{0,30}\*\*Açık\*\*').hasMatch(section),
        isTrue,
        reason: 'PITR durumu güncellenmemiş',
      );
      // 6A\'daki "hiç yedek yok" ifadesi artık gerçek değil.
      expect(
        RegExp(r'\*\*hiç yedek yok\*\*').hasMatch(runbook),
        isFalse,
        reason: 'eski durum ifadesi güncellenmemiş',
      );
    });

    test('RTO/RPO hedefleri var ve SLA olarak sunulmuyor', () {
      final section = _section(runbook, '## 4. Backup / RPO / RTO');
      final flat = _flat(section);
      expect(flat, contains('≤ 4 saat'));
      expect(
        RegExp(r'RPO[^\n]{0,120}dakika hassasiyeti').hasMatch(section),
        isTrue,
        reason: 'PITR yolunun RPO\'su yazılmalı',
      );
      expect(
        RegExp(r'(snapshot|yedek)[^\n]{0,120}(başarı|başarılı)')
            .hasMatch(section),
        isTrue,
        reason: 'yedek yolunun RPO\'su snapshot başarısına bağlanmalı',
      );
      expect(
        RegExp(r'(garanti|SLA)[^.]{0,60}(değildir|DEĞİLDİR)').hasMatch(flat),
        isTrue,
        reason: 'hedefler ürün garantisi gibi sunuluyor',
      );
    });

    test('tatbikat sıklığı ve sonraki tarih ÖNERİ; otomasyon yok', () {
      final flat = _flat(_section(runbook, '## 4. Backup / RPO / RTO'));
      expect(flat, contains('6 haftada bir'));
      expect(flat, contains('2026-09-14'));
      expect(flat, contains('2026-10-26'));
      expect(
        RegExp(
          r'(otomasyon|zamanlanmış görev)[^.]{0,60}kurulmamış',
          caseSensitive: false,
        ).hasMatch(flat),
        isTrue,
        reason: 'var olmayan otomasyon ima ediliyor',
      );
    });

    test('runbook durumu artık "hiçbir canlı adım uygulanmadı" DEMİYOR', () {
      expect(
        _flat(runbook),
        isNot(contains('hiçbir canlı adım henüz uygulanmadı')),
        reason: '6B1/6B2 canlıda uygulandı; durum satırı yanlış',
      );
      expect(
        RegExp(r'§4[–-]§5[^|]{0,80}canlıda uygulandı').hasMatch(_flat(runbook)),
        isTrue,
      );
    });

    test('kanıt belgesi runbook\'tan bağlanıyor', () {
      expect(runbook, contains('RESTORE-DRILL-2026-09-14.md'));
      expect(
        File(_evidencePath).existsSync(),
        isTrue,
        reason: 'bağlanan kanıt belgesi yok',
      );
    });
  });
}
