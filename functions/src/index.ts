/**
 * Cloud Functions giriş noktası — sadeleştirilmiş MVP envanteri (6B):
 * analyzeDecision (Gemini) + billing webhook + KVKK stub'ları.
 * (suggestCriteria/scoreOptions kaldırıldı — statik şablon kriterleri
 * ve premium AI puanlama sonraki sprintlerde.)
 */
import { initializeApp } from "firebase-admin/app";

initializeApp();

export { analyzeDecision } from "./ai/analyze.js";

// Abonelik: RevenueCat webhook → users/{uid}.plan (Sprint 5)
export { revenuecatWebhook } from "./billing/revenuecatWebhook.js";

// KVKK (Sprint 6)
export { deleteAccount } from "./privacy/deleteAccount.js";
export { exportData } from "./privacy/exportData.js";
