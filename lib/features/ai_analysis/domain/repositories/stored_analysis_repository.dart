import '../entities/ai_analysis.dart';

/// KALICI analizin okuma portu (İş Paketi 4 / Dilim A).
///
/// Backend, üretilen analizi `aiAnalyses/latest` altında saklar. İstemci bunu
/// okumadığı için uygulama kapanıp açıldığında kullanıcı ödediği analizi
/// kaybediyor ve karşısında yeniden "AI Analizini Başlat" CTA'sı buluyordu —
/// tekrar basmak YENİ bir kredi harcaması demekti.
///
/// Port SALT OKUNURDUR: analiz üretimi callable'ın işidir. Firestore tipleri
/// bu arayüzün arkasında kalır; domain ve presentation katmanları görmez.
abstract interface class StoredAnalysisRepository {
  /// Kararın kalıcı en güncel analizini izler.
  ///
  ///  - analiz yoksa `null` yayar (kullanıcı CTA görür);
  ///  - belge bozuksa ya da okuma reddedilirse akış HATA yayar — sessizce
  ///    boş başarıya DÖNÜŞMEZ.
  Stream<AiAnalysis?> watchLatest(String decisionId);
}

/// Firebase kullanılamıyorken ya da oturum yokken kullanılan fail-closed port.
///
/// Boş UID ya da `local-user` ile Firestore yolu KURULMAZ: aksi hâlde
/// kullanıcılar arası bir belge yolu oluşabilirdi.
class UnavailableStoredAnalysisRepository implements StoredAnalysisRepository {
  const UnavailableStoredAnalysisRepository();

  @override
  Stream<AiAnalysis?> watchLatest(String decisionId) =>
      Stream<AiAnalysis?>.value(null);
}
