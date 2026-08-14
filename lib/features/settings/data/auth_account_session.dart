import '../../auth/domain/repositories/auth_repository.dart';
import '../domain/account_deletion.dart';

/// [AccountSession] ↔ [AuthRepository] adaptörü (PR-R1).
///
/// NEDEN ADAPTÖR: AuthRepository'ye "hesap sil" sorumluluğu EKLENMEDİ —
/// silme sunucuda olur, istemcinin işi yalnız oturumu döndürmektir.
/// Settings bu dar portu görür, tüm giriş yüzeyini değil.
class AuthAccountSession implements AccountSession {
  const AuthAccountSession(this._auth);

  final AuthRepository _auth;

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }
}
