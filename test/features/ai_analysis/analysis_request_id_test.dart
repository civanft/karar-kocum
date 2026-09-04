import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/features/ai_analysis/domain/analysis_request_id.dart';

/// İŞ PAKETİ 2 / DİLİM F-1 — requestId üretimi ve kalıcılık sözleşmesi.
///
/// requestId backend idempotency ANAHTARIDIR:
///  - tek kullanıcı eylemi için BİR kez üretilir,
///  - belirsiz/retryable hatada KORUNUR (retry aynı anahtarla gider),
///  - açık "yeniden analiz" YENİ anahtar üretir,
///  - süreç kesintisinden sonra geri alınabilir,
///  - UID + decisionId alanına scope edilir,
///  - karar metni veya hassas içerik SAKLAMAZ.
void main() {
  group('biçim', () {
    test('backend şemasıyla uyumlu: 24 karakter, [a-z0-9]', () {
      for (var i = 0; i < 50; i++) {
        final id = newAnalysisRequestId();
        expect(id, matches(RegExp(r'^[a-z0-9]{24}$')));
      }
    });

    test('her çağrı farklı kimlik üretir', () {
      final ids = {for (var i = 0; i < 200; i++) newAnalysisRequestId()};
      expect(ids.length, 200);
    });
  });

  group('depolama anahtarı', () {
    test('UID ve decisionId alanına scope edilir', () {
      final a = pendingRequestKey(uid: 'u1', decisionId: 'd1');
      final b = pendingRequestKey(uid: 'u2', decisionId: 'd1');
      final c = pendingRequestKey(uid: 'u1', decisionId: 'd2');
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('anahtar karar metni veya hassas içerik taşımaz', () {
      final key = pendingRequestKey(uid: 'u1', decisionId: 'd1');
      expect(key, contains('u1'));
      expect(key, contains('d1'));
      expect(key.length, lessThan(120));
    });

    test('aynı girdi için kararlı (deterministik)', () {
      expect(
        pendingRequestKey(uid: 'u1', decisionId: 'd1'),
        pendingRequestKey(uid: 'u1', decisionId: 'd1'),
      );
    });
  });
}
