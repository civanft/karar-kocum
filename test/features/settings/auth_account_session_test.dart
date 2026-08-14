import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/auth/domain/entities/app_user.dart';
import 'package:karar_veriyorum/features/auth/domain/repositories/auth_repository.dart';
import 'package:karar_veriyorum/features/settings/data/auth_account_session.dart';

/// PR-R1B — dar oturum portunun AuthRepository'ye bağlanması.
///
/// AuthRepository'ye "hesap sil" sorumluluğu EKLENMEDİ; silme sunucuda
/// olur, istemcinin işi yalnız oturumu döndürmektir.
void main() {
  test('signOut ve signInAnonymously depoya iletilir', () async {
    final repo = _RecordingAuthRepository();
    final session = AuthAccountSession(repo);

    await session.signOut();
    await session.signInAnonymously();

    expect(repo.calls, ['signOut', 'signInAnonymously']);
  });

  test('depo hatası yutulmaz — kararı çağıran verir', () async {
    final repo = _RecordingAuthRepository(signInThrows: true);
    final session = AuthAccountSession(repo);

    await expectLater(session.signInAnonymously(), throwsStateError);
  });
}

class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({this.signInThrows = false});

  final bool signInThrows;
  final calls = <String>[];

  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> signInAnonymously() async {
    calls.add('signInAnonymously');
    if (signInThrows) throw StateError('ağ yok');
    return const AppUser(uid: 'yeni-misafir', isAnonymous: true);
  }

  @override
  Future<AppUser> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<AppUser> signInWithApple() => throw UnimplementedError();

  @override
  Future<void> signOut() async => calls.add('signOut');
}
