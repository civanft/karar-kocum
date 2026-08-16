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
