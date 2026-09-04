/// Analiz isteği idempotency anahtarı (İş Paketi 2).
///
/// Backend `analyzeDecision` payload'ı STRICT'tir ve `requestId` ZORUNLUDUR:
/// aynı (uid, requestId) için başarılı analiz sunucuda yalnız bir kez
/// uygulanır. Bu yüzden anahtar TEK kullanıcı eylemi için bir kez üretilir,
/// belirsiz hatalarda korunur ve yalnız açık "yeniden analiz" ile yenilenir.
///
/// Biçim backend şemasıyla birebir uyumludur: 24 karakter, yalnız [a-z0-9].
/// Yeni bir UUID bağımlılığı EKLENMEZ; kaynak `Random.secure()`.
library;

import 'dart:math';

const int analysisRequestIdLength = 24;

const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

final Random _secure = Random.secure();

/// Kriptografik olarak güvenli yeni istek kimliği.
/// 36^24 ≈ 2^124 — çakışma pratikte imkânsız.
String newAnalysisRequestId([Random? random]) {
  final r = random ?? _secure;
  return List.generate(
    analysisRequestIdLength,
    (_) => _alphabet[r.nextInt(_alphabet.length)],
  ).join();
}

/// Bekleyen isteğin cihazda saklandığı anahtar.
///
/// UID + decisionId alanına SCOPE edilir: farklı kullanıcı veya farklı karar
/// birbirinin anahtarını göremez. Karar metni ya da başka hassas içerik
/// SAKLANMAZ — yalnız kimlikler.
String pendingRequestKey({required String uid, required String decisionId}) =>
    'ai.pendingRequest.$uid.$decisionId';
