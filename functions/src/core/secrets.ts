/**
 * Secret Manager bağları — AI-ANALIZ-TASARIMI.md §2.
 * Değerler koda/env dosyasına yazılmaz; deploy'da fonksiyona bağlanır:
 *   npx firebase-tools functions:secrets:set OPENAI_API_KEY
 * Erişim yalnız secrets listesinde bu bağı bildiren fonksiyonlarda,
 * çalışma zamanında openaiApiKey.value() ile (PR #4'te kullanılacak).
 */
import { defineSecret } from "firebase-functions/params";

export const openaiApiKey = defineSecret("OPENAI_API_KEY");

/** RevenueCat webhook imza doğrulaması (Sprint 5'te kullanılacak). */
export const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");
