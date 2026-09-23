import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';

void main() {
  test('first release startup cannot wait forever before runApp', () async {
    final sdk = Completer<FirebaseStatus>();
    final result = await waitForFirebaseStartup(
      sdk.future,
      isReleaseMode: true,
      timeout: const Duration(milliseconds: 10),
    );
    expect(result, FirebaseStatus.unavailable);
    // Completing the original operation does not change the timed-out result.
    sdk.complete(
      FirebaseStatus.ready,
    );
    expect(result, FirebaseStatus.unavailable);
    // A later caller can reuse that operation without another SDK call.
    expect(
      await waitForFirebaseStartup(
        sdk.future,
        isReleaseMode: true,
      ),
      FirebaseStatus.ready,
    );
  });

  test('successful initial startup preserves ready status', () async {
    expect(
      await waitForFirebaseStartup(
        Future.value(FirebaseStatus.ready),
        isReleaseMode: true,
      ),
      FirebaseStatus.ready,
    );
  });
}
