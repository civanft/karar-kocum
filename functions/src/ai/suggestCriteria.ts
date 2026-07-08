/** Eksik kriter önerisi — Sprint 2 stub'ı (bkz. analyze.ts notu). */
import { HttpsError, onCall } from "firebase-functions/v2/https";

export const suggestCriteria = onCall(() => {
  throw new HttpsError(
    "unimplemented",
    "suggestCriteria Sprint 2'de devreye girecek.",
  );
});
