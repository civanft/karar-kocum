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
import {
  accountDeletingError,
  barrierRef,
} from "../privacy/account_deletion_barrier.js";
import {
  MAX_PENDING_TICKETS,
  MAX_REWARD_CREDITS,
  REWARD_TICKET_TTL_MS,
} from "../config.js";

export type GrantOutcome =
  | "granted"
  | "duplicate"
  | "expired"
  | "unknown"
  | "capped" // ödül tavanı (MAX_REWARD_CREDITS) — kredi verilmez
  // Hesap silme bariyeri açık (İş Paketi 3): callback 2xx döner ve
  // idempotent biter, ama kredi YAZILMAZ ve kullanıcı belgesi DİRİLMEZ.
  | "blocked"
  | "user_mismatch";

export interface TicketStore {
  countPending(uid: string, nowMs: number): Promise<number>;
  /** Kullanıcının mevcut ödül kredisi (tavan ön-kontrolü için). */
  currentRewardCredits(uid: string): Promise<number>;
  create(uid: string, expiresAtMs: number): Promise<string>; // ticketId
  /** TEK transaction: bilet doğrula + granted işaretle + kredi +1 (tavana dek). */
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
  // Hotfix madde 4: ödül tavanındaysa reklam izletme — bileti hiç açma.
  if ((await store.currentRewardCredits(uid)) >= MAX_REWARD_CREDITS) {
    throw new AppError(
      "quota-exceeded",
      "Ödül hakkı üst sınırına ulaştın (en fazla " +
        `${MAX_REWARD_CREDITS} ödül kredisi).`,
      { maxRewardCredits: MAX_REWARD_CREDITS },
    );
  }
  if ((await store.countPending(uid, nowMs)) >= MAX_PENDING_TICKETS) {
    throw new AppError(
      "rate-limited",
      "Bekleyen çok fazla ödül isteğin var — önce reklamı tamamla.",
      { retryAfterSeconds: 60 },
    );
  }
  const expiresAtMs = nowMs + REWARD_TICKET_TTL_MS;
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

  async currentRewardCredits(uid: string): Promise<number> {
    const user = await this.db.doc(`users/${uid}`).get();
    const raw = user.data()?.["rewardCredits"];
    return typeof raw === "number" ? Math.max(0, Math.trunc(raw)) : 0;
  }

  async create(uid: string, expiresAtMs: number): Promise<string> {
    const ref = this.tickets(uid).doc();
    // Bariyer kontrolü ve bilet yazımı AYNI transaction'da: aksi hâlde
    // bariyer araya girerse silinmiş kullanıcı altında bilet doğardı.
    await this.db.runTransaction(async (tx) => {
      if ((await tx.get(barrierRef(this.db, uid))).exists) {
        throw accountDeletingError();
      }
      tx.create(ref, {
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(expiresAtMs),
      });
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
      // HESAP SİLME BARİYERİ (İş Paketi 3): bariyer açıksa kredi YAZILMAZ
      // ve kullanıcı belgesi DİRİLTİLMEZ. Okuma transaction'ın çakışma
      // kümesindedir; bariyer araya girerse transaction yeniden çalışır.
      if ((await tx.get(barrierRef(this.db, uid))).exists) return "blocked";

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

      // Hotfix madde 4: tavan kontrolü transaction İÇİNDE (yarış-güvenli).
      const user = await tx.get(userRef);
      const currentRaw = user.data()?.["rewardCredits"];
      const current =
        typeof currentRaw === "number" ? Math.max(0, Math.trunc(currentRaw)) : 0;
      if (current >= MAX_REWARD_CREDITS) {
        // Bilet tüketilir (tekrar denenemez) ama kredi VERİLMEZ.
        tx.update(ticketRef, {
          status: "granted",
          transactionId,
          capped: true,
          grantedAt: FieldValue.serverTimestamp(),
        });
        return "capped";
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
