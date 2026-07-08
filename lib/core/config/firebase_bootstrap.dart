import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Firebase başlatma sonucu — provider ağacına override ile enjekte edilir.
enum FirebaseStatus {
  /// Firebase hazır; Firestore + Auth kullanılabilir.
  ready,

  /// Yapılandırma placeholder ya da başlatma hatası — uygulama YEREL MODDA
  /// çalışır (in-memory depo, kimliksiz). Geliştirme ve CI için normaldir.
  localMode,
}

/// Uygulama açılışında Firebase'i dener; başarısızlık ÇÖKME DEĞİLDİR.
/// Splash bütçesi (mimari §13): burada yalnız init + anonim oturum var,
/// Remote Config/Analytics sonraki sprintlerde eklenirken de bekletilmez.
abstract final class FirebaseBootstrap {
  static Future<FirebaseStatus> tryInitialize() async {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (options.apiKey.startsWith(DefaultFirebaseOptions.placeholderMarker)) {
      debugPrint(
        'FirebaseBootstrap: placeholder yapılandırma — yerel mod. '
        "Gerçek proje için 'flutterfire configure' çalıştırın.",
      );
      return FirebaseStatus.localMode;
    }

    try {
      await Firebase.initializeApp(options: options);
      await _ensureSignedIn();
      return FirebaseStatus.ready;
    } catch (error, stackTrace) {
      // İlk açılış + uçak modu gibi durumlarda kullanıcıyı kilitlemeyiz.
      debugPrint('FirebaseBootstrap: başlatılamadı, yerel mod. $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      return FirebaseStatus.localMode;
    }
  }

  /// US-E1: giriş yapmadan ilk karar — açılışta sessiz anonim oturum.
  /// Mevcut oturum (anonim ya da bağlı hesap) varsa dokunulmaz.
  static Future<void> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }
}
