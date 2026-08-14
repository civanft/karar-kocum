/**
 * Hesap silme portlarının ÜRETİM adaptörü (PR-R1B).
 *
 * Ayrı dosyada olmasının nedeni: bu sınır (Admin SDK ↔ Firestore/Auth)
 * gerçek emülatöre karşı entegrasyon testinden geçirilir. Callable
 * handler'ın içinde gömülü kalsaydı yalnız mock'lar test edilirdi.
 *
 * Admin SDK Rules'u BYPASS eder — kaskad için gereklidir; bu yüzden bu
 * dosyanın çağrıldığı tek yer doğrulanmış oturumdan uid alan handler'dır.
 */
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import type { AccountDeletionPorts } from "./delete_account_service.js";

export const firestoreAccountDeletionPorts: AccountDeletionPorts = {
  recursiveDeleteUser: async (uid) => {
    // BulkWriter tabanlı; alt koleksiyonları kendi gezer ve SINIRLI retry
    // uygular (sonsuz döngü yok).
    const db = getFirestore();
    await db.recursiveDelete(db.doc(`users/${uid}`));
  },
  deleteDocument: async (path) => {
    await getFirestore().doc(path).delete(); // belge yoksa no-op
  },
  deleteAuthUser: async (uid) => {
    await getAuth().deleteUser(uid);
  },
};
