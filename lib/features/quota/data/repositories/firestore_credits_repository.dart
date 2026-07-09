import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/limits.dart';
import '../../domain/repositories/credits_repository.dart';

/// users/{uid}.freeAnalysisCredits canlı okuması.
/// Alan yoksa (sunucu henüz lazy-init etmedi) başlangıç değeri kabul
/// edilir — sunucudaki peekCredits ile birebir aynı anlam.
class FirestoreCreditsRepository implements CreditsRepository {
  FirestoreCreditsRepository(this._firestore, {required String uid})
      : _uid = uid;

  final FirebaseFirestore _firestore;
  final String _uid;

  @override
  Stream<int> watchRemaining() =>
      _firestore.collection('users').doc(_uid).snapshots().map((snapshot) {
        final raw = snapshot.data()?['freeAnalysisCredits'];
        if (raw is num) {
          // Savunma: bozuk veri hiçbir zaman negatif gösterilmez.
          final value = raw.toInt();
          return value < 0 ? 0 : value;
        }
        return Limits.freeAnalysisCredits;
      });
}
