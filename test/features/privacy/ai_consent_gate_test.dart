import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/ai_analysis_client.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/repositories/stored_analysis_repository.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/providers/analysis_providers.dart';
import 'package:karar_veriyorum/features/ai_analysis/presentation/widgets/analysis_card.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/privacy/domain/entities/ai_consent.dart';
import 'package:karar_veriyorum/features/privacy/domain/repositories/ai_consent_repository.dart';
import 'package:karar_veriyorum/features/privacy/presentation/providers/ai_consent_providers.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İŞ PAKETİ 5 / DİLİM B — VERSİYONLU AI İZNİ (istemci kapısı).
///
/// Karar içeriği OpenAI'ye gitmeden ÖNCE açık, bilgilendirilmiş ve geri
/// alınabilir izin gerekir. Kapı atlatılabilir olduğu için backend de
/// zorlar (functions/test/ai_consent_enforcement.test.ts); burada
/// KULLANICI YÜZEYİ ve dış çağrının hiç başlamadığı kanıtlanır.

/// Dış sistem sınırı: kaç kez ÜCRETLİ analiz çağrıldığını sayar.
class _CountingClient implements AiAnalysisClient {
  int calls = 0;

  @override
  Future<AiAnalysis> analyze({
    required String decisionId,
    required String requestId,
  }) async {
    calls++;
    return AiAnalysis.mock();
  }
}

/// Kalıcı analiz deposu — dış sistem sınırında sahte.
class _StoredAnalysisStub implements StoredAnalysisRepository {
  _StoredAnalysisStub(this._analysis);
  final AiAnalysis? _analysis;

  @override
  Stream<AiAnalysis?> watchLatest(String decisionId) =>
      Stream<AiAnalysis?>.value(_analysis);
}

/// Kontrollü izin deposu — dış sistem sınırında sahte.
class _FakeConsentRepository implements AiConsentRepository {
  _FakeConsentRepository([AiConsent? initial]) : _current = initial;

  final _controller = StreamController<AiConsent?>.broadcast();
  int grants = 0;
  int withdrawals = 0;
  Object? failWith;
  AiConsent? _current;

  /// Gerçek Firestore akışı gibi: abone olan ÖNCE mevcut durumu alır.
  @override
  Stream<AiConsent?> watch() {
    if (failWith != null) return Stream<AiConsent?>.error(failWith!);
    return Stream<AiConsent?>.multi((controller) {
      controller.add(_current);
      final sub = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> grant() async {
    grants++;
    _current = AiConsent(
      granted: true,
      version: currentAiConsentVersion,
      updatedAt: DateTime(2026),
    );
    _controller.add(_current);
  }

  @override
  Future<void> withdraw() async {
    withdrawals++;
    _current = AiConsent(
      granted: false,
      version: currentAiConsentVersion,
      updatedAt: DateTime(2026),
    );
    _controller.add(_current);
  }

  void emit(AiConsent? consent) => _controller.add(consent);
}

const _acceptLabel = 'Kabul et ve analizi başlat';
const _declineLabel = 'Şimdi değil';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _CountingClient client;
  late _FakeConsentRepository consent;

  Future<void> pump(
    WidgetTester tester, {
    AiConsent? initialConsent,
    Object? consentError,
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    client = _CountingClient();
    consent = _FakeConsentRepository(initialConsent);
    if (consentError != null) consent.failWith = consentError;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiAnalysisClientProvider.overrideWithValue(client),
          aiConsentRepositoryProvider.overrideWithValue(consent),
          remainingCreditsProvider.overrideWith((_) => Stream.value(5)),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: AnalysisSection(decisionId: 'd1'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAnalyze(WidgetTester tester) async {
    await tester.tap(find.text('AI Analizini Başlat'));
    await tester.pumpAndSettle();
  }

  group('ilk analiz talebi', () {
    testWidgets('1. disclosure AÇILIR, DIŞ ÇAĞRI YAPILMAZ', (tester) async {
      await pump(tester);
      await tapAnalyze(tester);

      expect(find.text(_acceptLabel), findsOneWidget);
      expect(find.text(_declineLabel), findsOneWidget);
      expect(client.calls, 0, reason: 'izin öncesi aktarım YOK');
      expect(consent.grants, 0, reason: 'metni görmek izin DEĞİLDİR');
    });

    testWidgets('disclosure gerçek veri akışını anlatır', (tester) async {
      await pump(tester);
      await tapAnalyze(tester);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(text, contains('OpenAI'));
      expect(text.toLowerCase(), contains('seçenek'));
      expect(text.toLowerCase(), contains('kriter'));
      // Anahtar cihazda DEĞİL, sonuç saklanıyor, çıktı hatalı olabilir.
      expect(text.toLowerCase(), contains('sunucu'));
      expect(text.toLowerCase(), contains('sakla'));
      expect(text.toLowerCase(), contains('hatalı'));
      expect(text.toLowerCase(), contains('profesyonel'));
    });

    testWidgets('2. KABUL → tek izin kaydı ve TEK analiz çağrısı',
        (tester) async {
      await pump(tester);
      await tapAnalyze(tester);
      await tester.tap(find.text(_acceptLabel));
      await tester.pumpAndSettle();

      expect(consent.grants, 1);
      expect(client.calls, 1);
    });

    testWidgets('3. ŞİMDİ DEĞİL → çağrı yok, izin kaydı yok', (tester) async {
      await pump(tester);
      await tapAnalyze(tester);
      await tester.tap(find.text(_declineLabel));
      await tester.pumpAndSettle();

      expect(consent.grants, 0);
      expect(client.calls, 0);
      // AI dışı akış çalışmaya devam eder: CTA hâlâ kullanılabilir.
      expect(find.text('AI Analizini Başlat'), findsOneWidget);
    });

    testWidgets('8. ÇİFT dokunma tek izin kaydı ve TEK istek üretir',
        (tester) async {
      await pump(tester);
      await tapAnalyze(tester);
      await tester.tap(find.text(_acceptLabel), warnIfMissed: false);
      await tester.tap(find.text(_acceptLabel), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(consent.grants, 1);
      expect(client.calls, 1);
    });
  });

  group('izin durumu', () {
    testWidgets('geçerli izin varsa disclosure AÇILMAZ, analiz başlar',
        (tester) async {
      await pump(
        tester,
        initialConsent: AiConsent(
          granted: true,
          version: currentAiConsentVersion,
          updatedAt: DateTime(2026),
        ),
      );
      await tapAnalyze(tester);

      expect(find.text(_acceptLabel), findsNothing);
      expect(client.calls, 1);
    });

    testWidgets('5. ESKİ sürüm izni → yeniden izin istenir', (tester) async {
      await pump(
        tester,
        initialConsent: AiConsent(
          granted: true,
          version: currentAiConsentVersion - 1,
          updatedAt: DateTime(2026),
        ),
      );
      await tapAnalyze(tester);

      expect(find.text(_acceptLabel), findsOneWidget);
      expect(client.calls, 0);
    });

    testWidgets('4. izin OKUMA HATASI → FAIL CLOSED', (tester) async {
      await pump(tester, consentError: StateError('firestore unavailable'));
      await tapAnalyze(tester);

      expect(client.calls, 0, reason: 'okunamayan izin, izin değildir');
      // Ham hata yüzeye çıkmaz.
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(text.contains('StateError'), isFalse);
      expect(text.contains('firestore unavailable'), isFalse);
    });

    testWidgets('6-7. geri alma engeller, yeniden kabul çalıştırır',
        (tester) async {
      await pump(
        tester,
        initialConsent: AiConsent(
          granted: false,
          version: currentAiConsentVersion,
          updatedAt: DateTime(2026),
        ),
      );
      await tapAnalyze(tester);
      expect(find.text(_acceptLabel), findsOneWidget);
      expect(client.calls, 0);

      await tester.tap(find.text(_acceptLabel));
      await tester.pumpAndSettle();
      expect(client.calls, 1);
    });
  });

  group('geri yüklenen analiz', () {
    testWidgets('11. mevcut analiz İZİN OLMADAN görüntülenir, çağrı YOK',
        (tester) async {
      // Ödenmiş bir analiz zaten Firestore'da (Paket 4 restore'u). Onu
      // GÖRMEK yeni bir aktarım DEĞİLDİR: ne izin modalı açılır ne dış
      // çağrı yapılır. Gerçek restore yolu kullanılır.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      client = _CountingClient();
      consent = _FakeConsentRepository(); // izin YOK
      final stored = _StoredAnalysisStub(AiAnalysis.mock());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiAnalysisClientProvider.overrideWithValue(client),
            aiConsentRepositoryProvider.overrideWithValue(consent),
            storedAnalysisRepositoryProvider.overrideWithValue(stored),
            firebaseStatusProvider.overrideWithValue(FirebaseStatus.ready),
            currentUidProvider.overrideWithValue('u1'),
            remainingCreditsProvider.overrideWith((_) => Stream.value(5)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnalysisSection(decisionId: 'd1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_acceptLabel), findsNothing, reason: 'izin döngüsü YOK');
      expect(client.calls, 0, reason: 'görüntüleme aktarım değildir');
      expect(find.text('AI Analizini Başlat'), findsNothing);
      expect(find.textContaining('AI tarafından oluşturuldu'), findsOneWidget);
    });
  });

  group('erişilebilirlik ve görsel dayanıklılık', () {
    testWidgets('15a. disclosure yüksek text scale ile TAŞMAZ', (tester) async {
      await pump(tester, textScale: 2.0);
      await tapAnalyze(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(_acceptLabel), findsOneWidget);
    });

    testWidgets('15b. dark mode ve dar ekranda çalışır', (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      await pump(tester, brightness: Brightness.dark);
      await tapAnalyze(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(_acceptLabel), findsOneWidget);
    });

    testWidgets('15c. eylemler erişilebilir buton semantiği taşır',
        (tester) async {
      await pump(tester);
      await tapAnalyze(tester);
      final semantics = tester.getSemantics(find.text(_acceptLabel));
      expect(semantics.label, contains('Kabul'));
    });
  });
}
