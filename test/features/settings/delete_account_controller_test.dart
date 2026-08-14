import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/presentation/providers/settings_providers.dart';

/// PR-R1 / R1B — silme denetleyicisi: çift tetik paylaşımı, loading yaşam
/// döngüsü, oturum sonucu ve oturum kapsamlı cache yenileme.
void main() {
  late _FakeClient client;
  late _FakeCleaner cleaner;
  late _FakeSession session;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        accountDeletionClientProvider.overrideWithValue(client),
        localUserDataCleanerProvider.overrideWithValue(cleaner),
        accountSessionProvider.overrideWithValue(session),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    client = _FakeClient();
    cleaner = _FakeCleaner();
    session = _FakeSession();
  });

  test('çift tetik tek uzak istek üretir ve AYNI sonucu paylaşır', () async {
    final container = makeContainer();
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final first = controller.deleteAccount();
    final second = controller.deleteAccount(); // istem devam ederken
    client.complete();
    final results = await Future.wait([first, second]);

    expect(client.callCount, 1);
    // İkinci tetik sahte başarı ÜRETMEZ; birincinin sonucunu alır.
    expect(identical(results[0], results[1]), isTrue);
    expect(results[1].succeeded, isTrue);
  });

  test('çift tetik hata durumunda da aynı hatayı paylaşır', () async {
    client.failure = const AccountDeletionFailure(
      kind: AccountDeletionFailureKind.nonRetryable,
      message: 'Oturumun sona ermiş.',
    );
    final container = makeContainer();
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final results = await Future.wait([
      controller.deleteAccount(),
      controller.deleteAccount(),
    ]);

    expect(client.callCount, 1);
    // İkinci tetik "başarı" sanılıp Home'a yönlendirilmemeli.
    expect(results[1].succeeded, isFalse);
    expect(results[1].failure?.message, 'Oturumun sona ermiş.');
  });

  test('işlem bittikten sonra yeni tetik yeni istek üretir', () async {
    final container = makeContainer();
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final first = controller.deleteAccount();
    client.complete();
    await first;
    await controller.deleteAccount();

    expect(client.callCount, 2);
  });

  test('başarıda loading açılır ve kapanır', () async {
    final container = makeContainer();
    final states = <bool>[];
    container.listen(
      deleteAccountControllerProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final future = controller.deleteAccount();
    expect(container.read(deleteAccountControllerProvider), isTrue);

    client.complete();
    final report = await future;

    expect(report.succeeded, isTrue);
    expect(report.outcome, AccountDeletionOutcome.deletedAndReady);
    expect(container.read(deleteAccountControllerProvider), isFalse);
    expect(states, [false, true, false]);
  });

  test('hatada da loading kapanır ve hata döner', () async {
    client.failure = const AccountDeletionFailure(
      kind: AccountDeletionFailureKind.retryable,
      message: 'Bağlantı kurulamadı, tekrar dene.',
    );
    final container = makeContainer();

    final report = await container
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();

    expect(report.failure?.kind, AccountDeletionFailureKind.retryable);
    expect(report.outcome, isNull);
    expect(container.read(deleteAccountControllerProvider), isFalse);
  });

  test('beklenmedik istisnada bile loading kapanır', () async {
    client.crash = true;
    final container = makeContainer();

    final report = await container
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();

    expect(report.succeeded, isFalse);
    expect(container.read(deleteAccountControllerProvider), isFalse);
  });

  test('yeni oturum açılamazsa deletedNeedsRestart raporlanır', () async {
    session.signInThrows = true;
    final container = makeContainer();

    final future = container
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();
    client.complete();
    final report = await future;

    // Hata DEĞİL: veri silindi, yalnız oturum kurulamadı.
    expect(report.succeeded, isTrue);
    expect(report.outcome, AccountDeletionOutcome.deletedNeedsRestart);
  });

  test('başarıda oturum kapsamlı cache\'ler yenilenir', () async {
    final container = makeContainer();
    final decisionsBefore = container.read(decisionRepositoryProvider);
    final creditsBefore = container.read(creditsRepositoryProvider);

    final future = container
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();
    client.complete();
    await future;

    expect(
      identical(container.read(decisionRepositoryProvider), decisionsBefore),
      isFalse,
    );
    expect(
      identical(container.read(creditsRepositoryProvider), creditsBefore),
      isFalse,
    );
  });

  test('oturum kurulamasa BİLE eski veri cache\'i düşürülür', () async {
    session.signInThrows = true;
    final container = makeContainer();
    final decisionsBefore = container.read(decisionRepositoryProvider);

    final future = container
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();
    client.complete();
    await future;

    expect(
      identical(container.read(decisionRepositoryProvider), decisionsBefore),
      isFalse,
    );
  });

  test('hatada cache\'ler korunur (kullanıcı verisi kaybolmaz)', () async {
    client.failure = const AccountDeletionFailure(
      kind: AccountDeletionFailureKind.retryable,
      message: 'Bağlantı kurulamadı, tekrar dene.',
    );
    final container = makeContainer();
    final decisionsBefore = container.read(decisionRepositoryProvider);

    await container
        .read(deleteAccountControllerProvider.notifier)
        .deleteAccount();

    expect(
      identical(container.read(decisionRepositoryProvider), decisionsBefore),
      isTrue,
    );
  });
}

class _FakeClient implements AccountDeletionClient {
  int callCount = 0;
  AccountDeletionFailure? failure;
  bool crash = false;
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
    if (crash) throw StateError('beklenmedik');
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
}
