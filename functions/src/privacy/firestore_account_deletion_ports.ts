/**
 * Hesap silme portlarının ÜRETİM adaptörü (PR-R1B, İş Paketi 3).
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

import { ANALYSIS_REQUESTS_COLLECTION } from "../ai/analysis_journal.js";
import { FirestoreAnalysisPorts } from "../ai/firestore_ports.js";
import { raiseDeletionBarrier } from "./account_deletion_barrier.js";
import type { AccountDeletionPorts } from "./delete_account_service.js";

/** users/{uid} altında veri kaldıysa temizlik BİTMEMİŞTİR. */
const USER_SUBCOLLECTIONS = [
  "decisions",
  ANALYSIS_REQUESTS_COLLECTION,
  "analysisReservations",
  "rewardTickets",
  "subscriptions",
] as const;

export const firestoreAccountDeletionPorts: AccountDeletionPorts = {
  raiseBarrier: async (uid) => {
    await raiseDeletionBarrier(getFirestore(), uid, Date.now());
  },

  /**
   * Bariyerden önce açılmış AI rezervasyonlarını kapatır.
   *
   * Yalnız `olderThanMs` kadar YAŞLI kayıtlar zorla kapatılır: daha genç
   * bir rezervasyonu açan analyzeDecision çağrısı HÂLÂ çalışıyor olabilir
   * ve rezervasyonunu altından almak muhasebeyi bozardı. Bariyer yeni
   * rezervasyonu zaten engellediği için bu bekleme SINIRLIDIR.
   *
   * Kapanış mantığı KOPYALANMAZ: Paket 2C/2D'nin
   * `reconcileStaleReservations` primitive'i kullanılır.
   */
  drainOpenReservations: async (uid, olderThanMs) =>
    new FirestoreAnalysisPorts(uid).drainReservationsForDeletion({
      nowMs: Date.now(),
      settledAfterMs: olderThanMs,
      limit: 50,
    }),

  recursiveDeleteUser: async (uid) => {
    // BulkWriter tabanlı; alt koleksiyonları kendi gezer ve SINIRLI retry
    // uygular (sonsuz döngü yok).
    const db = getFirestore();
    await db.recursiveDelete(db.doc(`users/${uid}`));
  },

  deleteDocument: async (path) => {
    await getFirestore().doc(path).delete(); // belge yoksa no-op
  },

  userDataRemains: async (uid) => {
    const db = getFirestore();
    if ((await db.doc(`users/${uid}`).get()).exists) return true;
    for (const name of USER_SUBCOLLECTIONS) {
      const snap = await db.collection(`users/${uid}/${name}`).limit(1).get();
      if (!snap.empty) return true;
    }
    return false;
  },

  deleteAuthUser: async (uid) => {
    await getAuth().deleteUser(uid);
  },
};
