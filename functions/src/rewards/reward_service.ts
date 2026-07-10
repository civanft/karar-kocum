/**
 * Ödüllü reklam kredi servisi — PR #7A.
 *
 * Akış: istemci bilet açar (createTicket) → bileti custom_data olarak
 * reklama iliştirir → reklam TAMAMLANINCA AdMob'un SUNUCUSU callback'i
 * imzalı çağırır → grantFromCallback tek transaction'da bileti
 * pending→granted çevirip rewardCredits +1 yazar.
 *
 * Güvence eşlemesi:
 *  - "Reklam tamamlanmadan kredi yok": krediyi yalnız SSV callback'i
 *    verir; istemcide grant yolu yok (rules da alanı kapatır).
 *  - "Transaction": grantIfPending tek Firestore transaction'ı.
 *  - "Çifte ödül engellenir": bilet durum makinesi pending→granted TEK
 *    YÖNLÜ; aynı biletle ikinci callback 'duplicate' döner, kredi yazmaz.
 */
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";

export const TICKET_TTL_MS = 15 * 60_000; // reklam izleme penceresi
export const MAX_PENDING_TICKETS = 3; // bilet stoklama/spam freni

export type GrantOutcome =
  | "granted"
  | "duplicate"
  | "expired"
  | "unknown"
  | "user_mismatch";

export interface TicketStore {
  countPending(uid: string, nowMs: number): Promise<number>;
  create(uid: string, expiresAtMs: number): Promise<string>; // ticketId
  /** TEK transaction: bilet doğrula + granted işaretle + kredi +1. */
  grantIfPending(
    uid: string,
    ticketId: string,
    transactionId: string,
    nowMs: number,
  ): Promise<GrantOutcome>;
}

export async function createRewardTicket(
  store: TicketStore,
  uid: string,
  now: () => number = Date.now,
): Promise<{ ticketId: string; expiresAtMs: number }> {
  const nowMs = now();
  if ((await store.countPending(uid, nowMs)) >= MAX_PENDING_TICKETS) {
    throw new AppError(
      "rate-limited",
      "Bekleyen çok fazla ödül isteğin var — önce reklamı tamamla.",
      { retryAfterSeconds: 60 },
    );
  }
  const expiresAtMs = nowMs + TICKET_TTL_MS;
  const ticketId = await store.create(uid, expiresAtMs);
  return { ticketId, expiresAtMs };
}

export async function grantFromCallback(
  store: TicketStore,
  payload: { userId: string; customData: string; transactionId: string },
  now: () => number = Date.now,
): Promise<GrantOutcome> {
  if (!payload.userId || !payload.customData) return "unknown";
  return store.grantIfPending(
    payload.userId,
    payload.customData,
    payload.transactionId,
    now(),
  );
}

// ---- Üretim deposu ----

export class FirestoreTicketStore implements TicketStore {
  private get db() {
    return getFirestore();
  }

  private tickets(uid: string) {
    return this.db.collection(`users/${uid}/rewardTickets`);
  }

  async countPending(uid: string, nowMs: number): Promise<number> {
    const snapshot = await this.tickets(uid)
      .where("status", "==", "pending")
      .where("expiresAt", ">", Timestamp.fromMillis(nowMs))
      .get();
    return snapshot.size;
  }

  async create(uid: string, expiresAtMs: number): Promise<string> {
    const ref = await this.tickets(uid).add({
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(expiresAtMs),
    });
    return ref.id;
  }

  async grantIfPending(
    uid: string,
    ticketId: string,
    transactionId: string,
    nowMs: number,
  ): Promise<GrantOutcome> {
    const ticketRef = this.tickets(uid).doc(ticketId);
    const userRef = this.db.doc(`users/${uid}`);

    return this.db.runTransaction(async (tx) => {
      const ticket = await tx.get(ticketRef);
      if (!ticket.exists) return "unknown";

      const data = ticket.data()!;
      if (data["status"] === "granted") return "duplicate"; // çifte ödül ✗
      if (data["status"] !== "pending") return "unknown";

      const expiresAt = data["expiresAt"] as Timestamp | undefined;
      if (!expiresAt || expiresAt.toMillis() < nowMs) {
        tx.update(ticketRef, { status: "expired" });
        return "expired";
      }

      tx.update(ticketRef, {
        status: "granted",
        transactionId,
        grantedAt: FieldValue.serverTimestamp(),
      });
      tx.set(
        userRef,
        { rewardCredits: FieldValue.increment(1) },
        { merge: true },
      );
      return "granted";
    });
  }
}
