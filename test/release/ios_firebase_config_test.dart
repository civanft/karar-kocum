import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// İŞ PAKETİ 6A — iOS FIREBASE BUILD CONFIGURATION SÖZLEŞMESİ.
///
/// Eskiden `firebase.json` yalnız `Release` build configuration'ı
/// tanımlıyordu ve `Runner/GoogleService-Info.plist` doğrudan Xcode
/// Resources phase'ine bağlıydı. Bunun iki sonucu vardı:
///
///  1. `flutterfire upload-crashlytics-symbols` Debug'da `null` config'i
///     `Map<String, dynamic>`'e cast edip `FirebaseJsonException` fırlatıyor
///     ve simulator build'ini DÜŞÜRÜYORDU.
///  2. Resources phase (5) FlutterFire script'inden (9) ÖNCE çalıştığı için
///     aynı dosya iki kez kopyalanıyordu; script atlanır/başarısız olursa
///     Release paketine DEVELOPMENT plist'i sızabilirdi.
///
/// Bu testler o iki hatanın geri gelmesini engeller.
Map<String, dynamic> _iosConfig() {
  final json = jsonDecode(File('firebase.json').readAsStringSync())
      as Map<String, dynamic>;
  final flutter = json['flutter']! as Map<String, dynamic>;
  final platforms = flutter['platforms']! as Map<String, dynamic>;
  return platforms['ios']! as Map<String, dynamic>;
}

/// Plist'ten TEK bir anahtarı okur. Değerler rapora BASILMAZ; yalnız
/// karşılaştırma için kullanılır.
String? _plistValue(String path, String key) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final source = file.readAsStringSync();
  final match = RegExp(
    '<key>$key</key>\\s*<string>([^<]*)</string>',
  ).firstMatch(source);
  return match?.group(1);
}

const _devProject = 'karar-veriyorum-dev';
const _prodProject = 'karar-kocum-production';
const _devPlist = 'ios/Runner/Firebase/Development/GoogleService-Info.plist';
const _prodPlist = 'ios/Runner/Firebase/Production/GoogleService-Info.plist';

void main() {
  late Map<String, dynamic> ios;
  late Map<String, dynamic> configs;
  late String pbx;

  setUpAll(() {
    ios = _iosConfig();
    configs = ios['buildConfigurations']! as Map<String, dynamic>;
    pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  });

  group('build configuration → ortam eşlemesi', () {
    test('Xcode\'daki HER build configuration eşlenmiş', () {
      final inXcode = RegExp(r'name = (Debug|Profile|Release);')
          .allMatches(pbx)
          .map((m) => m.group(1)!)
          .toSet();
      expect(inXcode, {'Debug', 'Profile', 'Release'});
      expect(
        configs.keys.toSet(),
        inXcode,
        reason: 'eşlenmemiş configuration build\'i düşürür',
      );
    });

    test('Debug → DEVELOPMENT projesi', () {
      final debug = configs['Debug']! as Map<String, dynamic>;
      expect(debug['projectId'], _devProject);
      expect(debug['fileOutput'], _devPlist);
    });

    test('Profile → DEVELOPMENT projesi', () {
      final profile = configs['Profile']! as Map<String, dynamic>;
      expect(profile['projectId'], _devProject);
      expect(profile['fileOutput'], _devPlist);
    });

    test('Release → PRODUCTION projesi', () {
      final release = configs['Release']! as Map<String, dynamic>;
      expect(release['projectId'], _prodProject);
      expect(release['fileOutput'], _prodPlist);
    });

    test('Debug/Profile production plist\'ini KULLANAMAZ', () {
      for (final name in ['Debug', 'Profile']) {
        final config = configs[name]! as Map<String, dynamic>;
        expect(config['fileOutput'], isNot(_prodPlist), reason: name);
        expect(config['projectId'], isNot(_prodProject), reason: name);
      }
    });

    test('Release development plist\'ini KULLANAMAZ', () {
      final release = configs['Release']! as Map<String, dynamic>;
      expect(release['fileOutput'], isNot(_devPlist));
      expect(release['projectId'], isNot(_devProject));
    });

    test('hiçbir config İZLENMEYEN eski yolu göstermez', () {
      final outputs = [
        ios['default']!,
        ...configs.values,
      ].map((c) => (c! as Map<String, dynamic>)['fileOutput']).toList();
      expect(
        outputs.contains('ios/Runner/GoogleService-Info.plist'),
        isFalse,
        reason: 'gitignore\'lu dosyaya referans temiz clone\'u kırar',
      );
    });
  });

  group('plist dosyaları izlenebilir ve DOĞRU ortamda', () {
    test('her iki plist de repoda MEVCUT', () {
      expect(File(_devPlist).existsSync(), isTrue, reason: _devPlist);
      expect(File(_prodPlist).existsSync(), isTrue, reason: _prodPlist);
    });

    test('plist içerikleri beyan edilen projeyle UYUŞUR', () {
      expect(_plistValue(_devPlist, 'PROJECT_ID'), _devProject);
      expect(_plistValue(_prodPlist, 'PROJECT_ID'), _prodProject);
    });

    test('GOOGLE_APP_ID firebase.json ile UYUŞUR', () {
      expect(
        _plistValue(_devPlist, 'GOOGLE_APP_ID'),
        (configs['Debug']! as Map<String, dynamic>)['appId'],
      );
      expect(
        _plistValue(_prodPlist, 'GOOGLE_APP_ID'),
        (configs['Release']! as Map<String, dynamic>)['appId'],
      );
    });

    test('BUNDLE_ID Xcode hedefiyle UYUŞUR', () {
      final bundleId = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);')
          .allMatches(pbx)
          .map((m) => m.group(1)!)
          .firstWhere((id) => !id.endsWith('RunnerTests'));
      expect(_plistValue(_devPlist, 'BUNDLE_ID'), bundleId);
      expect(_plistValue(_prodPlist, 'BUNDLE_ID'), bundleId);
    });

    test('plist\'ler yalnız PUBLIC client config taşır', () {
      for (final path in [_devPlist, _prodPlist]) {
        final source = File(path).readAsStringSync();
        for (final forbidden in [
          'BEGIN PRIVATE KEY',
          'private_key',
          'client_email',
          'service_account',
          'refresh_token',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$path içinde credential materyali: $forbidden',
          );
        }
      }
    });

    test('development ve production yapılandırmaları KARIŞMAMIŞ', () {
      expect(
        _plistValue(_devPlist, 'PROJECT_ID'),
        isNot(_plistValue(_prodPlist, 'PROJECT_ID')),
      );
      expect(
        _plistValue(_devPlist, 'GOOGLE_APP_ID'),
        isNot(_plistValue(_prodPlist, 'GOOGLE_APP_ID')),
      );
    });
  });

  group('Xcode: TEK kopyalama kaynağı', () {
    test('Resources phase artık plist KOPYALAMIYOR', () {
      final resources = pbx.substring(
        pbx.indexOf('/* Begin PBXResourcesBuildPhase section */'),
        pbx.indexOf('/* End PBXResourcesBuildPhase section */'),
      );
      expect(
        resources.contains('GoogleService-Info.plist'),
        isFalse,
        reason: 'Resources phase FlutterFire script\'inden ÖNCE çalışır; '
            'çift kopyalama yanlış ortam plist\'i bırakabilir',
      );
    });

    test('proje dosyasında ORPHAN plist referansı yok', () {
      expect(pbx.contains('GoogleService-Info.plist'), isFalse);
    });

    test('FlutterFire bundle script\'i MEVCUT (tek kaynak)', () {
      expect(pbx, contains('flutterfire bundle-service-file'));
      expect(pbx, contains(r'--build-configuration=${CONFIGURATION}'));
    });

    test('PrivacyInfo.xcprivacy hedef bağlantısı KORUNDU', () {
      final fileRef = RegExp(
        r'(\w+) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference',
      ).firstMatch(pbx);
      expect(fileRef, isNotNull);
      final buildFile = RegExp(
        r'(\w+) /\* PrivacyInfo\.xcprivacy in Resources \*/ = '
        r'\{isa = PBXBuildFile; fileRef = (\w+)',
      ).firstMatch(pbx);
      expect(buildFile, isNotNull);
      expect(buildFile!.group(2), fileRef!.group(1));
      final resources = pbx.substring(
        pbx.indexOf('/* Begin PBXResourcesBuildPhase section */'),
        pbx.indexOf('/* End PBXResourcesBuildPhase section */'),
      );
      expect(
        resources.contains('${buildFile.group(1)} /* PrivacyInfo.xcprivacy'),
        isTrue,
      );
    });
  });

  group('uygulama kimlikleri bu PR\'da DEĞİŞMEDİ', () {
    test('iOS bundle id ve Android applicationId sabit', () {
      const bundleLine =
          'PRODUCT_BUNDLE_IDENTIFIER = com.kararveriyorum.kararVeriyorum;';
      expect(pbx, contains(bundleLine));
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(
        gradle,
        contains('applicationId = "com.kararveriyorum.karar_veriyorum"'),
      );
    });
  });
}
