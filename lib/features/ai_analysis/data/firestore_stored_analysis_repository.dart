import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/ai_analysis.dart';
import '../domain/repositories/stored_analysis_repository.dart';

/// Kalıcı analiz okumasının Firestore adaptörü (İş Paketi 4 / Dilim A).
///
/// Yol backend ile SENKRON: `users/{uid}/decisions/{decisionId}/aiAnalyses/latest`
/// (functions `LATEST_ANALYSIS_ID`). Rules bu belgeyi yalnız sahibine ve
/// yalnız hesap silme bariyeri yokken okutur.
class FirestoreStoredAnalysisRepository implements StoredAnalysisRepository {
  const FirestoreStoredAnalysisRepository({
    required FirebaseFirestore firestore,
    required String uid,
  })  : _db = firestore,
        _uid = uid;

  final FirebaseFirestore _db;
  final String _uid;

  static const _latestId = 'latest';

  @override
  Stream<AiAnalysis?> watchLatest(String decisionId) => _db
          .doc('users/$_uid/decisions/$decisionId/aiAnalyses/$_latestId')
          .snapshots()
          .map((snapshot) {
        if (!snapshot.exists) return null;
        // Bozuk belge burada FIRLATIR; çağıran güvenli okuma hatası gösterir.
        return AiAnalysisMapper.fromStored(snapshot.data());
      });
}
