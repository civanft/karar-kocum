/**
 * Rezervasyon için KANITLANABİLİR kullanım ÜST SINIRI (İş Paketi 2D).
 *
 * NEDEN GEREKLİ: sağlayıcının gerçek token tüketimi ancak çağrı bittikten
 * sonra bilinir. Bütçe kontrolü ise çağrıdan ÖNCE yapılmak zorundadır; aksi
 * halde eşzamanlı istekler kontrolü aynı anda geçip günlük tavanı aşar.
 * Bu yüzden çağrı öncesinde bir üst sınır rezerve edilir, çağrı bitince
 * rezervasyon serbest bırakılıp yerine GERÇEK tüketim yazılır.
 *
 * ═══ NEDEN `ceil(karakter / 3)` DEĞİL ═══
 *
 * 2B/2C'de girdi tokenleri `ceil(promptChars / 3)` ile tahmin ediliyor ve
 * bu "konservatif üst sınır" gibi kullanılıyordu. Bu İDDİA YANLIŞTIR:
 * karakter sayısı ile token sayısı arasında böyle bir üst sınır ilişkisi
 * yoktur. Gerçek `o200k_base` tokenizer'ıyla ölçülen karşı örnekler
 * (testlerde koşuyor):
 *
 *   emoji dizisi      : 11 tahmin < 27 gerçek token
 *   birleşik Unicode  :  8 tahmin < 15 gerçek token
 *   CJK               :  9 tahmin < 20 gerçek token
 *   tekrarlı "ı" ×300 : 100 tahmin < 300 gerçek token
 *
 * Yani bütçe kontrolü delinebiliyordu.
 *
 * ═══ ÜST SINIR KANITI ═══
 *
 * GPT modelleri byte-level BPE kullanır. Böyle bir kodlamada:
 *   1. metin önce UTF-8 baytlarına çevrilir,
 *   2. her token BOŞ OLMAYAN bir bayt dizisine çözülür,
 *   3. tokenlerin bayt çözümleri girdiyi tam olarak PARÇALAR (örtüşme ve
 *      boşluk yok).
 * Her token en az bir bayt tükettiğine göre:
 *
 *   token_sayısı ≤ UTF-8_bayt_sayısı
 *
 * Bu eşitsizlik kodlamanın KİMLİĞİNDEN bağımsızdır: o200k_base, cl100k_base
 * ya da başka bir byte-level BPE için aynı şekilde geçerlidir. Dolayısıyla
 * `gpt-4.1-mini`'nin hangi kodlamayı kullandığını bilmek gerekmez — üretim
 * kodunun tokenizer'a bağımlılığı YOKTUR.
 *
 * Testler bu sınırı gerçek tokenizer'a (js-tiktoken, YALNIZ devDependency)
 * karşı hem örnek tablosuyla hem property testiyle doğrular.
 *
 * ═══ SINIRIN GEVŞEKLİĞİ VE NEDEN KABUL EDİLEBİLİR ═══
 *
 * Bayt sınırı gerçek tüketimin ~3 katı olabilir. Bu, günlük TOPLAMLARI
 * etkilemez: rezervasyon geçicidir, finalize'da serbest bırakılıp yerine
 * GERÇEK tüketim yazılır. Yalnız EŞZAMANLI kabul başlığını daraltır —
 * yani fazla rezerve etmek erken durdurur, az rezerve etmek tavanı
 * deldirir. Yön bilinçlidir.
 */
import { AppError } from "../core/errors.js";
import { computeCostUsd } from "./cost_control.js";

/**
 * Sohbet mesajı başına çerçeveleme payı (rol belirteçleri, ayırıcılar).
 * Kesin değer modele özgüdür ve belgelenmiş tek bir sayı yoktur; bu yüzden
 * OpenAI cookbook'undaki ~3 token/mesaj gözleminin belirgin şekilde üstünde,
 * GÜVENLİ bir sabit seçilmiştir.
 */
export const FRAMING_TOKENS_PER_MESSAGE = 8;

/** Yanıt hazırlama + istek düzeyi çerçeveleme için ek güvenli pay. */
export const FRAMING_TOKENS_OVERHEAD = 8;

/** Taşma koruması: bunun üstündeki bir tahmin istek hatası sayılır. */
export const MAX_ESTIMATE_TOKENS = 5_000_000;

export interface UsageEstimate {
  tokens: number;
  usd: number;
}

/**
 * Bir metnin token sayısı için KANITLANABİLİR üst sınır: UTF-8 bayt sayısı.
 * Yukarıdaki kanıta bakınız.
 */
export function utf8UpperBoundTokens(text: string): number {
  return Buffer.byteLength(text, "utf8");
}

function assertSafeCount(value: number, field: string): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new AppError(
      "invalid-argument",
      "Analiz isteği işlenemedi — lütfen tekrar dene.",
      { field },
    );
  }
}

/**
 * Sistem + kullanıcı mesajı, çerçeveleme payı ve çıkış tavanının TAMAMINI
 * kapsayan üst sınır. USD, giriş ve çıkış tokenleri AYRI fiyatlandırılarak
 * hesaplanır (çıkış tokeni girişten pahalıdır; birleşik sayıyı ucuz giriş
 * fiyatından hesaplamak maliyeti olduğundan düşük gösterirdi).
 */
export function estimateUsage(params: {
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  model: string;
}): UsageEstimate {
  assertSafeCount(params.maxOutputTokens, "maxOutputTokens");

  const content =
    utf8UpperBoundTokens(params.systemPrompt) +
    utf8UpperBoundTokens(params.userPrompt);
  const framing = 2 * FRAMING_TOKENS_PER_MESSAGE + FRAMING_TOKENS_OVERHEAD;
  const inputTokens = content + framing;
  const outputTokens = params.maxOutputTokens;

  assertSafeCount(inputTokens, "inputTokens");
  const total = inputTokens + outputTokens;
  assertSafeCount(total, "tokens");
  if (total > MAX_ESTIMATE_TOKENS) {
    throw new AppError(
      "invalid-argument",
      "Analiz isteği işlenemedi — lütfen tekrar dene.",
      { field: "tokens" },
    );
  }

  return {
    tokens: total,
    usd: computeCostUsd(params.model, { inputTokens, outputTokens }),
  };
}
