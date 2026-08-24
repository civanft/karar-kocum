/**
 * AdMob SSV callback'i — ödülün TEK veriliş yolu (PR #7A).
 * AdMob'un sunucusu reklam TAMAMLANINCA çağırır; imza doğrulanmadan
 * hiçbir şey yazılmaz. Yanıt politikası:
 *   - imza geçersiz → 403 (saldırı sinyali)
 *   - granted/duplicate/expired/unknown → 200 (AdMob retry fırtınası
 *     olmasın; duplicate 200 dönmek İDEMPOTENCY gereğidir)
 */
import { onRequest } from "firebase-functions/v2/https";

import { functionRegion } from "../core/deployment.js";
import { logger } from "firebase-functions/v2";

import { grantFromCallback, FirestoreTicketStore } from "./reward_service.js";
import { createGstaticKeyProvider, SsvVerifier } from "./ssv_verifier.js";

const verifier = new SsvVerifier(createGstaticKeyProvider());

export const admobRewardCallback = onRequest(
  {
    region: functionRegion,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (request, response) => {
    const rawQuery = request.url.split("?")[1] ?? "";

    const payload = await verifier.verify(rawQuery);
    if (!payload) {
      logger.warn("reward_callback_invalid_signature");
      response.status(403).send("invalid signature");
      return;
    }

    const outcome = await grantFromCallback(
      new FirestoreTicketStore(),
      payload,
    );
    logger.info("reward_callback", {
      outcome,
      transactionId: payload.transactionId,
      // uid loglanmaz (PII kuralı); bilet kimliği yeterli iz
      ticketId: payload.customData,
    });
    response.status(200).send(outcome);
  },
);
