/**
 * Cloud Functions giriş noktası — MVP DEPLOY YÜZEYİ (PR #6E-3A, PR-R1).
 *
 * Yalnız CANLIDA İŞ GÖREN fonksiyonlar export edilir. Boş stub'lar
 * (revenuecatWebhook / exportData) index'ten ÇIKARILDI:
 * deploy edilirlerse iş yapmayan ama saldırı yüzeyi + soğuk-başlatma
 * maliyeti taşıyan instance'lar olurlardı. Kaynak dosyaları duruyor;
 * ilgili sprintte (billing Sprint 5, KVKK Sprint 6) gerçek gövdeyle
 * birlikte yeniden export edilecek.
 */
import { initializeApp } from "firebase-admin/app";

initializeApp();

// AI analiz (OpenAI, sunucu tarafı) — çekirdek özellik.
export { analyzeDecision } from "./ai/analyze.js";

// Ödüllü reklam kredisi (7A): bilet callable'ı + AdMob SSV callback'i.
export { createRewardTicket } from "./rewards/createRewardTicket.js";
export { admobRewardCallback } from "./rewards/admobRewardCallback.js";

// KVKK / Store P0: uygulama içinden hesap + veri silme (PR-R1).
export { deleteAccount } from "./privacy/deleteAccount.js";
