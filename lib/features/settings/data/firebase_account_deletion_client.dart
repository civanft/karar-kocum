import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/account_deletion.dart';

/// Callable çağrısının test edilebilir yüzeyi.
///
/// Gerçek [FirebaseFunctions] örneği testte kurulamaz (Firebase.initializeApp
/// ister); çağrı bu fonksiyon arkasına alınınca isim/payload/seçenek
/// sözleşmesi gerçek Firebase olmadan doğrulanabilir.
typedef AccountDeletionCallableRunner = Future<void> Function(
  String name,
  Map<String, Object?> payload,
  HttpsCallableOptions options,
);

/// `deleteAccount` callable istemcisi — Firebase tipleri BURADA kalır.
class FirebaseAccountDeletionClient implements AccountDeletionClient {
  FirebaseAccountDeletionClient(FirebaseFunctions functions)
      : _run = ((name, payload, options) async {
          await functions
              .httpsCallable(name, options: options)
              .call<Object?>(payload);
        });

  @visibleForTesting
  const FirebaseAccountDeletionClient.withRunner(this._run);

  final AccountDeletionCallableRunner _run;

  static const _callableName = 'deleteAccount';

  /// Sunucu bütçesi 300 sn; istemci daha erken pes eder ki kullanıcı
  /// süresiz beklemesin. Timeout retryable'dır ve sunucu kaskadı
  /// idempotent olduğundan tekrar deneme güvenlidir.
  static const _timeout = Duration(seconds: 120);

  @override
  Future<void> deleteAccount() async {
    try {
      // Payload BOŞ: uid sunucuda request.auth'tan okunur.
      await _run(
        _callableName,
        const <String, Object?>{},
        HttpsCallableOptions(
          limitedUseAppCheckToken: true, // tek kullanımlık App Check token'ı
          timeout: _timeout,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    } on AccountDeletionFailure {
      rethrow;
    } catch (_) {
      // Bağlantı koptu: sunucunun işi bitirip bitirmediği BİLİNMİYOR.
      // Ham istisna mesajı kullanıcıya SIZDIRILMAZ.
      throw const AccountDeletionFailure(
        kind: AccountDeletionFailureKind.retryable,
        message: 'Hesap silinemedi, birazdan tekrar dene.',
        ambiguous: true,
      );
    }
  }

  AccountDeletionFailure _mapError(FirebaseFunctionsException e) {
    // Sunucu mesajları (errors.ts) kullanıcı-dostu ve TR'dir.
    final message = e.message?.trim().isNotEmpty == true
        ? e.message!.trim()
        : 'Hesap silinemedi, birazdan tekrar dene.';

    switch (e.code) {
      case 'unauthenticated':
      case 'permission-denied':
      case 'failed-precondition':
      case 'invalid-argument':
        // Tekrar denemek işe yaramaz; oturum yenilenmeli.
        return AccountDeletionFailure(
          kind: AccountDeletionFailureKind.nonRetryable,
          message: message,
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
      default:
        // Sunucu işi TAMAMLAMIŞ olabilir; cevap ulaşmadı.
        return AccountDeletionFailure(
          kind: AccountDeletionFailureKind.retryable,
          message: message,
          ambiguous: true,
        );
    }
  }
}
