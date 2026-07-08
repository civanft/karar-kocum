import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:karar_veriyorum/features/auth/data/repositories/firebase_auth_repository.dart';
import 'package:karar_veriyorum/features/auth/domain/repositories/auth_repository.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:mocktail/mocktail.dart';

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

void main() {
  late MockFirebaseAuth auth;
  late _MockGoogleSignIn google;
  late FirebaseAuthRepository repo;

  setUp(() {
    auth = MockFirebaseAuth();
    google = _MockGoogleSignIn();
    when(() => google.signOut()).thenAnswer((_) async => null);
    repo = FirebaseAuthRepository(auth, googleSignIn: google);
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

  test('signOut Google oturumunu da kapatır', () async {
    await repo.signInAnonymously();
    await repo.signOut();
    verify(() => google.signOut()).called(1);
    expect(repo.currentUser, isNull);
  });

  test('AppUser alan eşlemesi (displayName/email/photo)', () async {
    final mockUser = MockUser(
      uid: 'u-42',
      displayName: 'Civan',
      email: 'civan@example.com',
      photoURL: 'https://example.com/p.png',
    );
    final authed = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final r = FirebaseAuthRepository(authed, googleSignIn: google);

    final user = r.currentUser!;
    expect(user.uid, 'u-42');
    expect(user.displayName, 'Civan');
    expect(user.email, 'civan@example.com');
    expect(user.photoUrl, 'https://example.com/p.png');
    expect(user.isAnonymous, isFalse);
  });

  test('Google girişi iptal edilirse SignInCancelledException', () async {
    when(() => google.signIn()).thenAnswer((_) async => null);
    expect(repo.signInWithGoogle, throwsA(isA<SignInCancelledException>()));
  });

  test('Google girişi: kimlik bilgisiyle oturum açılır', () async {
    final account = _MockGoogleAccount();
    final tokens = _MockGoogleAuthentication();
    when(() => google.signIn()).thenAnswer((_) async => account);
    when(() => account.authentication).thenAnswer((_) async => tokens);
    when(() => tokens.idToken).thenReturn('id-token');
    when(() => tokens.accessToken).thenReturn('access-token');

    final user = await repo.signInWithGoogle();
    expect(user.uid, isNotEmpty);
    expect(user.isAnonymous, isFalse);
  });

  test(
      'anonim oturum + hedef hesap kayıtlı → AccountExistsException '
      '(anonim veri korunur, otomatik geçiş YOK)', () async {
    final account = _MockGoogleAccount();
    final tokens = _MockGoogleAuthentication();
    when(() => google.signIn()).thenAnswer((_) async => account);
    when(() => account.authentication).thenAnswer((_) async => tokens);
    when(() => tokens.idToken).thenReturn('id-token');
    when(() => tokens.accessToken).thenReturn('access-token');

    final anon = MockUser(uid: 'anon-1', isAnonymous: true);
    final conflicted = MockFirebaseAuth(signedIn: true, mockUser: anon);
    whenCalling(Invocation.method(#linkWithCredential, null))
        .on(anon)
        .thenThrow(FirebaseAuthException(code: 'credential-already-in-use'));
    final r = FirebaseAuthRepository(conflicted, googleSignIn: google);

    await expectLater(
      r.signInWithGoogle(),
      throwsA(isA<AccountExistsException>()),
    );
  });

  test('Apple girişi iOS dışında UnsupportedError (hazırlık kapısı)', () {
    // Test ortamı macOS/Linux — Platform.isIOS false.
    expect(repo.signInWithApple, throwsUnsupportedError);
  });
}

class _MockGoogleAccount extends Mock implements GoogleSignInAccount {}

class _MockGoogleAuthentication extends Mock
    implements GoogleSignInAuthentication {}
