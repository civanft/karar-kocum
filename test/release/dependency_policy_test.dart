import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PR-STORE-2 — v1 production SDK yüzeyi sözleşmesi.
///
/// "Dependency var" ile "runtime'da veri topluyor" farklı şeylerdir; ama
/// mağaza beyanı ve gizlilik manifestleri BUNDLE'a bakar. Kullanılmayan bir
/// SDK, binary'de olduğu için beyan yükümlülüğü ve inceleme riski doğurur.
/// Bu test yüzeyi sabitler.
const _forbidden = <String>[
  'firebase_analytics',
  'firebase_remote_config',
  'firebase_storage',
  'google_sign_in',
  'sign_in_with_apple',
  'purchases_flutter',
  'flutter_secure_storage',
  'cached_network_image',
  'dio',
  'pdf',
  'printing',
  'share_plus',
];

const _required = <String>[
  'firebase_core',
  'firebase_auth',
  'cloud_firestore',
  'cloud_functions',
  'firebase_crashlytics',
  'firebase_app_check',
  'flutter_local_notifications',
  'shared_preferences',
  'url_launcher',
  'flutter_riverpod',
  'go_router',
  'freezed_annotation',
  'json_annotation',
];

void main() {
  late String pubspec;

  setUpAll(() => pubspec = File('pubspec.yaml').readAsStringSync());

  group('pubspec bağımlılıkları', () {
    test('yasaklı SDK\'lar pubspec\'te YOK', () {
      for (final pkg in _forbidden) {
        expect(
          RegExp('^\\s{2}$pkg:', multiLine: true).hasMatch(pubspec),
          isFalse,
          reason: '$pkg v1 production yüzeyinde kalmamalı',
        );
      }
    });

    test('aktif SDK\'lar korunur', () {
      for (final pkg in _required) {
        expect(
          RegExp('^\\s{2}$pkg:', multiLine: true).hasMatch(pubspec),
          isTrue,
          reason: '$pkg düşmüş',
        );
      }
    });

    test('integration_test dev dependency olarak korunur', () {
      expect(pubspec, contains('integration_test:'));
    });
  });

  group('kaynak kod importları', () {
    test('lib/ yasaklı paketleri import ETMEZ', () {
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final pkg in _forbidden) {
          if (source.contains('package:$pkg/')) {
            offenders.add('${file.path} → $pkg');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('lockfile yasaklı paketleri doğrudan bağımlılık olarak taşımaz', () {
      final lock = File('pubspec.lock').readAsStringSync();
      for (final pkg in _forbidden) {
        final block = RegExp(
          '^  $pkg:\\n(?:.*\\n)*?    dependency: ([^\\n]+)',
          multiLine: true,
        ).firstMatch(lock);
        if (block == null) continue;
        expect(
          block.group(1),
          startsWith('transitive'),
          reason: '$pkg hâlâ doğrudan bağımlılık',
        );
      }
    });
  });
}
