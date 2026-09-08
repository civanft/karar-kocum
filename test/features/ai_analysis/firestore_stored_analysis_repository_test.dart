import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/firestore_stored_analysis_repository.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/entities/ai_analysis.dart';

/// İŞ PAKETİ 4 / DİLİM A — kalıcı analiz okuma adaptörü.
///
/// Yol backend ile SENKRON olmalı (`LATEST_ANALYSIS_ID = 'latest'`): yanlış
/// yol sessizce "analiz yok" gibi görünür ve kullanıcı ödediği sonucu
/// kaybeder. Bozuk belge ise sessizce boş-ama-başarılı bir analize
/// DÖNÜŞMEMELİ.
void main() {
  const uid = 'u1';
  const decisionId = 'd1';

  late FakeFirebaseFirestore db;
  late FirestoreStoredAnalysisRepository repo;

  const path = 'users/$uid/decisions/$decisionId/aiAnalyses/latest';

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreStoredAnalysisRepository(firestore: db, uid: uid);
  });

  Map<String, Object?> validDoc() => {
        'summary': 'Özet',
        'strengths': ['a'],
        'weaknesses': ['b'],
        'risks': ['c'],
        'recommendation': 'Öneri',
        'confidence': 'high',
        'generatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 4)),
      };

  test('backend ile AYNI yoldan okur', () async {
    await db.doc(path).set(validDoc());

    final analysis = await repo.watchLatest(decisionId).first;

    expect(analysis, isNotNull);
    expect(analysis!.summary, 'Özet');
    expect(analysis.recommendation, 'Öneri');
    expect(analysis.confidence, AnalysisConfidence.high);
    // Firestore Timestamp yerel saate çözülür; anı karşılaştır.
    expect(analysis.generatedAt?.toUtc(), DateTime.utc(2026, 3, 4));
  });

  test('belge YOKSA null yayınlar (hata değil)', () async {
    expect(await repo.watchLatest(decisionId).first, isNull);
  });

  test('BAŞKA kullanıcının/kararın belgesi okunmaz', () async {
    await db
        .doc('users/u2/decisions/$decisionId/aiAnalyses/latest')
        .set(validDoc());
    await db
        .doc('users/$uid/decisions/other/aiAnalyses/latest')
        .set(validDoc());

    expect(await repo.watchLatest(decisionId).first, isNull);
  });

  test('BOZUK belge sessizce boş başarıya dönüşmez — akış HATA verir',
      () async {
    await db.doc(path).set({'summary': 'Özet'}); // eksik alanlar

    expect(
      repo.watchLatest(decisionId),
      emitsError(isA<StoredAnalysisFormatException>()),
    );
  });

  test('canlı akış: sonradan yazılan analiz YAYINLANIR', () async {
    final emissions = <AiAnalysis?>[];
    final sub = repo.watchLatest(decisionId).listen(emissions.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    await db.doc(path).set(validDoc());
    await Future<void>.delayed(Duration.zero);

    expect(emissions.first, isNull);
    expect(emissions.last?.summary, 'Özet');
  });
}
