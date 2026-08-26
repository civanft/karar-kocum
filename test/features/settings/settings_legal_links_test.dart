import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/config/legal_links.dart';
import 'package:karar_veriyorum/core/services/analytics/analytics_service.dart';
import 'package:karar_veriyorum/core/services/external_link_launcher.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/presentation/providers/settings_providers.dart';
import 'package:karar_veriyorum/features/settings/presentation/screens/settings_screen.dart';

/// PR-LEGAL-1 — Ayarlar ekranındaki üç yasal bağlantı.
///
/// pumpAndSettle KULLANILMAZ; yalnız sınırlı pump. Mağaza incelemesi
/// çalışmayan ya da sonsuz bekleyen bir bağlantıyı reddeder.
void main() {
  late _FakeLauncher launcher;
  late _RecordingAnalytics analytics;

  setUp(() {
    launcher = _FakeLauncher();
    analytics = _RecordingAnalytics();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionClientProvider.overrideWithValue(_NoopClient()),
          localUserDataCleanerProvider.overrideWithValue(_NoopCleaner()),
          accountSessionProvider.overrideWithValue(_NoopSession()),
          externalLinkLauncherProvider.overrideWithValue(launcher),
          analyticsServiceProvider.overrideWithValue(analytics),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: GoRouter(
            initialLocation: '/settings',
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
              GoRoute(
                path: '/home',
                builder: (_, __) => const Scaffold(body: Text('HOME')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('üç yasal bağlantı da görünür', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Gizlilik Politikası'), findsOneWidget);
    expect(find.text('Kullanım Koşulları'), findsOneWidget);
    expect(find.text('Destek'), findsOneWidget);
  });

  testWidgets('her satır DOĞRU URL gönderir', (tester) async {
    await pumpSettings(tester);

    for (final pair in <(String, String)>[
      ('Gizlilik Politikası', LegalLinks.privacy),
      ('Kullanım Koşulları', LegalLinks.terms),
      ('Destek', LegalLinks.support),
    ]) {
      await tester.tap(find.text(pair.$1));
      await tester.pump();
      expect(launcher.opened.last, pair.$2, reason: '${pair.$1} yanlış URL');
    }
    expect(launcher.opened, hasLength(3));
  });

  testWidgets('açma başarısızsa Türkçe SnackBar gösterilir', (tester) async {
    launcher.result = false;
    await pumpSettings(tester);

    await tester.tap(find.text('Gizlilik Politikası'));
    await tester.pump();

    final snack = find.byType(SnackBar);
    expect(snack, findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: snack, matching: find.byType(Text)).first,
    );
    expect(text.data, isNotNull);
    expect(text.data, contains('açılamadı'));
    expect(text.data, isNot(contains('Error')));
  });

  testWidgets('başarısızlıkta SONSUZ spinner kalmaz', (tester) async {
    launcher.result = false;
    await pumpSettings(tester);

    await tester.tap(find.text('Destek'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('başarıda SnackBar gösterilmez', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Kullanım Koşulları'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('açma BAŞARISIZSA analytics gönderilmez', (tester) async {
    launcher.result = false;
    await pumpSettings(tester);

    await tester.tap(find.text('Gizlilik Politikası'));
    await tester.pump();

    expect(
      analytics.documents,
      isEmpty,
      reason: 'sayfa açılmadığı hâlde "opened" kaydı üretilmiş',
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('launcher FIRLATIRSA analytics gönderilmez', (tester) async {
    launcher.throws = true;
    await pumpSettings(tester);

    await tester.tap(find.text('Kullanım Koşulları'));
    await tester.pump();

    expect(analytics.documents, isEmpty);
  });

  testWidgets('başarıda analytics TAM BİR KEZ gönderilir', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Destek'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(analytics.documents, ['support']);
  });

  testWidgets('analytics hatası UI davranışını ETKİLEMEZ', (tester) async {
    analytics.throws = true;
    await pumpSettings(tester);

    await tester.tap(find.text('Gizlilik Politikası'));
    await tester.pump();

    // Açma başarılıydı: hata SnackBar'ı çıkmamalı, ekran ayakta kalmalı.
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('Gizlilik Politikası'), findsOneWidget);
  });

  testWidgets('analytics YALNIZ belge adını taşır, URL/PII taşımaz',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Gizlilik Politikası'));
    await tester.pump();
    await tester.tap(find.text('Destek'));
    await tester.pump();

    expect(analytics.documents, ['privacy', 'support']);
    for (final doc in analytics.documents) {
      expect(doc, isNot(contains('http')));
    }
  });

  testWidgets('mevcut hesap silme satırı korunur', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Hesabımı ve Verilerimi Sil'), findsOneWidget);
  });
}

class _FakeLauncher implements ExternalLinkLauncher {
  final List<String> opened = [];
  bool result = true;
  bool throws = false;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    if (throws) throw Exception('kanal yok');
    return result;
  }
}

class _RecordingAnalytics extends NoopAnalyticsService {
  final List<String> documents = [];
  bool throws = false;

  @override
  Future<void> logLegalLinkOpened({required String document}) async {
    if (throws) throw Exception('analytics kanalı yok');
    documents.add(document);
  }
}

class _NoopClient implements AccountDeletionClient {
  @override
  Future<void> deleteAccount() async {}
}

class _NoopCleaner implements LocalUserDataCleaner {
  @override
  Future<void> clearAll() async {}
}

class _NoopSession implements AccountSession {
  @override
  Future<void> signOut() async {}
  @override
  Future<void> signInAnonymously() async {}
}
