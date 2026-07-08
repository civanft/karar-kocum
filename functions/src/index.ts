/**
 * Cloud Functions giriş noktası — TEKNIK-MIMARI.md §5.1 fonksiyon envanteri.
 * Her fonksiyon kendi modülünde; burada yalnız export edilir.
 */
import { initializeApp } from "firebase-admin/app";

initializeApp();

// AI proxy boru hattı (§5.2): auth → oku → moderasyon → kota → LLM → doğrula → yaz
export { analyzeDecision } from "./ai/analyze.js";
export { suggestCriteria } from "./ai/suggestCriteria.js";
export { scoreOptions } from "./ai/scoreOptions.js";

// Abonelik: RevenueCat webhook → users/{uid}.plan (tek yazar)
export { revenuecatWebhook } from "./billing/revenuecatWebhook.js";

// KVKK/GDPR
export { deleteAccount } from "./privacy/deleteAccount.js";
export { exportData } from "./privacy/exportData.js";
