import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/domain/delete_account.dart';

/// PR-R1 / R1B — hesap silme koordinasyonu (use case).
///
/// Sözleşme: sunucu silmesi BAŞARILI olmadan yerel temizlik ve oturum
/// değişimi YAPILMAZ. Sunucu başarılıysa hesap gerçekten silinmiştir;
/// sonraki adımların sonucu "silinemedi" değil, oturum DURUMU olarak
/// raporlanır ([AccountDeletionOutcome]).
void main() {
  late List<String> calls;

  DeleteAccount build({
    AccountDeletionFailure? remoteFailure,
    bool cleanerThrows = false,
    bool signOutThrows = false,
    bool signInThrows = false,
  }) =>
      DeleteAccount(
        client: _FakeClient(calls, remoteFailure),
        cleaner: _FakeCleaner(calls, throws: cleanerThrows),
        session: _FakeSession(
          calls,
          signOutThrows: signOutThrows,
          signInThrows: signInThrows,
        ),
      );

  setUp(() => calls = <String>[]);

  test('başarı: temizlik → signOut → yeni anonim oturum sırasıyla', () async {
    final outcome = await build()();

    expect(outcome, AccountDeletionOutcome.deletedAndReady);
    expect(calls, [
      'remote:delete',
      'local:clearAll',
      'session:signOut',
      'session:signInAnonymously',
    ]);
  });

  test('sunucu başarısızsa yerel temizlik ve signOut YAPILMAZ', () async {
    const failure = AccountDeletionFailure(
      kind: AccountDeletionFailureKind.retryable,
      message: 'Bağlantı kurulamadı, tekrar dene.',
    );
    final thrown = await build(remoteFailure: failure)()
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    expect(thrown, isA<AccountDeletionFailure>());
    expect(
      (thrown! as AccountDeletionFailure).kind,
      AccountDeletionFailureKind.retryable,
    );
    expect(calls, ['remote:delete']); // sonrasındaki hiçbir adım çalışmadı
  });

  test('non-retryable hata olduğu gibi taşınır', () async {
    const failure = AccountDeletionFailure(
      kind: AccountDeletionFailureKind.nonRetryable,
      message: 'Oturumun sona ermiş.',
    );
    final thrown = await build(remoteFailure: failure)()
        .then<Object?>((_) => null)
        .catchError((Object e) => e);

    final f = thrown! as AccountDeletionFailure;
    expect(f.kind, AccountDeletionFailureKind.nonRetryable);
    expect(f.message, 'Oturumun sona ermiş.');
  });

  test('yerel temizlik patlarsa oturum adımları YİNE DE çalışır', () async {
    // Sunucu verisi silindi; cihazda kalan tercih yüzünden kullanıcı
    // silinmiş hesapta MAHSUR KALMAMALI.
    final outcome = await build(cleanerThrows: true)();

    expect(outcome, AccountDeletionOutcome.deletedAndReady);
    expect(calls, contains('session:signOut'));
    expect(calls, contains('session:signInAnonymously'));
  });

  test('yeni misafir oturumu açılamazsa deletedNeedsRestart döner', () async {
    final outcome = await build(signInThrows: true)();

    // Silme GERÇEKLEŞTİ — bu bir hata değil, farklı bir son durum.
    expect(outcome, AccountDeletionOutcome.deletedNeedsRestart);
    expect(calls, contains('session:signOut'));
  });

  test('signOut patlarsa da anonim oturum DENENİR', () async {
    final outcome = await build(signOutThrows: true)();

    expect(calls, contains('session:signInAnonymously'));
    expect(outcome, AccountDeletionOutcome.deletedAndReady);
  });

  test('signOut ve signIn birlikte patlarsa deletedNeedsRestart', () async {
    final outcome = await build(signOutThrows: true, signInThrows: true)();

    expect(outcome, AccountDeletionOutcome.deletedNeedsRestart);
  });
}

class _FakeClient implements AccountDeletionClient {
  _FakeClient(this.calls, this.failure);
  final List<String> calls;
  final AccountDeletionFailure? failure;

  @override
  Future<void> deleteAccount() async {
    calls.add('remote:delete');
    if (failure != null) throw failure!;
  }
}

class _FakeCleaner implements LocalUserDataCleaner {
  _FakeCleaner(this.calls, {this.throws = false});
  final List<String> calls;
  final bool throws;

  @override
  Future<void> clearAll() async {
    calls.add('local:clearAll');
    if (throws) throw StateError('yerel depo hatası');
  }
}

class _FakeSession implements AccountSession {
  _FakeSession(
    this.calls, {
    this.signOutThrows = false,
    this.signInThrows = false,
  });
  final List<String> calls;
  final bool signOutThrows;
  final bool signInThrows;

  @override
  Future<void> signOut() async {
    calls.add('session:signOut');
    if (signOutThrows) throw StateError('signOut hatası');
  }

  @override
  Future<void> signInAnonymously() async {
    calls.add('session:signInAnonymously');
    if (signInThrows) throw StateError('ağ yok');
  }
}
