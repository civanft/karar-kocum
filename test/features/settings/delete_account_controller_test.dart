import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/decision/presentation/providers/decision_providers.dart';
import 'package:karar_veriyorum/features/quota/presentation/providers/credits_providers.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/presentation/providers/settings_providers.dart';

/// PR-R1 — silme denetleyicisi: çift dokunuş guard'ı, loading yaşam
/// döngüsü ve oturum kapsamlı cache yenileme.
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

  test('10) çift dokunuş tek uzak istek üretir', () async {
    final container = makeContainer();
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final first = controller.deleteAccount();
    final second = controller.deleteAccount(); // istem devam ederken
    client.complete();
    await Future.wait([first, second]);

    expect(client.callCount, 1);
  });

  test('11) başarıda loading açılır ve kapanır', () async {
    final container = makeContainer();
    final states = <bool>[];
    container.listen(
      deleteAccountControllerProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final future = controller.deleteAccount();
    await Future<void>.value(); // mikro görev: state true'ya geçsin
    expect(container.read(deleteAccountControllerProvider), isTrue);

    client.complete();
    expect(await future, isNull); // hata yok
    expect(container.read(deleteAccountControllerProvider), isFalse);
    expect(states, [false, true, false]);
  });

  test('11) hatada da loading kapanır ve hata döner', () async {
    client.failure = const AccountDeletionFailure(
      kind: AccountDeletionFailureKind.retryable,
      message: 'Bağlantı kurulamadı, tekrar dene.',
    );
    final container = makeContainer();
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final failure = await controller.deleteAccount();

    expect(failure?.kind, AccountDeletionFailureKind.retryable);
    expect(container.read(deleteAccountControllerProvider), isFalse);
  });

  test('11) beklenmedik istisnada bile loading kapanır', () async {
    client.crash = true;
    final container = makeContainer();
    final controller = container.read(deleteAccountControllerProvider.notifier);

    final failure = await controller.deleteAccount();

    expect(failure, isNotNull);
    expect(container.read(deleteAccountControllerProvider), isFalse);
  });

  test('12) başarıda oturum kapsamlı cache\'ler yenilenir', () async {
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

  test('12) hatada cache\'ler korunur (kullanıcı verisi kaybolmaz)', () async {
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
  final _gate = Completer<void>();

  void complete() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> deleteAccount() async {
    callCount++;
    if (failure != null) throw failure!;
    if (crash) throw StateError('beklenmedik');
    await _gate.future;
  }
}

class _FakeCleaner implements LocalUserDataCleaner {
  bool cleared = false;

  @override
  Future<void> clearAll() async => cleared = true;
}

class _FakeSession implements AccountSession {
  final calls = <String>[];

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> signInAnonymously() async => calls.add('signInAnonymously');
}
