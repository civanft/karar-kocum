import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/auth/domain/entities/app_user.dart';
import 'package:karar_veriyorum/features/auth/domain/repositories/auth_repository.dart';
import 'package:karar_veriyorum/features/settings/data/auth_account_session.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';
import 'package:karar_veriyorum/features/settings/domain/delete_account.dart';

/// İŞ PAKETİ 3 — BELİRSİZ SONUÇ.
///
/// Callable sunucuda TAMAMLANIP cevabı istemciye ulaşmayabilir (timeout,
/// bağlantı kopması). Kör biçimde "silindi" saymak kullanıcının yerel
/// verisini haksız yere siler; kör biçimde "silinemedi" saymak ise silinmiş
/// bir hesapta mahsur bırakır. Tek kesin sinyal Auth'un kendisidir.
class _StubClient implements AccountDeletionClient {
  _StubClient(this._failure);
  final AccountDeletionFailure? _failure;
  int calls = 0;

  @override
  Future<void> deleteAccount() async {
    calls++;
    if (_failure != null) throw _failure;
  }
}

class _StubSession implements AccountSession {
  _StubSession(this.existence);
  AccountExistenceCheck existence;
  bool verifyThrows = false;
  final calls = <String>[];

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> signInAnonymously() async => calls.add('signIn');

  @override
  Future<AccountExistenceCheck> verifyAccountDeleted() async {
    calls.add('verify');
    if (verifyThrows) throw StateError('doğrulama patladı');
    return existence;
  }
}

class _SpyCleaner implements LocalUserDataCleaner {
  int calls = 0;
  @override
  Future<void> clearAll() async => calls++;
}

const _ambiguous = AccountDeletionFailure(
  kind: AccountDeletionFailureKind.retryable,
  message: 'Hesap silinemedi, birazdan tekrar dene.',
  ambiguous: true,
);

const _unauthenticated = AccountDeletionFailure(
  kind: AccountDeletionFailureKind.nonRetryable,
  message: 'Oturum bulunamadı.',
);

DeleteAccount _build(
  AccountDeletionClient client,
  AccountSession session,
  LocalUserDataCleaner cleaner,
) =>
    DeleteAccount(client: client, cleaner: cleaner, session: session);

void main() {
  group('callable başarısı', () {
    test('doğrulama HİÇ yapılmaz; yerel temizlik ve yeni oturum çalışır',
        () async {
      final client = _StubClient(null);
      final session = _StubSession(AccountExistenceCheck.stillPresent);
      final cleaner = _SpyCleaner();

      final outcome = await _build(client, session, cleaner)();

      expect(outcome, AccountDeletionOutcome.deletedAndReady);
      expect(session.calls, ['signOut', 'signIn']); // 'verify' YOK
      expect(cleaner.calls, 1);
    });
  });

  group('belirsiz sonuç', () {
    test('timeout + hesap HÂLÂ VAR → retryable hata, yerel veri SİLİNMEZ',
        () async {
      final client = _StubClient(_ambiguous);
      final session = _StubSession(AccountExistenceCheck.stillPresent);
      final cleaner = _SpyCleaner();

      await expectLater(
        _build(client, session, cleaner)(),
        throwsA(
          isA<AccountDeletionFailure>()
              .having((f) => f.isRetryable, 'retryable', isTrue),
        ),
      );
      expect(cleaner.calls, 0);
      expect(session.calls, ['verify']);
    });

    test('timeout + reload user-not-found → silme BAŞARILI sayılır', () async {
      final client = _StubClient(_ambiguous);
      final session = _StubSession(AccountExistenceCheck.deleted);
      final cleaner = _SpyCleaner();

      final outcome = await _build(client, session, cleaner)();

      expect(outcome, AccountDeletionOutcome.deletedAndReady);
      expect(cleaner.calls, 1);
      expect(session.calls, ['verify', 'signOut', 'signIn']);
    });

    test('doğrulama BELİRSİZ kalırsa başarı VARSAYILMAZ', () async {
      final client = _StubClient(_ambiguous);
      final session = _StubSession(AccountExistenceCheck.unknown);
      final cleaner = _SpyCleaner();

      await expectLater(
        _build(client, session, cleaner)(),
        throwsA(isA<AccountDeletionFailure>()),
      );
      // Yerel temizlik, signOut ve yeni anonim oturum HİÇ çalışmaz.
      expect(cleaner.calls, 0);
      expect(session.calls, ['verify']);
    });

    test('token-expired benzeri belirsizlikte oturum işlemleri çalışmaz',
        () async {
      final client = _StubClient(_ambiguous);
      final session = _StubSession(AccountExistenceCheck.stillPresent);
      final cleaner = _SpyCleaner();

      await expectLater(
        _build(client, session, cleaner)(),
        throwsA(isA<AccountDeletionFailure>()),
      );
      expect(session.calls, isNot(contains('signOut')));
      expect(session.calls, isNot(contains('signIn')));
      expect(cleaner.calls, 0);
    });

    test('doğrulama ÇÖKERSE başarı VARSAYILMAZ', () async {
      final client = _StubClient(_ambiguous);
      final session = _StubSession(AccountExistenceCheck.deleted)
        ..verifyThrows = true;
      final cleaner = _SpyCleaner();

      await expectLater(
        _build(client, session, cleaner)(),
        throwsA(isA<AccountDeletionFailure>()),
      );
      expect(cleaner.calls, 0);
    });

    test('unauthenticated KÖR biçimde "silindi" sayılmaz', () async {
      final client = _StubClient(_unauthenticated);
      // Hesap gerçekten yok gibi görünse bile: çağrı sunucuya hiç
      // ulaşmamış olabilir.
      final session = _StubSession(AccountExistenceCheck.deleted);
      final cleaner = _SpyCleaner();

      await expectLater(
        _build(client, session, cleaner)(),
        throwsA(
          isA<AccountDeletionFailure>()
              .having((f) => f.isRetryable, 'retryable', isFalse),
        ),
      );
      expect(session.calls, isEmpty); // doğrulama bile denenmez
      expect(cleaner.calls, 0);
    });
  });

  group('AuthAccountSession.verifyAccountDeleted eşlemesi', () {
    AuthAccountSession make(AccountReloadRunner reload) =>
        AuthAccountSession.withReloader(const _NoopAuthRepository(), reload);

    test('oturum yoksa UNKNOWN (silme kanıtı DEĞİL)', () async {
      expect(
        await make(() => null).verifyAccountDeleted(),
        AccountExistenceCheck.unknown,
      );
    });

    test('reload başarılıysa kullanıcı HÂLÂ VAR', () async {
      expect(
        await make(() async {}).verifyAccountDeleted(),
        AccountExistenceCheck.stillPresent,
      );
    });

    test('YALNIZ user-not-found → DELETED', () async {
      expect(
        await make(() async {
          throw FirebaseAuthException(code: 'user-not-found');
        }).verifyAccountDeleted(),
        AccountExistenceCheck.deleted,
      );
    });

    // İş Paketi 3B: `user-token-expired` KESİN KANIT DEĞİLDİR. Token
    // geçersizliği silme dışında oturum/kimlik değişikliklerinden de
    // kaynaklanabilir; "silindi" saymak yerel veriyi haksız yere sildirirdi.
    // `user-disabled` ise hesabın VAR olduğunu gösterir.
    test('user-token-expired → UNKNOWN (silme kanıtı DEĞİL)', () async {
      expect(
        await make(() async {
          throw FirebaseAuthException(code: 'user-token-expired');
        }).verifyAccountDeleted(),
        AccountExistenceCheck.unknown,
      );
    });

    test('user-disabled → UNKNOWN (hesap duruyor)', () async {
      expect(
        await make(() async {
          throw FirebaseAuthException(code: 'user-disabled');
        }).verifyAccountDeleted(),
        AccountExistenceCheck.unknown,
      );
    });

    test('ağ hatası ve bilinmeyen kod → UNKNOWN', () async {
      expect(
        await make(() async {
          throw FirebaseAuthException(code: 'network-request-failed');
        }).verifyAccountDeleted(),
        AccountExistenceCheck.unknown,
      );
      expect(
        await make(() async {
          throw StateError('beklenmedik');
        }).verifyAccountDeleted(),
        AccountExistenceCheck.unknown,
      );
    });
  });
}

class _NoopAuthRepository implements AuthRepository {
  const _NoopAuthRepository();
  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();
  @override
  AppUser? get currentUser => null;
  @override
  Future<AppUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
