/**
 * RevenueCat webhook → users/{uid}.plan güncelleme — Sprint 5.
 * GEÇİCİ STUB: imza doğrulaması ve plan yazımı henüz yok;
 * 501 döner ki yanlışlıkla canlıya bağlanırsa fark edilsin.
 */
import { onRequest } from "firebase-functions/v2/https";

export const revenuecatWebhook = onRequest((_req, res) => {
  res.status(501).send("revenuecatWebhook Sprint 5'te devreye girecek.");
});
