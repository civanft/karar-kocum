import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/domain/delete_account.dart';

/// PR-R1 — hesap silme koordinasyonu (use case).
///
/// Sözleşme: sunucu silmesi BAŞARILI olmadan yerel temizlik ve oturum
/// değişimi YAPILMAZ. Sunucu başarılıysa veri artık gerçekten yok demektir;
/// sonraki adımların hatası kullanıcıya "silinemedi" gibi gösterilmez.
void main() {
  late List<String> calls;

  DeleteAccount build({
    AccountDeletionFailure? remoteFailure,
    bool cleanerThrows = false,
    bool signInThrows = false,
  }) =>
      DeleteAccount(
        client: _FakeClient(calls, remoteFailure),
        cleaner: _FakeCleaner(calls, throws: cleanerThrows),
        session: _FakeSession(calls, signInThrows: signInThrows),
      );

  setUp(() => calls = <String>[]);

  test('8-9) başarı: temizlik → signOut → yeni anonim oturum sırasıyla',
      () async {
    await build()();
    expect(calls, [
      'remote:delete',
      'local:clearAll',
      'session:signOut',
      'session:signInAnonymously',
    ]);
  });

  test('7) sunucu başarısızsa yerel temizlik ve signOut YAPILMAZ', () async {
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

  test('yerel temizlik patlarsa oturum adımları yine de çalışır', () async {
    // Sunucu verisi silindi; cihazda kalan tercih yüzünden kullanıcı
    // silinmiş hesapta MAHSUR KALMAMALI.
    await build(cleanerThrows: true)();
    expect(calls, contains('session:signOut'));
    expect(calls, contains('session:signInAnonymously'));
  });

  test('yeni misafir oturumu açılamazsa akış yine de başarılı sayılır',
      () async {
    // Silme gerçekleşti; yeni oturum bir sonraki açılışta bootstrap ile
    // kurulur. Kullanıcıya hata göstermek yanıltıcı olur.
    await expectLater(build(signInThrows: true)(), completes);
    expect(calls, contains('session:signOut'));
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
  _FakeSession(this.calls, {this.signInThrows = false});
  final List<String> calls;
  final bool signInThrows;

  @override
  Future<void> signOut() async => calls.add('session:signOut');

  @override
  Future<void> signInAnonymously() async {
    calls.add('session:signInAnonymously');
    if (signInThrows) throw StateError('ağ yok');
  }
}
