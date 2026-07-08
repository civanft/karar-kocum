/** AI otomatik puanlama (premium) — Sprint 2 stub'ı (bkz. analyze.ts notu). */
import { HttpsError, onCall } from "firebase-functions/v2/https";

export const scoreOptions = onCall(() => {
  throw new HttpsError(
    "unimplemented",
    "scoreOptions Sprint 2'de devreye girecek.",
  );
});
