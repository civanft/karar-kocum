/** KVKK hesap silme kaskadı — Sprint 6 stub'ı (bkz. ai/analyze.ts notu). */
import { HttpsError, onCall } from "firebase-functions/v2/https";

export const deleteAccount = onCall(() => {
  throw new HttpsError(
    "unimplemented",
    "deleteAccount Sprint 6'da devreye girecek.",
  );
});
