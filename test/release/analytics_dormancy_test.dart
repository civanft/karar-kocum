import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/services/analytics/analytics_service.dart';

/// İŞ PAKETİ 5 / DİLİM E — ANALYTICS VE TEŞHİS.
///
/// Analytics izni ile AI işleme izni AYRI şeylerdir ve birbirini
/// etkilemez. v1'de analytics "varsayılan kapalı" DEĞİL, **hiç yok**:
/// SDK binary'de bulunmaz. Bu testler o gerçeği kilitler — mağaza
/// beyanı ve gizlilik politikası buna dayanıyor.
void main() {
  group('SDK seviyesinde yokluk', () {
    test('firebase_analytics BAĞIMLILIK OLARAK yok', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lock = File('pubspec.lock').readAsStringSync();
      expect(pubspec.contains('firebase_analytics:'), isFalse);
      expect(
        RegExp(r'^\s{2}firebase_analytics:', multiLine: true).hasMatch(lock),
        isFalse,
        reason: 'lock dosyasında da bulunmamalı',
      );
    });

    test('hiçbir kaynak dosya Analytics SDK API\'si çağırmaz', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('FirebaseAnalytics') ||
            source.contains('setAnalyticsCollectionEnabled') ||
            source.contains('logEvent(')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('reklam kimliği izinleri manifest\'te KALDIRILIYOR', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      for (final permission in [
        'com.google.android.gms.permission.AD_ID',
        'android.permission.ACCESS_ADSERVICES_AD_ID',
        'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
      ]) {
        final block = RegExp(
          '<uses-permission[^>]*$permission"[^>]*tools:node="remove"',
          dotAll: true,
        );
        expect(
          block.hasMatch(manifest.replaceAll(RegExp(r'\s+'), ' ')),
          isTrue,
          reason: '$permission kaldırılmıyor',
        );
      }
    });
  });

  group('çalışma zamanı davranışı', () {
    test('tek uygulama Noop\'tur ve provider onu döner', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(analyticsServiceProvider),
        isA<NoopAnalyticsService>(),
      );
    });

    test('v1 sözleşmesi: analytics KAPALI', () {
      expect(analyticsEnabledInV1(), isFalse);
    });

    test('hiçbir olay çağrısı hata üretmez ve sessizce tamamlanır', () async {
      const service = NoopAnalyticsService();
      await service.logDecisionCreated(source: 'blank');
      await service.logAnalysisRequested(tier: 'basic');
      await service.logAnalysisCompleted(
        tier: 'basic',
        latencyMs: 1,
        cached: false,
      );
      await service.logLegalLinkOpened(document: 'privacy');
      await service.setUserProperties(plan: 'free', decisionsTotal: 1);
    });
  });

  group('olay şeması PII taşımaz', () {
    /// SERBEST METİN taşıyabilecek tek tip `String`'tir. Sayılar ve
    /// boolean'lar içerik taşıyamaz. Bu yüzden değişmez şudur: her `String`
    /// parametre, değer kümesi BELGELENMİŞ bir enum alanıdır.
    ///
    /// Yeni bir `String` parametre eklemek bu testi kırar — bilinçli karar
    /// olmadan olaylara serbest metin giremez.
    const allowedStringParams = {
      'source', // blank|template, paywall kaynağı
      'templateId', // statik katalog kimliği
      'origin', // template|keyword|generic
      'tier', // basic
      'channel', // paylaşım kanalı
      'format', // paylaşım biçimi
      'document', // privacy|terms|support
      'plan', // free|premium
    };

    test('hiçbir olayda BEYAN EDİLMEMİŞ String parametre yok', () {
      final source = File(
        'lib/core/services/analytics/analytics_service.dart',
      ).readAsStringSync();
      // Yalnız arayüz bloğu: uygulama gövdeleri imza kaynağı değildir.
      final interface = source.substring(
        source.indexOf('abstract interface class AnalyticsService'),
        source.indexOf('class NoopAnalyticsService'),
      );

      final stringParams = RegExp(r'String\??\s+(\w+)')
          .allMatches(interface)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        stringParams.difference(allowedStringParams),
        isEmpty,
        reason: 'beyan edilmemiş serbest metin parametresi',
      );
    });

    test('içerik/PII adlı parametre HİÇ yok', () {
      final source = File(
        'lib/core/services/analytics/analytics_service.dart',
      ).readAsStringSync();
      final interface = source
          .substring(
            source.indexOf('abstract interface class AnalyticsService'),
            source.indexOf('class NoopAnalyticsService'),
          )
          .toLowerCase();

      for (final forbidden in [
        'title',
        'summary',
        'recommendation',
        'email',
        'uid',
        'userid',
        'content',
        'prompt',
        'text',
      ]) {
        expect(
          RegExp('\\b\\w*$forbidden\\w*\\s*[,)}]').hasMatch(interface),
          isFalse,
          reason: 'olay parametresinde içerik/PII: $forbidden',
        );
      }
    });
  });
}
