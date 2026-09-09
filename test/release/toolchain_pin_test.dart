import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// İŞ PAKETİ 6A — TOOLCHAIN VE SÜRÜM SÖZLEŞMELERİ.
///
/// Flutter sürümü için repoda TEK bir makine-okunur kaynak vardır.
/// İkinci bir sabit tutmak, birinin güncellenip diğerinin unutulduğu
/// sessiz sürüm kaymasına yol açar.
void main() {
  late String flutterVersion;
  late String workflow;
  late String pubspec;

  setUpAll(() {
    flutterVersion = File('.flutter-version').readAsStringSync();
    workflow = File('.github/workflows/ci.yaml').readAsStringSync();
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  group('Flutter sürümü tek kaynak', () {
    test('.flutter-version mevcut ve KATI semver', () {
      expect(
        RegExp(r'^\d+\.\d+\.\d+$').hasMatch(flutterVersion.trim()),
        isTrue,
        reason: 'beklenmeyen biçim build\'i durdurmalı',
      );
    });

    test('dosya tek satır ve boş DEĞİL', () {
      final lines =
          flutterVersion.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines, hasLength(1));
    });

    test('CI sürümü DOSYADAN okur, sabit taşımaz', () {
      expect(workflow, contains('.flutter-version'));
      expect(
        workflow,
        contains(r'steps.flutter_version.outputs.version'),
        reason: 'SDK kurulumu okunan değeri kullanmalı',
      );
    });

    test('CI\'da İKİNCİ bir Flutter sürüm sabiti YOK', () {
      final version = flutterVersion.trim();
      expect(
        workflow.contains(version),
        isFalse,
        reason: 'workflow\'da hardcoded $version kaldı',
      );
      // Genel tarama: başka bir x.y.z Flutter pini sızmasın.
      expect(
        RegExp(r'flutter-version\s*:').hasMatch(workflow),
        isFalse,
        reason: 'ikinci bir flutter-version girdisi',
      );
    });

    test('CI seçilen sürümü LOG\'a yazar', () {
      expect(workflow, contains('Flutter SDK sürümü'));
    });

    test('sürüm okuma adımı FAIL-CLOSED', () {
      expect(workflow, contains('set -euo pipefail'));
      expect(workflow, contains('::error::'));
      expect(
        workflow,
        contains(r'^[0-9]+\.[0-9]+\.[0-9]+$'),
        reason: 'biçim doğrulaması olmadan boş değer sessizce geçer',
      );
    });
  });

  group('version / build number', () {
    test('pubspec sürümü <marketing>+<build> biçiminde', () {
      final match =
          RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull);
      expect(
        RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(match!.group(1)!),
        isTrue,
        reason: 'Android versionCode ve iOS CFBundleVersion buradan türer',
      );
    });

    test('build number POZİTİF tamsayı', () {
      final match =
          RegExp(r'^version:\s*\d+\.\d+\.\d+\+(\d+)$', multiLine: true)
              .firstMatch(pubspec);
      expect(int.parse(match!.group(1)!), greaterThan(0));
    });

    test('SHA-pinned GitHub Actions politikası GEVŞETİLMEDİ', () {
      final uses = RegExp(r'uses:\s*(\S+)')
          .allMatches(workflow)
          .map((m) => m.group(1)!)
          .where((u) => !u.startsWith('./'))
          .toList();
      expect(uses, isNotEmpty);
      for (final action in uses) {
        expect(
          RegExp(r'@[0-9a-f]{40}$').hasMatch(action),
          isTrue,
          reason: 'tam SHA ile pinlenmemiş aksiyon: $action',
        );
      }
    });
  });
}
