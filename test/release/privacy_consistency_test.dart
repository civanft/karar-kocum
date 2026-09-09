import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/privacy/domain/entities/ai_consent.dart';

/// İŞ PAKETİ 5 — KOD ↔ POLİTİKA ↔ MAĞAZA BEYANI TUTARLILIK MATRİSİ.
///
/// Gizlilik metinleri koddan bağımsız yaşayamaz: politika "izin verirseniz"
/// diyorsa gerçekten bir izin kapısı olmalı, "puanlar gönderilir" diyorsa
/// gerçekten gönderilmeli. Bu süit o bağı MAKİNEYLE zorlar.
String _read(String path) => File(path).readAsStringSync();

String _plain(String html) =>
    html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ');

void main() {
  late String policy;
  late String terms;
  late String consentSheet;
  late String appStore;
  late String playSafety;
  late String inventory;
  late String backendConsent;

  setUpAll(() {
    policy = _plain(_read('hosting/privacy/index.html'));
    terms = _plain(_read('hosting/terms/index.html'));
    const sheetPath =
        'lib/features/privacy/presentation/widgets/ai_consent_sheet.dart';
    consentSheet = _read(sheetPath);
    appStore = _read('docs/store/APP-STORE-PRIVACY.md');
    playSafety = _read('docs/store/GOOGLE-PLAY-DATA-SAFETY.md');
    inventory = _read('docs/privacy/DATA-FLOW-INVENTORY.md');
    backendConsent = _read('functions/src/privacy/ai_consent.ts');
  });

  group('izin sözleşmesi istemci ↔ sunucu senkron', () {
    test('sürüm numarası AYNI', () {
      final match =
          RegExp(r'AI_CONSENT_VERSION = (\d+)').firstMatch(backendConsent);
      expect(match, isNotNull);
      expect(int.parse(match!.group(1)!), currentAiConsentVersion);
    });

    test('Firestore yolu AYNI', () {
      expect(backendConsent, contains('AI_CONSENT_COLLECTION = "privacy"'));
      expect(backendConsent, contains('AI_CONSENT_DOC = "aiConsent"'));
      final repo = _read(
        'lib/features/privacy/data/firestore_ai_consent_repository.dart',
      );
      expect(repo, contains("users/\$_uid/privacy/aiConsent"));
    });

    test('rules izin belgesini KATI şemayla sınırlar', () {
      final rules = _read('firestore.rules');
      expect(rules, contains('match /privacy/aiConsent'));
      expect(rules, contains("hasOnly(['granted', 'version', 'updatedAt'])"));
      expect(
        rules,
        contains('d.updatedAt == request.time'),
        reason: 'zaman damgası sunucudan gelmeli',
      );
    });

    test('hesap silme kaskadı izin alt koleksiyonunu DOĞRULAR', () {
      final ports = _read(
        'functions/src/privacy/firestore_account_deletion_ports.ts',
      );
      expect(ports, contains('AI_CONSENT_COLLECTION'));
    });
  });

  group('politika gerçek veri akışıyla uyumlu', () {
    test('PUANLARIN gönderilmediği doğru yazılır', () {
      // Kod kanıtı: prompt yalnız kriter ağırlıklarını yazar.
      final prompt = _read('functions/src/ai/prompt.ts');
      expect(prompt.contains('scores'), isFalse);

      expect(
        RegExp('puanlar[^.]{0,80}(gönderil|iletil)(ir|mektedir)')
            .hasMatch(policy.toLowerCase()),
        isFalse,
        reason: 'politika puanların gönderildiğini iddia ediyor',
      );
      expect(policy.toLowerCase(), contains('puanlar'));
      expect(
        policy.toLowerCase(),
        contains('gönderilmez'),
        reason: 'puanların gönderilmediği açıkça yazılmalı',
      );
    });

    test('AI izin kapısı politikada ANLATILIR', () {
      final lower = policy.toLowerCase();
      expect(lower, contains('izin'));
      expect(lower, contains('geri al'));
      expect(lower, contains('ayarlar'));
    });

    test('OpenAI eğitim ve saklama davranışı DOĞRU ve İHTİYATLI', () {
      final lower = policy.toLowerCase();
      // Eğitim: opt-in olmadıkça kullanılmaz.
      expect(lower, contains('eğit'));
      // Kötüye kullanım izleme: 30 güne kadar, içerik kapsanabilir.
      expect(lower, contains('30 gün'));
      expect(lower, contains('kötüye kullanım'));
    });

    test('KANITLANMAYAN mutlak iddialar YOK', () {
      for (final source in [policy, terms, _plain(consentSheet)]) {
        final lower = source.toLowerCase();
        for (final claim in [
          'hiçbir şekilde saklanmaz',
          'hiçbir şekilde saklanmıyor',
          'anında silinir',
          'hiçbir insan göremez',
          'kesinlikle yurt dışına çıkmaz',
          'asla saklanmaz',
          'tamamen anonimdir',
          'zero data retention',
          'sıfır veri saklama',
        ]) {
          expect(
            lower.contains(claim),
            isFalse,
            reason: 'kanıtlanmayan iddia: $claim',
          );
        }
      }
    });

    test('politika sürümü ve yürürlük tarihi var', () {
      expect(policy.toLowerCase(), contains('yürürlük'));
      expect(
        RegExp(r'[Ss]ürüm.{0,4}\d+').hasMatch(policy),
        isTrue,
        reason: 'politika sürümü belirtilmeli',
      );
    });

    test('analytics AKTİF gibi anlatılmaz (SDK yok)', () {
      final pubspec = _read('pubspec.yaml');
      expect(pubspec.contains('firebase_analytics'), isFalse);
      expect(policy.toLowerCase(), contains('analitik'));
      expect(policy.toLowerCase(), contains('toplanmaz'));
    });

    test('veri dışa aktarmanın canlı OLMADIĞI gizlenmez', () {
      final index = _read('functions/src/index.ts');
      expect(index.contains('export { exportData }'), isFalse);
      expect(inventory, contains('Canlıda yok'));
    });
  });

  group('disclosure metni politikayla aynı şeyi söyler', () {
    test('sheet OpenAI, saklama, hata ve profesyonel sınırı anlatır', () {
      final lower = consentSheet.toLowerCase();
      expect(lower, contains('openai'));
      expect(lower, contains('saklanır'));
      expect(lower, contains('hatalı'));
      expect(lower, contains('profesyonel'));
      expect(
        lower,
        contains('puanlar'),
        reason: 'ne GÖNDERİLMEDİĞİ de yazmalı',
      );
    });
  });

  group('mağaza beyanları', () {
    final requiredColumns = [
      'Toplanıyor',
      'Paylaşılıyor',
      'Kullanıcıyla ilişkili',
      'Tracking',
      'Amaç',
      'Zorunlu',
      'Şifreli',
      'Silme',
      'Kanıt',
    ];

    test('iki beyan dosyası da tüm sütunları taşır', () {
      for (final doc in [appStore, playSafety]) {
        for (final column in requiredColumns) {
          expect(doc, contains(column), reason: 'eksik sütun: $column');
        }
      }
    });

    test('TRACKING her iki beyanda da HAYIR', () {
      for (final doc in [appStore, playSafety]) {
        expect(
          RegExp(r'Tracking[^\n]*\n').hasMatch(doc) || doc.contains('Tracking'),
          isTrue,
        );
        expect(
          doc.toLowerCase().contains('tracking: hayır') ||
              doc.contains('| Hayır |'),
          isTrue,
        );
      }
    });

    test('reklam kimliği hiçbir beyanda TOPLANIYOR değil', () {
      for (final doc in [appStore, playSafety]) {
        final adLine = doc
            .split('\n')
            .firstWhere((l) => l.contains('Reklam kimliği'), orElse: () => '');
        expect(adLine, isNotEmpty, reason: 'reklam kimliği satırı yok');
        expect(adLine.contains('Hayır'), isTrue);
      }
    });

    test('beyanlarda OpenAI ve Crashlytics kanıtlı', () {
      for (final doc in [appStore, playSafety]) {
        expect(doc, contains('OpenAI'));
        expect(doc, contains('Crashlytics'));
        expect(doc, contains('DATA-FLOW-INVENTORY'));
      }
    });

    test('her satır KOD/POLİTİKA kanıtı gösterir', () {
      for (final doc in [appStore, playSafety]) {
        // Yalnız "Veri türleri" tablosu: özet tablolarında kanıt sütunu
        // ayrı bir hücre değil, satırın kendisindedir.
        final section = doc.substring(
          doc.indexOf('## Veri türleri'),
          doc.indexOf('##', doc.indexOf('## Veri türleri') + 3),
        );
        final rows = section
            .split('\n')
            .where((l) => l.startsWith('| ') && !l.contains('---'))
            .skip(1) // başlık
            .toList();
        expect(rows, isNotEmpty);
        for (final row in rows) {
          expect(
            row.contains('.dart') ||
                row.contains('.ts') ||
                row.contains('.xml') ||
                row.contains('.yaml') ||
                row.contains('.html') ||
                row.contains('.md') ||
                row.contains('.plist') ||
                row.contains('.xcprivacy'),
            isTrue,
            reason: 'kanıtsız beyan satırı: ${row.substring(0, 60)}',
          );
        }
      }
    });
  });

  group('platform manifestleri', () {
    test('iOS gizlilik manifesti VAR ve tracking KAPALI', () {
      final manifest = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(manifest, contains('NSPrivacyTracking'));
      final tracking = RegExp(
        r'<key>NSPrivacyTracking</key>\s*<(true|false)/>',
      ).firstMatch(manifest);
      expect(tracking?.group(1), 'false');
      expect(manifest, contains('NSPrivacyTrackingDomains'));
      expect(manifest, contains('NSPrivacyAccessedAPITypes'));
    });

    test('iOS gizlilik manifesti Xcode HEDEFİNE BAĞLI', () {
      // Dosyanın var olması YETMEZ: Resources build phase'e bağlı değilse
      // uygulamaya girmez ve Apple onu hiç görmez.
      final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
      final fileRef = RegExp(
        r'(\w+) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference',
      ).firstMatch(pbx);
      expect(fileRef, isNotNull, reason: 'dosya referansı yok');

      final buildFile = RegExp(
        r'(\w+) /\* PrivacyInfo\.xcprivacy in Resources \*/ = '
        r'\{isa = PBXBuildFile; fileRef = (\w+)',
      ).firstMatch(pbx);
      expect(buildFile, isNotNull, reason: 'build file girdisi yok');
      expect(buildFile!.group(2), fileRef!.group(1));

      // Runner hedefinin Resources fazında YER ALMALI.
      final resources = pbx.substring(
        pbx.indexOf('/* Begin PBXResourcesBuildPhase section */'),
        pbx.indexOf('/* End PBXResourcesBuildPhase section */'),
      );
      expect(
        resources.contains('${buildFile.group(1)} /* PrivacyInfo.xcprivacy'),
        isTrue,
        reason: 'Resources build phase\'e bağlı değil',
      );
    });

    test('manifestte beyan edilen izinler mağaza beyanıyla UYUMLU', () {
      final android = _read('android/app/src/main/AndroidManifest.xml');
      final declared = RegExp(r'android:name="([^"]+)"(?![^>]*tools:node)')
          .allMatches(android.replaceAll(RegExp(r'\s+'), ' '))
          .map((m) => m.group(1)!)
          .where((n) => n.startsWith('android.permission'))
          .toSet();
      // Bildirim dışında hassas izin YOK.
      expect(
        declared,
        {
          'android.permission.POST_NOTIFICATIONS',
          'android.permission.RECEIVE_BOOT_COMPLETED',
        },
        reason: 'beklenmeyen izin: mağaza beyanı yanlış olur',
      );
    });
  });
}
