import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/settings/data/firebase_account_deletion_client.dart';
import 'package:karar_veriyorum/features/settings/domain/account_deletion.dart';

/// PR-R1 — `deleteAccount` callable istemcisi.
///
/// Firebase tipleri BU KATMANDA kalır; domain yalnız [AccountDeletionFailure]
/// görür. Çağrı yüzeyi (isim/payload/seçenek) enjekte edilebilir bir koşucu
/// üzerinden doğrulanır — gerçek Firebase başlatmaya gerek kalmaz.
void main() {
  late List<_Invocation> invocations;

  FirebaseAccountDeletionClient client({Object? error}) =>
      FirebaseAccountDeletionClient.withRunner((name, payload, options) async {
        invocations.add(_Invocation(name, payload, options));
        if (error != null) throw error;
      });

  setUp(() => invocations = <_Invocation>[]);

  test('1) boş payload gönderir; UID istemciden GEÇMEZ', () async {
    await client().deleteAccount();

    expect(invocations, hasLength(1));
    expect(invocations.single.name, 'deleteAccount');
    expect(invocations.single.payload, isEmpty);
  });

  test('2) limited-use App Check token aktiftir', () async {
    await client().deleteAccount();
    expect(invocations.single.options.limitedUseAppCheckToken, isTrue);
  });

  test('istemci timeout\'u sonludur ve sunucu bütçesini aşmaz', () async {
    await client().deleteAccount();
    final timeout = invocations.single.options.timeout;
    expect(timeout, greaterThan(Duration.zero));
    // Sunucu tarafı timeoutSeconds: 300.
    expect(timeout, lessThanOrEqualTo(const Duration(seconds: 300)));
  });

  test('3) başarı: hata fırlatmaz', () async {
    await expectLater(client().deleteAccount(), completes);
  });

  test('4) unavailable ve deadline-exceeded retryable', () async {
    for (final code in ['unavailable', 'deadline-exceeded', 'internal']) {
      final failure = await _failureOf(client(error: _err(code, 'sunucu')));
      expect(
        failure.kind,
        AccountDeletionFailureKind.retryable,
        reason: '$code retryable olmalı',
      );
    }
  });

  test('5) unauthenticated ve failed-precondition non-retryable', () async {
    for (final code in [
      'unauthenticated',
      'failed-precondition',
      'permission-denied',
    ]) {
      final failure = await _failureOf(client(error: _err(code, 'oturum')));
      expect(
        failure.kind,
        AccountDeletionFailureKind.nonRetryable,
        reason: '$code non-retryable olmalı',
      );
    }
  });

  test('6) bilinmeyen/Firebase dışı hata güvenli mesaja çevrilir', () async {
    final failure = await _failureOf(
      client(error: StateError('içeride ham detay var')),
    );
    expect(failure.kind, AccountDeletionFailureKind.retryable);
    expect(failure.message, isNotEmpty);
    expect(failure.message, isNot(contains('ham detay')));
  });

  test('sunucu mesajı boşsa kullanıcıya anlamlı metin gösterilir', () async {
    final failure = await _failureOf(client(error: _err('unavailable', '')));
    expect(failure.message.trim(), isNotEmpty);
  });
}

Future<AccountDeletionFailure> _failureOf(
  FirebaseAccountDeletionClient client,
) async {
  final thrown = await client
      .deleteAccount()
      .then<Object?>((_) => null)
      .catchError((Object e) => e);
  expect(thrown, isA<AccountDeletionFailure>());
  return thrown! as AccountDeletionFailure;
}

/// Korumalı yapıcıya erişmek için alt sınıf (test amaçlı).
class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException(String code, String message)
      : super(code: code, message: message);
}

FirebaseFunctionsException _err(String code, String message) =>
    _TestFunctionsException(code, message);

class _Invocation {
  _Invocation(this.name, this.payload, this.options);
  final String name;
  final Map<String, Object?> payload;
  final HttpsCallableOptions options;
}
