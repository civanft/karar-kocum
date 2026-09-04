import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/data/pending_analysis_request_store.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/analysis_request_id.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İŞ PAKETİ 2 / DİLİM F-2 — bekleyen requestId kalıcılığı.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PendingAnalysisRequestStore> store() async =>
      PrefsPendingAnalysisRequestStore(await SharedPreferences.getInstance());

  test('kayıt yoksa null döner', () async {
    final s = await store();
    expect(await s.read(uid: 'u1', decisionId: 'd1'), isNull);
  });

  test('yazılan kimlik süreç kesintisinden sonra geri alınır', () async {
    final id = newAnalysisRequestId();
    await (await store()).write(
      uid: 'u1',
      decisionId: 'd1',
      requestId: id,
    );

    // Yeni örnek = uygulama yeniden başlatıldı.
    final fresh = await store();
    expect(await fresh.read(uid: 'u1', decisionId: 'd1'), id);
  });

  test('UID ve decisionId alanına scope edilir', () async {
    final s = await store();
    final id = newAnalysisRequestId();
    await s.write(uid: 'u1', decisionId: 'd1', requestId: id);

    expect(await s.read(uid: 'u2', decisionId: 'd1'), isNull);
    expect(await s.read(uid: 'u1', decisionId: 'd2'), isNull);
  });

  test('clear yalnız kendi alanını siler', () async {
    final s = await store();
    final a = newAnalysisRequestId();
    final b = newAnalysisRequestId();
    await s.write(uid: 'u1', decisionId: 'd1', requestId: a);
    await s.write(uid: 'u1', decisionId: 'd2', requestId: b);

    await s.clear(uid: 'u1', decisionId: 'd1');

    expect(await s.read(uid: 'u1', decisionId: 'd1'), isNull);
    expect(await s.read(uid: 'u1', decisionId: 'd2'), b);
  });

  test('clearAll tüm bekleyen istekleri siler (hesap silme akışı)', () async {
    final s = await store();
    final id = newAnalysisRequestId();
    await s.write(uid: 'u1', decisionId: 'd1', requestId: id);
    final id2 = newAnalysisRequestId();
    await s.write(uid: 'u2', decisionId: 'd9', requestId: id2);

    await s.clearAll();

    expect(await s.read(uid: 'u1', decisionId: 'd1'), isNull);
    expect(await s.read(uid: 'u2', decisionId: 'd9'), isNull);
  });

  test('clearAll ilgisiz tercihlere DOKUNMAZ', () async {
    const other = 'journey.followUpOptedIn';
    SharedPreferences.setMockInitialValues(<String, Object>{
      other: <String>['d1'],
    });
    final prefs = await SharedPreferences.getInstance();
    final s = PrefsPendingAnalysisRequestStore(prefs);
    final id = newAnalysisRequestId();
    await s.write(uid: 'u1', decisionId: 'd1', requestId: id);

    await s.clearAll();

    expect(prefs.getStringList(other), ['d1']);
  });

  test('bozuk/biçimsiz kayıt null gibi ele alınır', () async {
    SharedPreferences.setMockInitialValues({
      pendingRequestKey(uid: 'u1', decisionId: 'd1'): 'GEÇERSİZ-BİÇİM',
    });
    final s = PrefsPendingAnalysisRequestStore(
      await SharedPreferences.getInstance(),
    );
    expect(await s.read(uid: 'u1', decisionId: 'd1'), isNull);
  });

  test('karar metni veya hassas içerik SAKLANMAZ', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = PrefsPendingAnalysisRequestStore(prefs);
    final id = newAnalysisRequestId();
    await s.write(uid: 'u1', decisionId: 'd1', requestId: id);

    final dump = prefs.getKeys().map((k) => '$k=${prefs.get(k)}').join('|');
    expect(dump, isNot(contains('Telefon')));
    expect(dump.length, lessThan(200));
  });
}
