import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Firebase Auth deposu.
///
/// v1 YÜZEYİ (PR-STORE-2): yalnız anonim oturum. Uygulamada Google/Apple
/// giriş ekranı yoktur; ilgili SDK'lar ve kod yolu production binary'sinden
/// çıkarıldı. Federated giriş geri geldiğinde anonim yükseltme stratejisi
/// linkWithCredential ile yapılmalıdır (uid KORUNUR → users/{uid}/decisions
/// verisi el değmeden kalır); bkz. TEKNIK-MIMARI.md §4.1.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final fb.FirebaseAuth _auth;

  static AppUser? _map(fb.User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          isAnonymous: user.isAnonymous,
          displayName: user.displayName,
          email: user.email,
          photoUrl: user.photoURL,
        );

  @override
  Stream<AppUser?> authStateChanges() => _auth.userChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AppUser> signInAnonymously() async {
    final result = await _auth.signInAnonymously();
    return _map(result.user)!;
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
