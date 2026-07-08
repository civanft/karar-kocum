/** KVKK veri dışa aktarma — Sprint 6 stub'ı (bkz. ai/analyze.ts notu). */
import { HttpsError, onCall } from "firebase-functions/v2/https";

export const exportData = onCall(() => {
  throw new HttpsError(
    "unimplemented",
    "exportData Sprint 6'da devreye girecek.",
  );
});
