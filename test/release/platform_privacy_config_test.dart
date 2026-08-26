import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PR-STORE-2 — platform gizlilik/uyum yapılandırması sözleşmesi.
void main() {
  group('iOS export compliance', () {
    late String plist;

    setUpAll(() => plist = File('ios/Runner/Info.plist').readAsStringSync());

    test('ITSAppUsesNonExemptEncryption tanımlı', () {
      expect(
        plist,
        contains('<key>ITSAppUsesNonExemptEncryption</key>'),
        reason: 'her yüklemede elle şifreleme sorusu sorulur',
      );
    });

    test('değer Boolean false — string "false" KABUL EDİLMEZ', () {
      final after = plist.substring(
        plist.indexOf('<key>ITSAppUsesNonExemptEncryption</key>'),
      );
      final value = after.substring(0, after.indexOf('<key>', 5));
      expect(value, contains('<false/>'), reason: 'Boolean olmalı');
      expect(
        value,
        isNot(contains('<string>')),
        reason: 'string "false" App Store tarafından reddedilir',
      );
    });

    test('spekülatif izin açıklaması eklenmemiş', () {
      for (final key in [
        'NSCameraUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSUserTrackingUsageDescription',
        'NSContactsUsageDescription',
      ]) {
        expect(plist, isNot(contains(key)), reason: '$key gereksiz');
      }
    });
  });

  group('Android gizlilik yapılandırması', () {
    late String manifest;

    setUpAll(
      () => manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );

    test('yerel yedekleme KAPALI', () {
      expect(
        manifest,
        contains('android:allowBackup="false"'),
        reason: 'kullanıcı verisi cihaz yedeğine kopyalanmamalı',
      );
    });

    test('reklam kimliği izinleri manifest-merger\'da KALDIRILIR', () {
      for (final perm in [
        'com.google.android.gms.permission.AD_ID',
        'android.permission.ACCESS_ADSERVICES_AD_ID',
        'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
      ]) {
        final block = RegExp(
          'uses-permission[^>]*android:name="${RegExp.escape(perm)}"[^>]*'
          'tools:node="remove"',
          dotAll: true,
        );
        expect(
          block.hasMatch(manifest),
          isTrue,
          reason: '$perm için tools:node="remove" yok',
        );
      }
    });

    test('tools namespace tanımlı', () {
      const toolsNs = 'xmlns:tools="http://schemas.android.com/tools"';
      expect(manifest, contains(toolsNs));
    });

    test('hassas izin EKLENMEMİŞ', () {
      for (final perm in [
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'CAMERA',
        'RECORD_AUDIO',
        'READ_CONTACTS',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
      ]) {
        expect(manifest, isNot(contains(perm)), reason: '$perm istenmemeli');
      }
    });

    test('mevcut bildirim izinleri korunur', () {
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    });
  });
}
