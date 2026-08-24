import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PR-PROD-2 — release artifact'ının Firebase kimliği sözleşmesi.
///
/// Firebase BAŞLATILMAZ, ağ isteği yapılmaz: yalnız repodaki yapılandırma
/// dosyaları denetlenir. Assertion'lar YALNIZ public kimlikleri (project id,
/// app id, package/bundle id) karşılaştırır — anahtar veya dosya içeriği
/// hiçbir mesaja girmez.
const _devProject = 'karar-veriyorum-dev';
const _prodProject = 'karar-kocum-production';

void main() {
  group('Android', () {
    test('release flavor production projesine bağlı', () {
      final json = _readJson('android/app/src/release/google-services.json');
      expect(_projectId(json), _prodProject);
      expect(
        _packageNames(json),
        contains('com.kararveriyorum.karar_veriyorum'),
      );
    });

    test('varsayılan (debug/dev) config dev projesinde KALIR', () {
      expect(
        _projectId(_readJson('android/app/google-services.json')),
        _devProject,
      );
    });

    test('release ve varsayılan config farklı projelere bakar', () {
      expect(
        _projectId(_readJson('android/app/src/release/google-services.json')),
        isNot(_projectId(_readJson('android/app/google-services.json'))),
      );
    });
  });

  group('iOS', () {
    const prodPlist = 'ios/Runner/Firebase/Production/GoogleService-Info.plist';
    const devPlist = 'ios/Runner/GoogleService-Info.plist';

    test('Release build configuration production projesine bağlı', () {
      expect(_plistValue(prodPlist, 'PROJECT_ID'), _prodProject);
      expect(
        _plistValue(prodPlist, 'BUNDLE_ID'),
        'com.kararveriyorum.kararVeriyorum',
      );
    });

    test('varsayılan (debug/dev) plist dev projesinde KALIR', () {
      expect(_plistValue(devPlist, 'PROJECT_ID'), _devProject);
    });

    test('Xcode projesi doğru plist\'i kopyalayan fazı içerir', () {
      final pbxproj =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(
        pbxproj,
        contains('flutterfire bundle-service-file'),
        reason: 'faz yoksa release build dev plist ile paketlenir',
      );
      expect(
        pbxproj,
        contains(r'--build-configuration=${CONFIGURATION}'),
        reason: 'build configuration geçilmezse yanlış proje seçilir',
      );
    });
  });

  group('firebase.json eşlemesi', () {
    late Map<String, dynamic> flutter;

    setUpAll(() {
      final root = _readJson('firebase.json');
      flutter = (root['flutter'] as Map<String, dynamic>)['platforms']
          as Map<String, dynamic>;
    });

    test('varsayılan platform hedefleri hâlâ dev', () {
      for (final platform in ['android', 'ios']) {
        final p = flutter[platform] as Map<String, dynamic>;
        expect(
          (p['default'] as Map)['projectId'],
          _devProject,
          reason: '$platform varsayılanı production\'a kaymış',
        );
      }
    });

    test('release build configuration\'ları production\'a bağlı', () {
      final android = (flutter['android'] as Map)['buildConfigurations'] as Map;
      final ios = (flutter['ios'] as Map)['buildConfigurations'] as Map;
      expect((android['src/release'] as Map)['projectId'], _prodProject);
      expect((ios['Release'] as Map)['projectId'], _prodProject);
    });
  });

  group('callable bölge sözleşmesi', () {
    test('lib/ içinde bölgesiz FirebaseFunctions.instance KALMADI', () {
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('///')) continue;
          if (RegExp(r'FirebaseFunctions\.instance\b(?!For)').hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'bölgesiz instance production europe-west1 callable\'ını '
            'bulamaz (not-found)',
      );
    });

    test('gerçek istemciler merkezi bölgeyi kullanır', () {
      for (final path in [
        'lib/features/ai_analysis/presentation/providers/analysis_providers.dart',
        'lib/features/settings/presentation/providers/settings_providers.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('functionsRegionProvider'),
          reason: '$path merkezi bölge seam\'ini kullanmıyor',
        );
        expect(
          source,
          contains('FirebaseFunctions.instanceFor'),
          reason: '$path bölge geçmiyor',
        );
      }
    });
  });
}

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

String _projectId(Map<String, dynamic> googleServices) =>
    (googleServices['project_info'] as Map<String, dynamic>)['project_id']
        as String;

List<String> _packageNames(Map<String, dynamic> googleServices) =>
    (googleServices['client'] as List)
        .map((c) => ((c as Map)['client_info'] as Map)['android_client_info'])
        .map((info) => (info as Map)['package_name'] as String)
        .toList();

/// Plist'ten YALNIZ istenen alanı çeker; dosya içeriği mesajlara girmez.
String _plistValue(String path, String key) {
  final xml = File(path).readAsStringSync();
  final match = RegExp(
    '<key>$key</key>\\s*<string>([^<]*)</string>',
  ).firstMatch(xml);
  expect(match, isNotNull, reason: '$key alanı $path içinde yok');
  return match!.group(1)!;
}
