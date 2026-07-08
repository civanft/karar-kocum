import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Faz 1'de: Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
  // + Crashlytics zone guard + App Check activate.
  // Splash bütçesi: yalnız Auth + Remote Config beklenir (500 ms timeout → cache).

  runApp(const ProviderScope(child: KararVeriyorumApp()));
}
