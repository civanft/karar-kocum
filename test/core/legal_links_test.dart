import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/legal_links.dart';

/// PR-LEGAL-1 — yasal bağlantı sözleşmesi (saf, Flutter'sız seam).
///
/// URL'ler TEK kaynakta durur; ekranlar sabit dize taşımaz. Mağaza
/// incelemesi kırık ya da yanlış bir bağlantıyı doğrudan reddeder.
void main() {
  const host = 'https://karar-kocum-production.web.app';

  test('privacy URL tam olarak /privacy', () {
    expect(LegalLinks.privacy, '$host/privacy');
  });

  test('terms URL tam olarak /terms', () {
    expect(LegalLinks.terms, '$host/terms');
  });

  test('support URL tam olarak /support', () {
    expect(LegalLinks.support, '$host/support');
  });

  test('üç bağlantı da HTTPS ve production hosting alanında', () {
    for (final url in LegalLinks.all) {
      final uri = Uri.parse(url);
      expect(uri.scheme, 'https', reason: '$url HTTPS değil');
      expect(uri.host, 'karar-kocum-production.web.app');
      expect(uri.hasQuery, isFalse, reason: '$url sorgu parametresi taşıyor');
      expect(uri.userInfo, isEmpty);
    }
  });

  test('allowlist tam olarak bu üç URL', () {
    expect(LegalLinks.all, [
      LegalLinks.privacy,
      LegalLinks.terms,
      LegalLinks.support,
    ]);
    expect(LegalLinks.all.toSet().length, 3);
  });

  test('allowlist dışındaki adresler reddedilir (open redirect koruması)', () {
    for (final bad in [
      'https://evil.example.com/privacy',
      'http://karar-kocum-production.web.app/privacy',
      '$host/privacy?next=https://evil.example.com',
      '$host/privacy/../../admin',
      'javascript:alert(1)',
      '',
    ]) {
      expect(
        LegalLinks.isAllowed(bad),
        isFalse,
        reason: '$bad allowlist dışına çıkmalıydı',
      );
    }
  });

  test('allowlist içindekiler kabul edilir', () {
    for (final url in LegalLinks.all) {
      expect(LegalLinks.isAllowed(url), isTrue);
    }
  });
}
