import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/ai_consent.dart';
import '../domain/repositories/ai_consent_repository.dart';

/// `users/{uid}/privacy/aiConsent` adaptörü.
///
/// Yol backend ile SENKRON (`functions/src/privacy/ai_consent.ts`
/// `AI_CONSENT_PATH`) ve hesap silme kaskadının taradığı alt koleksiyondadır.
class FirestoreAiConsentRepository implements AiConsentRepository {
  const FirestoreAiConsentRepository({
    required FirebaseFirestore firestore,
    required String uid,
  })  : _db = firestore,
        _uid = uid;

  final FirebaseFirestore _db;
  final String _uid;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.doc('users/$_uid/privacy/aiConsent');

  @override
  Stream<AiConsent?> watch() => _ref.snapshots().map((snapshot) {
        if (!snapshot.exists) return null;
        return _fromStored(snapshot.data());
      });

  /// KATI eşleme: bozuk belge sessizce "izin var" olmaz.
  static AiConsent? _fromStored(Map<String, Object?>? data) {
    if (data == null) return null;
    final granted = data['granted'];
    final version = data['version'];
    if (granted is! bool || version is! int) return null;
    return AiConsent(
      granted: granted,
      version: version,
      updatedAt: _readTimestamp(data['updatedAt']),
    );
  }

  static DateTime? _readTimestamp(Object? value) {
    if (value == null) return null;
    try {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> grant() => _write(granted: true);

  @override
  Future<void> withdraw() => _write(granted: false);

  /// Alan kümesi rules'daki KATI şemayla birebir; zaman SUNUCUDAN.
  Future<void> _write({required bool granted}) => _ref.set({
        'granted': granted,
        'version': currentAiConsentVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
