import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Firebase Auth deposu.
///
/// Anonim yükseltme stratejisi (mimari kararı): linkWithCredential ile
/// uid KORUNUR → users/{uid}/decisions verisi el değmeden kalır.
/// credential-already-in-use durumunda mevcut hesaba GİRİLMEZ (anonim
/// veri kaybolurdu) — AccountExistsException fırlatılır; birleştirme
/// Sprint 4'te mergeAccounts (Functions) ile.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, {GoogleSignIn? googleSignIn})
      : _google = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _google;

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
  Future<AppUser> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw const SignInCancelledException();
    final tokens = await account.authentication;
    final credential = fb.GoogleAuthProvider.credential(
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
    return _signInOrLink(credential);
  }

  @override
  Future<AppUser> signInWithApple() async {
    if (kIsWeb || !Platform.isIOS) {
      throw UnsupportedError('Apple ile giriş yalnız iOS\'ta desteklenir.');
    }
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final credential = fb.OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      accessToken: apple.authorizationCode,
    );
    return _signInOrLink(credential);
  }

  Future<AppUser> _signInOrLink(fb.AuthCredential credential) async {
    final current = _auth.currentUser;
    try {
      final result = current != null && current.isAnonymous
          ? await current.linkWithCredential(credential) // uid korunur (US-E1)
          : await _auth.signInWithCredential(credential);
      return _map(result.user)!;
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        throw AccountExistsException(e.email);
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    // Google oturumu kapanmasa BİLE Firebase oturumu kapanmalı: hesap
    // silme akışında bu, silinmiş hesabın oturumunun cihazda açık
    // kalmasını önler (PR-R1B).
    try {
      await _google.signOut();
    } catch (_) {
      // Yalnız Google tarafı; Firebase oturumu aşağıda kapatılır.
    }
    await _auth.signOut();
  }
}
