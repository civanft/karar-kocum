/**
 * Canlı smoke testi için Firebase istemci yapılandırması.
 *
 * API anahtarı YALNIZ ortamdan okunur; repoda varsayılan değer bulunmaz.
 * Anahtar yoksa hiçbir ağ isteği yapılmadan durulur ve hata mesajı yalnız
 * değişkenin ADINI anar — değeri asla yazdırmaz.
 *
 * Kullanım:
 *   FIREBASE_WEB_API_KEY=... node scripts/smoke/live_smoke_test.mjs
 *
 * Not: Firebase istemci anahtarı gizli bir sır değildir (her yayınlanan
 * uygulama binary'sinde bulunur); yine de repoda gereksiz kopya tutmamak
 * ve rotasyonu kolaylaştırmak için ortam değişkeninden alınır.
 */
export function readSmokeFirebaseConfig(env = process.env) {
  const apiKey = env.FIREBASE_WEB_API_KEY?.trim();
  if (!apiKey) {
    throw new Error(
      "FIREBASE_WEB_API_KEY ortam değişkeni gerekli; istemci anahtarını repoya yazmayın.",
    );
  }

  return {
    apiKey,
    appId: "1:740423241326:android:9faaa1a25d96871d04a07f",
    messagingSenderId: "740423241326",
    projectId: "karar-veriyorum-dev",
  };
}
