import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:karar_veriyorum/features/auth/data/repositories/firebase_auth_repository.dart';

/// PR-R1B — hesap silme sonrası oturum kapatma dayanıklılığı.
///
/// Google oturumu kapanmasa bile FirebaseAuth oturumu KAPANMALI: aksi
/// hâlde silinmiş hesabın Firebase oturumu cihazda açık kalır.
void main() {
  test('Google signOut hata verse de FirebaseAuth signOut çağrılır', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final repo = FirebaseAuthRepository(
      auth,
      googleSignIn: _ThrowingGoogleSignIn(),
    );

    await expectLater(repo.signOut(), completes);

    expect(auth.currentUser, isNull);
  });

  test('normal akışta da FirebaseAuth oturumu kapanır', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final repo =
        FirebaseAuthRepository(auth, googleSignIn: _QuietGoogleSignIn());

    await repo.signOut();

    expect(auth.currentUser, isNull);
  });
}

/// Sessiz sahte: gerçek GoogleSignIn platform kanalına gider.
class _QuietGoogleSignIn extends GoogleSignIn {
  @override
  Future<GoogleSignInAccount?> signOut() async => null;
}

class _ThrowingGoogleSignIn extends GoogleSignIn {
  @override
  Future<GoogleSignInAccount?> signOut() async {
    throw StateError('Google oturumu kapatılamadı');
  }
}
