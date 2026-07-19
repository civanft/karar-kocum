/**
 * MERKEZİ YAPILANDIRMA — tüm maliyet/limit ayarları tek dosyada (hotfix).
 *
 * Her değer bir env değişkeniyle ezilebilir (deploy-zamanı, kod değişmeden).
 * İstemci tarafı karşılığı: Flutter lib/core/constants/limits.dart —
 * kredi ve karar sayıları iki tarafta senkron tutulmalıdır.
 *
 * MALIYET HEDEFİ (hotfix): aylık ≤ 5 USD. Bkz. maliyet projeksiyonu
 * docs/MALIYET-AUDIT.md güncellemesi.
 */

function envInt(name: string, fallback: number): number {
  const raw = Number(process.env[name]);
  return Number.isFinite(raw) && raw > 0 ? Math.trunc(raw) : fallback;
}

function envFloat(name: string, fallback: number): number {
  const raw = Number(process.env[name]);
  return Number.isFinite(raw) && raw > 0 ? raw : fallback;
}

function envStr(name: string, fallback: string): string {
  const raw = process.env[name];
  return raw && raw.length > 0 ? raw : fallback;
}

// ---- Gemini modeli ve çağrı korumaları ----
/** Düşük maliyetli model (flash-lite'a env ile düşülebilir). */
export const OPENAI_MODEL = envStr("OPENAI_MODEL", "gpt-4.1-mini");
export const MAX_OUTPUT_TOKENS = envInt("MAX_OUTPUT_TOKENS", 800);
/** Derlenmiş kullanıcı mesajı için sabit üst sınır (karakter). Y-3 alan
 *  limitleri şema düzeyinde sınırlar; bu, giriş-token patlamasına karşı
 *  ikinci savunma (~24K kr ≈ ~6K token, zengin bir kararı rahat karşılar). */
export const MAX_INPUT_CHARS = envInt("MAX_INPUT_CHARS", 24_000);
/** Tek OpenAI çağrısı için sert zaman aşımı (ms). onCall 60 sn'den kısa
 *  olmalı ki timeout bizim kontrolümüzde retryable hataya dönüşsün. */
export const OPENAI_TIMEOUT_MS = envInt("OPENAI_TIMEOUT_MS", 20_000);
/** OpenAI başına yeniden deneme sınırı (tek deneme). */
export const OPENAI_MAX_RETRIES = envInt("OPENAI_MAX_RETRIES", 1);

// ---- Kredi modeli (istemci Limits ile senkron) ----
/** Yeni kullanıcının başlangıç ücretsiz analiz kredisi (yenilenmez). */
export const INITIAL_FREE_CREDITS = envInt("INITIAL_FREE_CREDITS", 5);
/** Reklamla kazanılabilecek ödül kredisi ÜST SINIRI (hotfix madde 4). */
export const MAX_REWARD_CREDITS = envInt("MAX_REWARD_CREDITS", 5);

// ---- Karar sayısı (hotfix madde 5 — rules ile senkron) ----
export const MAX_DECISIONS_PER_USER = envInt("MAX_DECISIONS_PER_USER", 50);

// ---- Analiz limitleri (hotfix madde 1-3) ----
/** GLOBAL günlük analiz adedi (tüm kullanıcılar toplamı). 50 → 20. */
export const DAILY_GLOBAL_ANALYSIS_LIMIT = envInt(
  "DAILY_ANALYSIS_LIMIT",
  20,
);
/** GLOBAL günlük maliyet devre kesici (USD). 0.35 → 0.15. */
export const DAILY_SPEND_LIMIT_USD = envFloat("AI_DAILY_SPEND_LIMIT_USD", 0.15);
/** GLOBAL günlük token tüketim tavanı (giriş+çıkış). $0,15/gün USD
 *  kesiciyle tutarlı üçüncü emniyet: ~375K token ≈ $0,15 @ flash karma
 *  fiyat. Aşılırsa analiz 'daily-limit' ile durur. */
export const DAILY_TOKEN_LIMIT = envInt("DAILY_TOKEN_LIMIT", 375_000);
/** KULLANICI BAŞINA analiz limitleri — perDay eklendi (madde 3: 3/gün). */
export const PER_USER_ANALYZE_LIMITS = {
  perMinute: envInt("USER_ANALYZE_PER_MINUTE", 3),
  perHour: envInt("USER_ANALYZE_PER_HOUR", 10),
  perDay: envInt("USER_ANALYZE_PER_DAY", 3),
} as const;

// ---- Ödül bileti ----
export const REWARD_TICKET_TTL_MS = envInt(
  "REWARD_TICKET_TTL_MS",
  15 * 60_000,
);
export const MAX_PENDING_TICKETS = envInt("MAX_PENDING_TICKETS", 3);
export const REWARD_TICKET_LIMITS = {
  perMinute: envInt("REWARD_PER_MINUTE", 5),
  perHour: envInt("REWARD_PER_HOUR", 20),
} as const;
