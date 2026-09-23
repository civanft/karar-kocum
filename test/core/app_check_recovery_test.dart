// Platform fakes exercise the real bootstrap without network access.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_app_check_platform_interface/firebase_app_check_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';

class _Core extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [];
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async =>
      CoreInitializeResponse(
        name: appName,
        options: initializeAppRequest,
        pluginConstants: {},
      );
}

class _AppCheck extends FirebaseAppCheckPlatform {
  _AppCheck() : super(appInstance: null);
  int attempts = 0;
  @override
  FirebaseAppCheckPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAppCheckPlatform setInitialValues() => this;
  @override
  Future<void> activate({
    WebProvider? webProvider,
    AndroidProvider? androidProvider,
    AppleProvider? appleProvider,
  }) async {
    attempts++;
    if (attempts == 1) throw Exception('temporary activation failure');
  }
}

class _Auth extends FirebaseAuthPlatform {
  int attempts = 0;
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;
  @override
  UserPlatform? get currentUser => null;
  @override
  Future<UserCredentialPlatform> signInAnonymously() async {
    attempts++;
    throw Exception('test ends at auth boundary');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('failed App Check blocks auth and retries even when Firebase app exists',
      () async {
    TestFirebaseCoreHostApi.setUp(_Core());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final check = _AppCheck();
    final auth = _Auth();
    FirebaseAppCheckPlatform.instance = check;
    FirebaseAuthPlatform.instance = auth;

    await FirebaseBootstrap.ensureInitialized();
    expect(check.attempts, 1);
    expect(
      auth.attempts,
      0,
      reason: 'failed attestation must not enter ready/auth flow',
    );
    expect(Firebase.apps, isNotEmpty);

    await FirebaseBootstrap.ensureInitialized();
    expect(
      check.attempts,
      2,
      reason: 'retry must recover the failed activation',
    );
    expect(auth.attempts, 1);
  });
}
