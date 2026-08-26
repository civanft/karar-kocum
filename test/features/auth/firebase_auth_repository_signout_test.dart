import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/auth/data/repositories/firebase_auth_repository.dart';

/// PR-R1B — hesap silme sonrası oturum kapatma.
///
/// PR-STORE-2 sonrası federated giriş yüzeyi yok; signOut yalnız FirebaseAuth
/// oturumunu kapatır. Korunan sözleşme aynı: silinmiş hesabın oturumu cihazda
/// AÇIK KALMAMALI.
void main() {
  test('signOut FirebaseAuth oturumunu kapatır', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final repo = FirebaseAuthRepository(auth);

    await repo.signOut();

    expect(auth.currentUser, isNull);
  });

  test('oturum yokken signOut hata vermez', () async {
    final auth = MockFirebaseAuth();
    final repo = FirebaseAuthRepository(auth);

    await expectLater(repo.signOut(), completes);
    expect(auth.currentUser, isNull);
  });
}
