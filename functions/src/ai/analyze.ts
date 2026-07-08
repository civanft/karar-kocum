/**
 * AI analiz proxy'si — TEKNIK-MIMARI.md §5.2 boru hattı.
 * Sprint 2'de doldurulacak GEÇİCİ STUB: imza ve dosya yapısı sabit,
 * iş mantığı yok. Çağrılırsa istemciye net "unimplemented" döner.
 */
import { HttpsError, onCall } from "firebase-functions/v2/https";

export const analyzeDecision = onCall(() => {
  throw new HttpsError(
    "unimplemented",
    "analyzeDecision Sprint 2'de devreye girecek.",
  );
});
