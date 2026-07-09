/**
 * Tier → model/limit eşlemesi — AI-ANALIZ-TASARIMI.md §6.1-6.2.
 * Model kimlikleri env ile ezilebilir (fiyat/kalite değişiminde deploy'suz
 * geçiş RC'ye taşınacak; env şimdilik yeterli kademe).
 */
export type Tier = "basic" | "advanced";

export interface TierConfig {
  model: string;
  maxOutputTokens: number;
}

export function tierConfig(tier: Tier): TierConfig {
  if (tier === "advanced") {
    return {
      model: process.env["OPENAI_MODEL_ADVANCED"] ?? "gpt-4o",
      maxOutputTokens: 1600,
    };
  }
  return {
    model: process.env["OPENAI_MODEL_BASIC"] ?? "gpt-4o-mini",
    maxOutputTokens: 900,
  };
}

/**
 * Kredi modeli (PR #6C-2): her kullanıcı 5 ücretsiz analiz KREDİSİYLE
 * başlar; her başarılı analiz 1 düşer; YENİLENMEZ (eski aylık modelin
 * yerini aldı). Flutter Limits.freeAnalysisCredits ile senkron.
 */
export const INITIAL_FREE_CREDITS = 5;

/** Günlük global harcama devre kesici eşiği (USD) — §4.3. */
export function dailySpendLimitUsd(): number {
  const raw = Number(process.env["AI_DAILY_SPEND_LIMIT_USD"]);
  return Number.isFinite(raw) && raw > 0 ? raw : 50;
}
