import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../auth/domain/repositories/auth_repository.dart';
import '../domain/account_deletion.dart';

/// Mevcut kullanıcıyı sunucudan tazeleyen dar seam.
///
/// `null` döndürmek "oturum yok" demektir. Gerçek [FirebaseAuth] örneği
/// testte kurulamaz (Firebase.initializeApp ister); çağrı bu fonksiyon
/// arkasına alınınca eşleme mantığı gerçek Firebase olmadan doğrulanabilir.
typedef AccountReloadRunner = Future<void>? Function();

/// [AccountSession] ↔ [AuthRepository] adaptörü (PR-R1, İş Paketi 3).
///
/// NEDEN ADAPTÖR: AuthRepository'ye "hesap sil" sorumluluğu EKLENMEDİ —
/// silme sunucuda olur, istemcinin işi yalnız oturumu döndürmektir.
class AuthAccountSession implements AccountSession {
  AuthAccountSession(this._auth) : _reload = _firebaseReload;

  @visibleForTesting
  const AuthAccountSession.withReloader(this._auth, this._reload);

  final AuthRepository _auth;
  final AccountReloadRunner _reload;

  static Future<void>? _firebaseReload() =>
      FirebaseAuth.instance.currentUser?.reload();

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }

  /// BELİRSİZ SONUÇ doğrulaması (İş Paketi 3).
  ///
  /// `reload()` sunucuya gider: hesap silinmişse Firebase `user-not-found`
  /// (ya da token'ı geçersizleşmişse `user-token-expired`) döndürür. Bu,
  /// "callable cevabı gelmedi ama sunucu işi bitirmiş olabilir" durumunda
  /// elimizdeki TEK kesin sinyaldir.
  ///
  /// Oturum zaten yoksa bu bir silme KANITI DEĞİLDİR — çağrı en baştan
  /// kimliksiz de olmuş olabilir; o durumda [AccountExistenceCheck.unknown]
  /// döner ve başarı VARSAYILMAZ.
  @override
  Future<AccountExistenceCheck> verifyAccountDeleted() async {
    final pending = _reload();
    if (pending == null) return AccountExistenceCheck.unknown;
    try {
      await pending;
      return AccountExistenceCheck.stillPresent;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'user-token-expired') {
        return AccountExistenceCheck.deleted;
      }
      return AccountExistenceCheck.unknown;
    } catch (_) {
      return AccountExistenceCheck.unknown;
    }
  }
}
