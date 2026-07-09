/**
 * MVP yapılandırması — tek model (6B: tier sistemi kaldırıldı).
 */
export const GEMINI_MODEL =
  process.env["GEMINI_MODEL"] ?? "gemini-2.0-flash";

export const MAX_OUTPUT_TOKENS = 800;

/**
 * Kredi modeli (PR #6C-2): her kullanıcı 5 ücretsiz analiz KREDİSİYLE
 * başlar; her başarılı analiz 1 düşer; YENİLENMEZ.
 * Flutter Limits.freeAnalysisCredits ile senkron.
 */
export const INITIAL_FREE_CREDITS = 5;

/**
 * Günlük global harcama devre kesici eşiği (USD) — MALIYET-AUDIT R1:
 * $0,35/gün ≈ $10,5/ay fiziksel tavan (proje bütçesi ≤ $10/ay).
 */
export function dailySpendLimitUsd(): number {
  const raw = Number(process.env["AI_DAILY_SPEND_LIMIT_USD"]);
  return Number.isFinite(raw) && raw > 0 ? raw : 0.35;
}
