import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/config/firebase_bootstrap.dart';

/// PR-RELEASE-1 — Firebase başlatma hata politikası (saf seam).
///
/// Release'de Firebase'e bağlanılamadığında uygulama YEREL MODA DÜŞMEZ:
/// yerel mod in-memory depo, sahte kredi ve mock AI sonucu demektir; bu,
/// kullanıcıya kalıcı sanılan veri ve uydurma analiz gösterirdi.
/// kReleaseMode doğrudan test edilemez, bu yüzden politika saf bir
/// fonksiyona ayrıldı.
void main() {
  group('firebaseFailureStatus', () {
    test('release hatası → unavailable (fail-closed)', () {
      expect(
        firebaseFailureStatus(isReleaseMode: true),
        FirebaseStatus.unavailable,
      );
    });

    test('debug/test hatası → localMode (geliştirme akışı korunur)', () {
      expect(
        firebaseFailureStatus(isReleaseMode: false),
        FirebaseStatus.localMode,
      );
    });

    test('iki mod ASLA aynı sonucu vermez', () {
      expect(
        firebaseFailureStatus(isReleaseMode: true),
        isNot(firebaseFailureStatus(isReleaseMode: false)),
      );
    });

    test('saf: aynı girdi aynı sonucu verir, yan etkisi yok', () {
      expect(
        firebaseFailureStatus(isReleaseMode: true),
        firebaseFailureStatus(isReleaseMode: true),
      );
    });
  });

  group('FirebaseStatus', () {
    test('unavailable ayrı bir durum olarak tanımlı', () {
      expect(FirebaseStatus.values, contains(FirebaseStatus.unavailable));
      expect(FirebaseStatus.values, hasLength(3));
    });

    test('unavailable ne ready ne localMode', () {
      expect(FirebaseStatus.unavailable, isNot(FirebaseStatus.ready));
      expect(FirebaseStatus.unavailable, isNot(FirebaseStatus.localMode));
    });
  });
}
