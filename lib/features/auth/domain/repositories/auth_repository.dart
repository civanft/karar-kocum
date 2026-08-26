import '../entities/app_user.dart';

/// Kimlik sözleşmesi.
///
/// v1 (PR-STORE-2): yalnız anonim oturum. Federated giriş yüzeyi
/// (Google/Apple) uygulamada UI'ı olmadığı için kaldırıldı; geri gelirse
/// anonim→hesap yükseltmesi linkWithCredential ile yapılmalı
/// (TEKNIK-MIMARI.md §4.1).
abstract interface class AuthRepository {
  /// Oturum akışı: abone olunca mevcut durum hemen gelir; null = oturum yok.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signInAnonymously();

  Future<void> signOut();
}

/// Yerel mod (Firebase yok): oturum daima null.
class NoopAuthRepository implements AuthRepository {
  const NoopAuthRepository();

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> signInAnonymously() =>
      throw StateError('Yerel modda oturum açılamaz');

  @override
  Future<void> signOut() async {}
}
