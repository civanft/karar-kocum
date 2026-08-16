import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS yayın yapılandırması sözleşmesi (AŞAMA 24B-1).
///
/// Bu test Firebase, emulator ya da Xcode ÇALIŞTIRMAZ; yalnız repository
/// dosyalarının sözleşmesini denetler. Amaç, iOS build'ini kıran iki
/// yapılandırma hatasının sessizce geri gelmesini engellemek:
///
///  1. FlutterFire'ın Crashlytics symbol-upload fazı, Flutter'ın SPM
///     yerleşimini (BUILD_DIR/SourcePackages) tanımayıp yalnız DerivedData
///     yoluna bakarsa `flutter build ios` PhaseScriptExecution ile düşer.
///  2. analyzer `build/**` dizinini hariç tutmazsa, iOS build'i alındıktan
///     sonra vendor kaynakları taranır ve `flutter analyze` binlerce sorun
///     bildirir.
void main() {
  group('FlutterFire Crashlytics build phase', () {
    late String script;

    setUpAll(() {
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
      expect(pbxproj.existsSync(), isTrue, reason: 'project.pbxproj yok');
      script = _crashlyticsShellScript(pbxproj.readAsStringSync());
    });

    test('faz projede tanımlı', () {
      expect(script, contains('flutterfire upload-crashlytics-symbols'));
    });

    test('CocoaPods yolunu destekler', () {
      expect(script, contains(r'$PODS_ROOT'));
      expect(script, contains('FirebaseCrashlytics/run'));
    });

    test('Flutter SPM yolunu (BUILD_DIR) destekler', () {
      // Flutter, SPM checkout'larını -clonedSourcePackagesDirPath ile
      // BUILD_DIR/SourcePackages altına koyar; DerivedData'da OLUŞMAZ.
      expect(
        _executableScript(script),
        contains(_buildDirCandidate),
        reason: 'BUILD_DIR tabanlı SPM yolu eksik',
      );
    });

    test('aday sırası: CocoaPods → BUILD_DIR → DerivedData', () {
      // YORUM SATIRLARI HARİÇ: script'in açıklama bloğu aynı yolları
      // gerçek aday listesinden ÖNCE andığı için, ham metin üzerinde
      // sıralama kontrolü false-positive üretir.
      final code = _executableScript(script);

      final podsAt = code.indexOf(_podsCandidate);
      final buildDirAt = code.indexOf(_buildDirCandidate);
      final derivedAt = code.indexOf(_derivedDataCandidate);

      expect(podsAt, greaterThan(-1), reason: 'CocoaPods adayı yok');
      expect(buildDirAt, greaterThan(-1), reason: 'BUILD_DIR adayı yok');
      expect(derivedAt, greaterThan(-1), reason: 'DerivedData adayı yok');

      expect(
        podsAt,
        lessThan(buildDirAt),
        reason: 'CocoaPods adayı BUILD_DIR\'dan ÖNCE denenmeli',
      );
      expect(
        buildDirAt,
        lessThan(derivedAt),
        reason: 'BUILD_DIR adayı DerivedData\'dan ÖNCE denenmeli',
      );
    });

    test('her adayı dosya olarak denetler', () {
      expect(
        _executableScript(script),
        contains(r'[ -f "$CANDIDATE" ]'),
        reason: 'dosya varlık kontrolü olmadan yanlış yol seçilebilir',
      );
    });

    test('bulunamazsa sessiz geçmez, açık hata üretir', () {
      expect(
        _executableScript(script),
        contains('exit 1'),
        reason: 'script bulunamadığında build başarılı sayılmamalı',
      );
    });

    test('simulator için KOŞULSUZ devre dışı bırakılmamış', () {
      // "iphonesimulator ise exit 0" gibi bir kestirme kabul edilmez.
      final skipsSimulator = RegExp(
        r'iphonesimulator[\s\S]{0,80}exit\s+0',
      ).hasMatch(_executableScript(script));
      expect(
        skipsSimulator,
        isFalse,
        reason: 'Crashlytics fazı simulator\'da koşulsuz atlanmamalı',
      );
    });

    test('makineye özel mutlak yol içermez', () {
      expect(script, isNot(contains('/Users/')));
    });
  });

  group('App Attest entitlement', () {
    late String pbxproj;

    setUpAll(() {
      pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    });

    test('Runner.entitlements dosyası mevcut', () {
      expect(
        File('ios/Runner/Runner.entitlements').existsSync(),
        isTrue,
        reason: 'App Attest entitlement dosyası yok',
      );
    });

    test('App Attest anahtarı ve production değeri tanımlı', () {
      final xml = File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(
        xml,
        contains('com.apple.developer.devicecheck.appattest-environment'),
        reason: 'App Attest entitlement anahtarı eksik',
      );
      // Firebase App Check sandbox token KABUL ETMEZ → değer production olmalı.
      final keyAt =
          xml.indexOf('com.apple.developer.devicecheck.appattest-environment');
      final after = xml.substring(keyAt);
      expect(
        after,
        contains('<string>production</string>'),
        reason: 'App Attest ortamı production olmalı',
      );
      expect(
        after.substring(0, after.indexOf('</dict>')),
        isNot(contains('<string>development</string>')),
        reason: 'development ortamı Firebase tarafından reddedilir',
      );
    });

    test('Runner\'ın üç configuration\'ı entitlements kullanır', () {
      final runnerConfigs = _targetConfigurations(pbxproj, 'Runner');
      expect(runnerConfigs.keys, containsAll(['Debug', 'Profile', 'Release']));
      for (final entry in runnerConfigs.entries) {
        expect(
          entry.value,
          contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
          reason: '${entry.key} configuration entitlements bağlamıyor',
        );
      }
    });

    test('CODE_SIGN_ENTITLEMENTS tam 3 kez tanımlı', () {
      final count = RegExp('CODE_SIGN_ENTITLEMENTS').allMatches(pbxproj).length;
      expect(count, 3, reason: 'yalnız Runner\'ın 3 config\'i bağlamalı');
    });

    test('RunnerTests entitlement BAĞLAMAZ', () {
      for (final body in _targetConfigurations(pbxproj, 'RunnerTests').values) {
        expect(body, isNot(contains('CODE_SIGN_ENTITLEMENTS')));
      }
    });

    test('entitlements dosyası Xcode projesine kayıtlı', () {
      expect(
        pbxproj,
        contains('Runner.entitlements'),
        reason: 'PBXFileReference yok; Xcode dosyayı göstermez',
      );
    });

    test('bundle ID ve Team ID değişmemiş', () {
      expect(
        RegExp('PRODUCT_BUNDLE_IDENTIFIER = com.kararveriyorum.kararVeriyorum;')
            .allMatches(pbxproj)
            .length,
        3,
      );
      expect(
        RegExp('DEVELOPMENT_TEAM = SXD4YLW556;').allMatches(pbxproj).length,
        6,
      );
    });
  });

  group('iOS deployment target', () {
    test('uygulama ve CocoaPods minimum iOS 14 kullanır', () {
      final podfile = File('ios/Podfile').readAsStringSync();
      final pbxproj =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      expect(
        podfile,
        contains("platform :ios, '14.0'"),
        reason: 'App Attest için minimum platform iOS 14 olmalı',
      );
      expect(
        RegExp('IPHONEOS_DEPLOYMENT_TARGET = 14.0;').allMatches(pbxproj).length,
        3,
        reason: 'Xcode proje yapılandırmalarının üçü de iOS 14 olmalı',
      );
      expect(
        podfile,
        contains(
          "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'",
        ),
        reason: 'Pod hedefleri eski iOS sürümüne geri düşmemeli',
      );
    });

    test('iOS 14 altı deployment target kalmaz', () {
      final files = [
        File('ios/Podfile').readAsStringSync(),
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      ].join('\n');

      expect(files, isNot(contains("platform :ios, '13.0'")));
      expect(files, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')));
    });
  });

  group('analyzer yapılandırması', () {
    test('build/** analyzer exclude listesinde', () {
      final yaml = File('analysis_options.yaml').readAsStringSync();
      final analyzerBlock = yaml.substring(yaml.indexOf('analyzer:'));
      expect(
        analyzerBlock,
        contains('build/**'),
        reason: 'iOS build sonrası vendor kaynakları analyze edilmemeli',
      );
    });

    test('mevcut exclude kuralları korunur', () {
      final yaml = File('analysis_options.yaml').readAsStringSync();
      for (final keep in [
        '**/*.g.dart',
        '**/*.freezed.dart',
        'lib/firebase_options*.dart',
      ]) {
        expect(yaml, contains(keep), reason: '$keep exclude listesinden düştü');
      }
    });
  });
}

/// Aday yollar — script'te birebir bu biçimde geçmeli.
const _podsCandidate = r'"$PODS_ROOT/FirebaseCrashlytics/run"';
const _buildDirCandidate =
    r'"$BUILD_DIR/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"';
const _derivedDataCandidate =
    r'"$DERIVED_DATA_PATH/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"';

/// Script'in YALNIZ çalıştırılabilir satırları (yorumlar atılır).
///
/// Açıklama bloğu aynı yolları gerçek aday listesinden önce andığı için,
/// sıralama kontrolleri ham metin üzerinde yapılamaz.
String _executableScript(String script) => script
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('#'))
    .join('\n');

/// pbxproj içindeki FlutterFire fazının shellScript değerini çözer.
String _crashlyticsShellScript(String pbxproj) {
  const marker = 'flutterfire upload-crashlytics-symbols';
  final matches = RegExp(r'shellScript = "((?:[^"\\]|\\.)*)";')
      .allMatches(pbxproj)
      .map((m) => m.group(1)!)
      .where((s) => s.contains(marker));
  expect(matches, isNotEmpty, reason: 'FlutterFire Crashlytics fazı YOK');
  return _unescape(matches.first);
}

String _unescape(String raw) =>
    raw.replaceAll(r'\n', '\n').replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

/// Verilen native target'ın configuration adı → gövde eşlemesi.
Map<String, String> _targetConfigurations(String pbxproj, String target) {
  final configs = <String, String>{};
  final bodies = <String, String>{};
  for (final m in RegExp(
    r'([0-9A-F]{24}) /\* (\w+) \*/ = \{\s*isa = XCBuildConfiguration;([\s\S]*?)\n\t\t\};',
  ).allMatches(pbxproj)) {
    bodies[m.group(1)!] = m.group(3)!;
    configs[m.group(1)!] = m.group(2)!;
  }
  final listMatch = RegExp(
    'Build configuration list for PBXNativeTarget "$target" '
    r'\*/ = \{\s*isa = XCConfigurationList;\s*buildConfigurations = \(([\s\S]*?)\);',
  ).firstMatch(pbxproj);
  expect(listMatch, isNotNull, reason: '$target configuration listesi yok');
  final result = <String, String>{};
  for (final m in RegExp(r'([0-9A-F]{24}) /\* (\w+) \*/')
      .allMatches(listMatch!.group(1)!)) {
    result[m.group(2)!] = bodies[m.group(1)!] ?? '';
  }
  return result;
}
