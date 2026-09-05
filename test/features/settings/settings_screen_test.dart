import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karar_veriyorum/core/theme/app_theme.dart';
import 'package:karar_veriyorum/features/decision/domain/entities/decision.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/decision/presentation/screens/home_screen.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/presentation/providers/settings_providers.dart';
import 'package:karar_veriyorum/features/settings/presentation/screens/settings_screen.dart';

/// PR-R1 — "Hesap ve Veriler" ekranı ve Home girişi.
///
/// pumpAndSettle KULLANILMAZ (spinner sürerken sonsuz bekler); yalnız
/// sınırlı pump kullanılır. Gerçek AppTheme uygulanır.
void main() {
  late _FakeClient client;
  late _FakeCleaner cleaner;
  late _FakeSession session;
  late String lastRoute;

  setUp(() {
    client = _FakeClient();
    cleaner = _FakeCleaner();
    session = _FakeSession();
    lastRoute = '/settings';
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = '/settings',
    List<Decision> decisions = const [],
    Size size = const Size(400, 800),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) {
            lastRoute = '/home';
            return const HomeScreen();
          },
        ),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
          path: '/decision/new',
          builder: (_, __) => const Scaffold(body: Text('NEW ROUTE')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionClientProvider.overrideWithValue(client),
          localUserDataCleanerProvider.overrideWithValue(cleaner),
          accountSessionProvider.overrideWithValue(session),
          decisionListProvider.overrideWith((ref) => Stream.value(decisions)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Decision decided(String id) => Decision(
        id: id,
        ownerUid: 'u1',
        title: 'Telefon',
        decisionStatus: DecisionCommitStatus.decided,
        chosenOptionId: 'a',
        decidedAt: DateTime.utc(2026, 7, 1),
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );

  /// Onay dialogunu açar.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Hesabımı ve Verilerimi Sil'));
    await tester.pump();
  }

  testWidgets('1) Home ayarlar ikonunu boş hâlde gösterir', (tester) async {
    await pumpApp(tester, initial: '/home');
    expect(find.byTooltip('Ayarlar'), findsOneWidget);
  });

  testWidgets('1) Home ayarlar ikonunu dolu hâlde de gösterir', (tester) async {
    await pumpApp(tester, initial: '/home', decisions: [decided('d1')]);
    expect(find.byTooltip('Ayarlar'), findsOneWidget);
  });

  testWidgets('2) ayarlar ikonu /settings ekranını açar', (tester) async {
    await pumpApp(tester, initial: '/home');
    await tester.tap(find.byTooltip('Ayarlar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Hesap ve Veriler'), findsOneWidget);
  });

  testWidgets('3) Settings placeholder DEĞİL; gerçek içerik gösterir',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('Ayarlar'), findsOneWidget); // AppBar
    expect(find.textContaining('Sprint'), findsNothing);
    expect(find.text('Hesap ve Veriler'), findsOneWidget);
  });

  testWidgets('4) silme aksiyonu görünür ve dokunma alanı >= 48dp',
      (tester) async {
    await pumpApp(tester);

    final action = find.text('Hesabımı ve Verilerimi Sil');
    expect(action, findsOneWidget);
    final size = tester.getSize(
      find.ancestor(of: action, matching: find.byType(InkWell)).first,
    );
    expect(size.height, greaterThanOrEqualTo(48.0));
  });

  testWidgets('4) yıkıcı aksiyon colorScheme.error rengini kullanır',
      (tester) async {
    await pumpApp(tester);

    final text = tester.widget<Text>(find.text('Hesabımı ve Verilerimi Sil'));
    final context = tester.element(find.text('Hesabımı ve Verilerimi Sil'));
    expect(text.style?.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('5) dialog metni ve aksiyonları sözleşmeye uyar', (tester) async {
    await pumpApp(tester);
    await openDialog(tester);

    expect(find.text('Hesabını ve tüm verilerini sil'), findsOneWidget);
    expect(
      find.textContaining('yeni ve boş bir misafir oturumu'),
      findsOneWidget,
    );
    expect(find.text('Vazgeç'), findsOneWidget);
    expect(find.text('Kalıcı Olarak Sil'), findsOneWidget);
  });

  testWidgets('5) Vazgeç hiçbir silme çağrısı yapmaz', (tester) async {
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Vazgeç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(client.callCount, 0);
    expect(cleaner.cleared, isFalse);
    expect(session.calls, isEmpty);
  });

  testWidgets('6) onay tek silme çağrısı üretir', (tester) async {
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog kapanışı
    client.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(client.callCount, 1);
  });

  testWidgets('7) işlem sürerken spinner görünür ve ikinci dokunuş engellenir',
      (tester) async {
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog kapanışı

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // Spinner sürerken aksiyona tekrar dokunulmaya çalışılır.
    final action = find.text('Hesabımı ve Verilerimi Sil');
    if (action.evaluate().isNotEmpty) {
      await tester.tap(action, warnIfMissed: false);
      await tester.pump();
    }
    expect(client.callCount, 1);

    client.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('8) başarıda Home\'a gidilir ve başarı mesajı gösterilir',
      (tester) async {
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog kapanışı
    client.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(lastRoute, '/home');
    expect(find.byType(SnackBar), findsWidgets);
    expect(find.textContaining('silindi'), findsOneWidget);
  });

  testWidgets('9) retryable hata: mesaj gösterilir, spinner kapanır',
      (tester) async {
    client.failure = const AccountDeletionFailure(
      kind: AccountDeletionFailureKind.retryable,
      message: 'Bağlantı kurulamadı, tekrar dene.',
    );
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Bağlantı kurulamadı, tekrar dene.'), findsOneWidget);
    // Tekrar denenebilir: aksiyon hâlâ kullanılabilir durumda.
    expect(find.text('Hesabımı ve Verilerimi Sil'), findsOneWidget);
    expect(lastRoute, isNot('/home'));
  });

  testWidgets('10) non-retryable hata: mesaj gösterilir, spinner kapanır',
      (tester) async {
    client.failure = const AccountDeletionFailure(
      kind: AccountDeletionFailureKind.nonRetryable,
      message: 'Oturumun sona ermiş.',
    );
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Oturumun sona ermiş.'), findsOneWidget);
    expect(lastRoute, isNot('/home'));
  });

  testWidgets('8b) yeni oturum açılamazsa yeniden başlatma mesajı gösterilir',
      (tester) async {
    session.signInThrows = true;
    await pumpApp(tester);
    await openDialog(tester);
    await tester.tap(find.text('Kalıcı Olarak Sil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // dialog kapanışı
    client.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text(
        'Hesabın ve verilerin silindi. Yeni oturum başlatılamadı; '
        'uygulamayı yeniden aç.',
      ),
      findsOneWidget,
    );
    // Kurulmamış bir oturum "başlattık" diye duyurulmamalı.
    expect(find.textContaining('misafir oturumu başlattık'), findsNothing);
    // Genel "silinemedi" hatası da gösterilmemeli — silme GERÇEKLEŞTİ.
    expect(find.textContaining('silinemedi'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('11) 320dp genişlikte taşma yok', (tester) async {
    await pumpApp(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);

    await openDialog(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('12) textScale 1.3 ile taşma yok', (tester) async {
    await pumpApp(tester, size: const Size(360, 720), textScale: 1.3);
    expect(tester.takeException(), isNull);

    await openDialog(tester);
    expect(tester.takeException(), isNull);
  });
}

/// Sunucu çağrısını test kontrolünde bekleten sahte istemci.
///
/// DİKKAT: [Completer] yalnız [deleteAccount] İÇİNDE yaratılır. setUp'ta
/// yaratılsaydı future'ı widget testinin sahte zaman bölgesinin DIŞINDA
/// doğar; complete() sonrası devam mikro-görevi tester.pump() ile
/// boşaltılmaz ve test sonsuza kadar beklemiş gibi görünürdü.
class _FakeClient implements AccountDeletionClient {
  int callCount = 0;
  AccountDeletionFailure? failure;
  Completer<void>? _gate;
  bool _released = false;

  void complete() {
    _released = true;
    if (_gate?.isCompleted == false) _gate!.complete();
  }

  @override
  Future<void> deleteAccount() async {
    callCount++;
    if (failure != null) throw failure!;
    if (_released) return;
    await (_gate = Completer<void>()).future;
  }
}

class _FakeCleaner implements LocalUserDataCleaner {
  bool cleared = false;

  @override
  Future<void> clearAll() async => cleared = true;
}

class _FakeSession implements AccountSession {
  final calls = <String>[];
  bool signInThrows = false;

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> signInAnonymously() async {
    calls.add('signInAnonymously');
    if (signInThrows) throw StateError('ağ yok');
  }

  /// İş Paketi 3: varsayılan sahte davranış — doğrulama BELİRSİZ kalır,
  /// yani hiçbir test kazara "silindi" varsaymaz.
  AccountExistenceCheck existence = AccountExistenceCheck.unknown;

  @override
  Future<AccountExistenceCheck> verifyAccountDeleted() async => existence;
}
