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
        final data = snapshot.data();
        // İki havuz (7A): free lazy-init'li, reward yazılmamışsa 0.
        // Sunucudaki readPools ile birebir aynı anlam; bozuk/negatif
        // veri hiçbir zaman negatif gösterilmez.
        int clamp(Object? raw, int fallback) =>
            raw is num ? (raw.toInt() < 0 ? 0 : raw.toInt()) : fallback;
        final free =
            clamp(data?['freeAnalysisCredits'], Limits.freeAnalysisCredits);
        final reward = clamp(data?['rewardCredits'], 0);
        return free + reward;
      });
}
