/**
 * Ödüllü reklam testleri (PR #7A):
 *  - SSV imza doğrulaması (gerçek ECDSA anahtar çiftiyle)
 *  - bilet durum makinesi: pending→granted TEK YÖNLÜ (çifte ödül ✗)
 *  - havuz matematiği: free önce, reward sonra, negatif imkânsız
 */
import { createSign, generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";

import { readPools } from "../src/ai/firestore_ports";
import { AppError } from "../src/core/errors";
import {
  createRewardTicket,
  grantFromCallback,
  type GrantOutcome,
  type TicketStore,
} from "../src/rewards/reward_service";
import {
  MAX_PENDING_TICKETS,
  MAX_REWARD_CREDITS,
  REWARD_TICKET_TTL_MS as TICKET_TTL_MS,
} from "../src/config";
import { SsvVerifier } from "../src/rewards/ssv_verifier";

// ---- SSV doğrulayıcı ----

const { privateKey, publicKey } = generateKeyPairSync("ec", {
  namedCurve: "prime256v1",
});
const pem = publicKey.export({ type: "spki", format: "pem" }).toString();

function signedQuery(params: Record<string, string>): string {
  const message = new URLSearchParams(params).toString();
  const signer = createSign("SHA256");
  signer.update(message);
  const signature = signer.sign(privateKey).toString("base64url");
  return `${message}&signature=${signature}&key_id=42`;
}

const keyProvider = async (keyId: string) => (keyId === "42" ? pem : null);

describe("SsvVerifier", () => {
  const payload = {
    ad_network: "5450213213286189855",
    custom_data: "ticket-1",
    reward_amount: "1",
    transaction_id: "tx-9",
    user_id: "u1",
  };

  it("geçerli imza: payload çözülür", async () => {
    const result = await new SsvVerifier(keyProvider).verify(
      signedQuery(payload),
    );
    expect(result).toEqual({
      userId: "u1",
      customData: "ticket-1",
      transactionId: "tx-9",
    });
  });

  it("OYNANMIŞ parametre: imza geçmez → null (ödül YOK)", async () => {
    const tampered = signedQuery(payload).replace(
      "custom_data=ticket-1",
      "custom_data=baska-bilet",
    );
    expect(await new SsvVerifier(keyProvider).verify(tampered)).toBeNull();
  });

  it("bilinmeyen key_id → null", async () => {
    const query = signedQuery(payload).replace("key_id=42", "key_id=99");
    expect(await new SsvVerifier(keyProvider).verify(query)).toBeNull();
  });

  it("imzasız istek → null", async () => {
    expect(
      await new SsvVerifier(keyProvider).verify("user_id=u1&custom_data=t"),
    ).toBeNull();
  });

  it("imzalanmamış son eke eklenen kimlik/bilet alanları reddedilir", async () => {
    const unsignedIdentity = signedQuery({ ad_network: "5450213213286189855" }) +
      "&user_id=u1&custom_data=ticket-1&transaction_id=tx-9";
    expect(await new SsvVerifier(keyProvider).verify(unsignedIdentity)).toBeNull();
  });

  it("imzalı alanların tekrarları ve yol ayraçları reddedilir", async () => {
    const duplicate = signedQuery(payload) + "&custom_data=ticket-2";
    expect(await new SsvVerifier(keyProvider).verify(duplicate)).toBeNull();
    expect(await new SsvVerifier(keyProvider).verify(
      signedQuery({ ...payload, custom_data: "a/b" }),
    )).toBeNull();
    expect(await new SsvVerifier(keyProvider).verify(
      signedQuery({ ...payload, transaction_id: "" }),
    )).toBeNull();
  });
});

// ---- Bilet durum makinesi (bellek içi atomik depo) ----

interface Ticket {
  uid: string;
  status: "pending" | "granted" | "expired";
  expiresAtMs: number;
  transactionId?: string;
}

class MemoryTicketStore implements TicketStore {
  tickets = new Map<string, Ticket>();
  rewardCredits = new Map<string, number>();
  private seq = 0;

  async countPending(uid: string, nowMs: number): Promise<number> {
    return [...this.tickets.values()].filter(
      (t) => t.uid === uid && t.status === "pending" && t.expiresAtMs > nowMs,
    ).length;
  }

  async currentRewardCredits(uid: string): Promise<number> {
    return this.rewardCredits.get(uid) ?? 0;
  }

  async create(uid: string, expiresAtMs: number): Promise<string> {
    const id = `t${++this.seq}`;
    this.tickets.set(id, { uid, status: "pending", expiresAtMs });
    return id;
  }

  async grantIfPending(
    uid: string,
    ticketId: string,
    transactionId: string,
    nowMs: number,
  ): Promise<GrantOutcome> {
    const ticket = this.tickets.get(ticketId);
    if (!ticket || ticket.uid !== uid) return "unknown";
    if (ticket.status === "granted") return "duplicate";
    if (ticket.status !== "pending") return "unknown";
    if (ticket.expiresAtMs < nowMs) {
      ticket.status = "expired";
      return "expired";
    }
    // Hotfix madde 4: tavan — bilet tüketilir, kredi verilmez.
    if ((this.rewardCredits.get(uid) ?? 0) >= MAX_REWARD_CREDITS) {
      ticket.status = "granted";
      return "capped";
    }
    ticket.status = "granted";
    ticket.transactionId = transactionId;
    this.rewardCredits.set(uid, (this.rewardCredits.get(uid) ?? 0) + 1);
    return "granted";
  }
}

describe("ödül akışı", () => {
  const now = () => 1_000_000;

  it("mutlu yol: bilet → callback → +1 rewardCredits", async () => {
    const store = new MemoryTicketStore();
    const { ticketId } = await createRewardTicket(store, "u1", now);

    const outcome = await grantFromCallback(
      store,
      { userId: "u1", customData: ticketId, transactionId: "tx-1" },
      now,
    );
    expect(outcome).toBe("granted");
    expect(store.rewardCredits.get("u1")).toBe(1);
  });

  it("ÇİFTE ÖDÜL: aynı biletle ikinci callback kredi YAZMAZ", async () => {
    const store = new MemoryTicketStore();
    const { ticketId } = await createRewardTicket(store, "u1", now);
    const payload = { userId: "u1", customData: ticketId, transactionId: "tx" };

    expect(await grantFromCallback(store, payload, now)).toBe("granted");
    expect(await grantFromCallback(store, payload, now)).toBe("duplicate");
    expect(await grantFromCallback(store, payload, now)).toBe("duplicate");
    expect(store.rewardCredits.get("u1")).toBe(1); // hâlâ 1
  });

  it("süresi geçmiş bilet: kredi YOK", async () => {
    const store = new MemoryTicketStore();
    const { ticketId } = await createRewardTicket(store, "u1", now);

    const later = () => now() + TICKET_TTL_MS + 1;
    const outcome = await grantFromCallback(
      store,
      { userId: "u1", customData: ticketId, transactionId: "tx" },
      later,
    );
    expect(outcome).toBe("expired");
    expect(store.rewardCredits.get("u1")).toBeUndefined();
  });

  it("başkasının bileti / bilinmeyen bilet: kredi YOK", async () => {
    const store = new MemoryTicketStore();
    const { ticketId } = await createRewardTicket(store, "u1", now);

    expect(
      await grantFromCallback(
        store,
        { userId: "saldirgan", customData: ticketId, transactionId: "x" },
        now,
      ),
    ).toBe("unknown");
    expect(
      await grantFromCallback(
        store,
        { userId: "u1", customData: "hayali", transactionId: "x" },
        now,
      ),
    ).toBe("unknown");
    expect(store.rewardCredits.size).toBe(0);
  });

  it("bekleyen bilet limiti: stoklama engellenir", async () => {
    const store = new MemoryTicketStore();
    for (let i = 0; i < MAX_PENDING_TICKETS; i++) {
      await createRewardTicket(store, "u1", now);
    }
    const error = await createRewardTicket(store, "u1", now).catch(
      (e: unknown) => e,
    );
    expect((error as AppError).code).toBe("rate-limited");
  });

  it("hotfix madde 4: tavandaki kullanıcıya bilet açılmaz", async () => {
    const store = new MemoryTicketStore();
    store.rewardCredits.set("u1", MAX_REWARD_CREDITS);
    const error = await createRewardTicket(store, "u1", now).catch(
      (e: unknown) => e,
    );
    expect((error as AppError).code).toBe("quota-exceeded");
    expect((error as AppError).details?.["maxRewardCredits"]).toBe(
      MAX_REWARD_CREDITS,
    );
  });

  it("hotfix madde 4: tavanda callback bileti tüketir ama kredi VERMEZ", async () => {
    const store = new MemoryTicketStore();
    store.rewardCredits.set("u1", MAX_REWARD_CREDITS);
    // Bileti manuel aç (tavan kontrolünü atlayarak yarış senaryosu simülasyonu):
    const ticketId = await store.create("u1", now() + TICKET_TTL_MS);

    const outcome = await grantFromCallback(
      store,
      { userId: "u1", customData: ticketId, transactionId: "tx" },
      now,
    );
    expect(outcome).toBe("capped");
    expect(store.rewardCredits.get("u1")).toBe(MAX_REWARD_CREDITS); // artmadı
    // Bilet tüketildi — tekrar denenemez:
    expect(
      await grantFromCallback(
        store,
        { userId: "u1", customData: ticketId, transactionId: "tx2" },
        now,
      ),
    ).toBe("duplicate");
  });
});

// ---- Havuz matematiği (tüketim: free önce, reward sonra) ----

describe("readPools (7A tüketim temeli)", () => {
  it("yazılmamış alanlar: free lazy-init 5, reward 0", () => {
    expect(readPools({})).toEqual({ free: 5, reward: 0 });
  });

  it("iki havuz da okunur; bozuk/negatif değer 0'a kırpılır", () => {
    expect(readPools({ freeAnalysisCredits: 2, rewardCredits: 3 })).toEqual({
      free: 2,
      reward: 3,
    });
    expect(readPools({ freeAnalysisCredits: -7, rewardCredits: "x" })).toEqual(
      { free: 0, reward: 0 },
    );
  });
});
