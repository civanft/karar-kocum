import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/auth/data/repositories/firebase_auth_repository.dart';

/// Anonim oturum sözleşmesi (PR-STORE-2 sonrası v1 yüzeyi).
///
/// Federated giriş kaldırıldı; korunan davranışlar: auth state stream,
/// anonim giriş, current UID ve sign-out.
void main() {
  late MockFirebaseAuth auth;
  late FirebaseAuthRepository repo;

  setUp(() {
    auth = MockFirebaseAuth();
    repo = FirebaseAuthRepository(auth);
  });

  test('anonim giriş: isAnonymous kullanıcı döner (US-E1)', () async {
    final user = await repo.signInAnonymously();
    expect(user.isAnonymous, isTrue);
    expect(user.uid, isNotEmpty);
    expect(repo.currentUser?.uid, user.uid);
  });

  test('authStateChanges: giriş ve çıkış emisyon üretir', () async {
    final emissions = <String?>[];
    final sub = repo.authStateChanges().listen((u) => emissions.add(u?.uid));

    await repo.signInAnonymously();
    await Future<void>.delayed(Duration.zero);
    await repo.signOut();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emissions, contains(isNotNull)); // giriş
    expect(emissions.last, isNull); // çıkış
  });

  test('AppUser alan eşlemesi (displayName/email/photo)', () async {
    final mockUser = MockUser(
      uid: 'u-42',
      displayName: 'Civan',
      email: 'civan@example.com',
      photoURL: 'https://example.com/p.png',
    );
    final authed = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final r = FirebaseAuthRepository(authed);

    final user = r.currentUser!;
    expect(user.uid, 'u-42');
    expect(user.displayName, 'Civan');
    expect(user.email, 'civan@example.com');
    expect(user.photoUrl, 'https://example.com/p.png');
    expect(user.isAnonymous, isFalse);
  });
}
