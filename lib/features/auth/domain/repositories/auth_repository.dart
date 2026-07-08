import '../entities/app_user.dart';

/// Kimlik sözleşmesi — TEKNIK-MIMARI.md §4.1 (anonim → hesap: linkWithCredential).
abstract interface class AuthRepository {
  /// Oturum akışı: abone olunca mevcut durum hemen gelir; null = oturum yok.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signInAnonymously();

  /// Google ile giriş. Mevcut oturum ANONİMSE hesaba bağlar (uid korunur —
  /// Firestore verisi taşınmaz); değilse normal giriş yapar.
  /// Hedef hesap zaten kayıtlıysa [AccountExistsException] fırlatır
  /// (veri birleştirme Sprint 4'te mergeAccounts fonksiyonuyla).
  Future<AppUser> signInWithGoogle();

  /// Apple ile giriş (yalnız iOS; diğer platformda [UnsupportedError]).
  /// Bağlama davranışı [signInWithGoogle] ile aynı.
  Future<AppUser> signInWithApple();

  Future<void> signOut();
}

/// Anonim hesabı bağlamaya çalışırken hedef kimlik zaten başka hesapta.
class AccountExistsException implements Exception {
  const AccountExistsException(this.email);
  final String? email;
}

/// Kullanıcı giriş penceresini kapattı — hata değil, sessiz iptal.
class SignInCancelledException implements Exception {
  const SignInCancelledException();
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
  Future<AppUser> signInWithGoogle() =>
      throw StateError('Yerel modda oturum açılamaz');

  @override
  Future<AppUser> signInWithApple() =>
      throw StateError('Yerel modda oturum açılamaz');

  @override
  Future<void> signOut() async {}
}
