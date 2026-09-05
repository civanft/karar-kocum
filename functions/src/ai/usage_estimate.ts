/**
 * Rezervasyon için KONSERVATİF kullanım tahmini (İş Paketi 2B).
 *
 * NEDEN GEREKLİ: sağlayıcının gerçek token tüketimi ancak çağrı bittikten
 * sonra bilinir. Bütçe kontrolü ise çağrıdan ÖNCE yapılmak zorundadır; aksi
 * halde eşzamanlı istekler kontrolü aynı anda geçip günlük tavanı aşar.
 * Bu yüzden çağrı öncesinde bir ÜST SINIR rezerve edilir, çağrı bitince
 * rezervasyon serbest bırakılıp yerine GERÇEK tüketim yazılır.
 *
 * FORMÜL — girdi tokenleri karakter sayısından tahmin edilir:
 *
 *   estimatedInputTokens = ceil(promptChars / CHARS_PER_TOKEN)
 *   estimatedOutputTokens = maxOutputTokens        (modelin tavanı)
 *   estimatedTokens = estimatedInputTokens + estimatedOutputTokens
 *   estimatedUsd = computeCostUsd(model, {input, output})
 *
 * CHARS_PER_TOKEN = 3 seçildi. GPT tokenizer'ı İngilizce'de ~4 karakter/token
 * üretir; Türkçe eklemeli yapısı ve UTF-8 çok baytlı karakterleri nedeniyle
 * token başına DAHA AZ karakter düşer. 3 kullanmak tahmini yukarı çeker —
 * yani rezervasyon gerçekten tüketilenden fazla olur. Yönü bilinçlidir:
 * bütçe kontrolünde fazla rezerve etmek erken durdurur, az rezerve etmek
 * tavanı deldirir.
 *
 * SINIR — BU BİR TAHMİNDİR, ÖLÇÜM DEĞİLDİR. "Yaklaşık" bir üst sınır sert
 * bütçe garantisi olarak sunulamaz: tokenizer davranışı modele göre değişir.
 * Garanti ettiği şey şudur ve yalnız budur: eşzamanlı istekler bütçe
 * kontrolünü AYNI ANDA geçemez, çünkü kontrol ve rezervasyon tek transaction
 * içindedir. Gerçek tüketim finalization'da tahminin YERİNE yazılır, böylece
 * sayaçlar uzun vadede gerçeği izler.
 */
import { computeCostUsd } from "./cost_control.js";

/** Türkçe metin için ihtiyatlı (yukarı yuvarlayan) karakter/token oranı. */
export const CHARS_PER_TOKEN = 3;

export interface UsageEstimate {
  tokens: number;
  usd: number;
}

export function estimateUsage(params: {
  promptChars: number;
  maxOutputTokens: number;
  model: string;
}): UsageEstimate {
  const inputTokens = Math.ceil(params.promptChars / CHARS_PER_TOKEN);
  const outputTokens = params.maxOutputTokens;
  return {
    tokens: inputTokens + outputTokens,
    usd: computeCostUsd(params.model, { inputTokens, outputTokens }),
  };
}
