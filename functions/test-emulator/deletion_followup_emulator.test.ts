/**
 * İŞ PAKETİ 3B — Paket 3 sonrası dört doğrulanmış açığın GERÇEK Firestore +
 * Auth emulator'ünde kapatılması.
 *
 * 1. Drain yalnız İLK sayfayı sayıyordu: ilk 50 kayıt kapanabilirse 51.
 *    ve sonrası hiç görülmeden `{open: 0}` dönüyordu.
 * 2. Bariyer oluşturulurken `expiresAt` yazılıyordu: silme 48 saatten uzun
 *    sürerse TTL bariyeri kaldırır ve Auth hâlâ dururken veri yeniden
 *    yazılabilir. Fail-closed DEĞİL.
 * 3. `createRewardTicket`'ın rate-limit transaction'ı bariyeri okumuyordu:
 *    `rateLimits/{uid}:reward` bariyerden sonra yetim doğabiliyordu.
 * 4. `user-token-expired` kesin silme kanıtı sayılıyordu (Dart tarafı).
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { JournalState } from "../src/ai/analysis_journal";
import { FirestoreAnalysisPorts } from "../src/ai/firestore_ports";
import { estimateUsage } from "../src/ai/usage_estimate";
import {
  ACCOUNT_DELETION_BLOCKS,
  BARRIER_TTL_MS,
  completeDeletionBarrier,
  raiseDeletionBarrier,
} from "../src/privacy/account_deletion_barrier";
import { deleteAccountCascade } from "../src/privacy/delete_account_service";
import { firestoreAccountDeletionPorts } from "../src/privacy/firestore_account_deletion_ports";
import { FirestoreRateLimitStore, RateLimiter } from "../src/quota/rate_limiter";
import { REWARD_TICKET_LIMITS } from "../src/config";
import { AppError } from "../src/core/errors";

const PROJECT_ID = "demo-karar";
const UID = "takip-sentetik-kullanici";
const DECISION_ID = "karar-1";

function assertEmulatorOnly(): void {
  const missing = ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]
    .filter((k) => !process.env[k]);
  if (missing.length > 0) {
    throw new Error(
      `Emulator zorunlu: ${missing.join(", ")} tanımlı değil. ` +
        "Bu testi 'npm run test:emulator' ile çalıştır.",
    );
  }
  if (!PROJECT_ID.startsWith("demo-")) {
    throw new Error("Yalnız demo-* projesi kullanılabilir.");
  }
}

const CONTENT = {
  title: "Sentetik karar başlığı",
  options: [
    { id: "o1", title: "Birinci seçenek", pros: [], cons: [] },
    { id: "o2", title: "İkinci seçenek", pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Ölçüt", weight: 5 }],
};
const ESTIMATE = estimateUsage({
  systemPrompt: "s".repeat(200),
  userPrompt: "u".repeat(200),
  maxOutputTokens: 800,
  model: "gpt-4.1-mini",
});

let app: App;
beforeAll(() => {
  assertEmulatorOnly();
  app = initializeApp({ projectId: PROJECT_ID });
});
afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore();
const auth = () => getAuth();
const barrierDoc = () => db().doc(`${ACCOUNT_DELETION_BLOCKS}/${UID}`);
const journalColl = () => db().collection(`users/${UID}/analysisRequests`);

function testClock() {
  let now = Date.now();
  return {
    now: () => now,
    sleep: async (ms: number) => {
      now += ms;
    },
  };
}

const OPS = [
  "dailySpend",
  "dailyTokens",
  "dailyAnalysisCount",
  "dailySpendReserved",
  "dailyTokensReserved",
] as const;

async function wipe(): Promise<void> {
  await db().recursiveDelete(db().doc(`users/${UID}`));
  await barrierDoc().delete();
  await db().doc(`rateLimits/${UID}`).delete();
  await db().doc(`rateLimits/${UID}:reward`).delete();
  for (const id of OPS) await db().doc(`ops/${id}`).delete();
  try {
    await auth().deleteUser(UID);
  } catch {
    // yok → no-op
  }
}

async function seed(): Promise<void> {
  await auth().createUser({ uid: UID });
  await db()
    .doc(`users/${UID}`)
    .set({ plan: "free", freeAnalysisCredits: 5, rewardCredits: 0 });
  await db()
    .doc(`users/${UID}/decisions/${DECISION_ID}`)
    .set({ ...CONTENT, status: "draft" });
}

/**
 * Doğrudan journal belgesi yazar — `reserve()` üzerinden 120 rezervasyon
 * açmak rate/kota limitlerine takılırdı. Kapanış yolunun gördüğü alanlar
 * birebir üretim şemasıdır.
 */
async function seedReservations(params: {
  count: number;
  ageMs: number;
  state?: JournalState;
  offset?: number;
}): Promise<void> {
  const nowMs = Date.now();
  let batch = db().batch();
  let n = 0;
  for (let i = 0; i < params.count; i++) {
    const id = `r${String((params.offset ?? 0) + i).padStart(23, "0")}`;
    batch.set(journalColl().doc(id), {
      state: params.state ?? JournalState.reserved,
      decisionId: DECISION_ID,
      contentFingerprint: "fp",
      accountingVersion: 2,
      reservationDay: new Date(nowMs).toISOString().slice(0, 10),
      estimateTokens: ESTIMATE.tokens,
      estimateUsd: ESTIMATE.usd,
      creditReserved: false,
      planAtReservation: "free",
      reservedAt: Timestamp.fromMillis(nowMs - params.ageMs),
      // Sıralama alanı: sorgu bunu kullanır.
      reservationExpiresAt: Timestamp.fromMillis(nowMs - params.ageMs + 600_000),
    });
    if (++n % 400 === 0) {
      await batch.commit();
      batch = db().batch();
    }
  }
  await batch.commit();
}

const openReservations = async (): Promise<number> =>
  (await journalColl().orderBy("reservationExpiresAt").get()).size;

const exists = async (path: string) => (await db().doc(path).get()).exists;

beforeEach(async () => {
  assertEmulatorOnly();
  await wipe();
});

describe("3B/1 — drain sayfalama", () => {
  it("51 rezervasyon: ilk sayfa kapansa bile 51. GENÇ kayıt görülür, open > 0", async () => {
    await seed();
    // 50 eski (kapanabilir) + 1 genç (aktif olabilir). Genç kaydın sıralama
    // değeri EN BÜYÜK olsun ki ilk sayfada görünmesin.
    await seedReservations({ count: 50, ageMs: 600_000, offset: 0 });
    await seedReservations({ count: 1, ageMs: 0, offset: 900 });

    const result = await firestoreAccountDeletionPorts.drainOpenReservations(
      UID,
      90_000,
    );
    expect(result.open).toBeGreaterThan(0);
  });

  it("51 rezervasyonda kaskat recursiveDelete ve Auth delete YAPMAZ", async () => {
    await seed();
    await seedReservations({ count: 50, ageMs: 600_000, offset: 0 });
    await seedReservations({ count: 1, ageMs: 0, offset: 900 });

    await expect(
      deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock()),
    ).rejects.toBeInstanceOf(AppError);

    expect(await exists(`users/${UID}`)).toBe(true);
    await expect(auth().getUser(UID)).resolves.toMatchObject({ uid: UID });
  });

  it("SAYFA BÜTÇESİNİN ötesindeki genç kayıt görülmeden silmeye geçilmez", async () => {
    await seed();
    // Bir turda en fazla pageSize×maxPages = 100 kayıt taranır. 100 eski
    // kayıt ilk turu doldurur; 101. GENÇ kayıt ancak `exhausted` doğru
    // bildirilirse SONRAKİ turda görülür. Yanlış bildirilirse kaskat
    // veriyi ve Auth'u siler.
    await seedReservations({ count: 100, ageMs: 600_000, offset: 0 });
    await seedReservations({ count: 1, ageMs: 0, offset: 900 });

    await expect(
      deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock()),
    ).rejects.toBeInstanceOf(AppError);

    expect(await exists(`users/${UID}`)).toBe(true);
    await expect(auth().getUser(UID)).resolves.toMatchObject({ uid: UID });
  });

  it("120 ESKİ rezervasyon: bounded sayfalarda TAMAMI kapanır", async () => {
    await seed();
    await seedReservations({ count: 120, ageMs: 600_000 });
    expect(await openReservations()).toBe(120);

    // Kaskat silmeden ÖNCE drain'in hepsini kapattığını doğrula.
    let rounds = 0;
    for (;;) {
      const r = await firestoreAccountDeletionPorts.drainOpenReservations(
        UID,
        90_000,
      );
      rounds++;
      if (r.open === 0 && !r.exhausted) break;
      expect(rounds).toBeLessThan(10); // bounded ilerleme
    }
    expect(await openReservations()).toBe(0);

    await deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock());

    expect(await exists(`users/${UID}`)).toBe(false);
    const day = new Date().toISOString().slice(0, 10);
    // `reserved` kayıtlar sağlayıcıya ulaşmadı → GERÇEK maliyet YAZILMAZ.
    const tokens = (await db().doc("ops/dailyTokens").get()).data()?.[day] ?? 0;
    expect(tokens).toBe(0);
    const reserved =
      (await db().doc("ops/dailyTokensReserved").get()).data()?.[day] ?? 0;
    expect(reserved).toBe(0);
  });

  it("sayfa sınırının ARKASINDAKİ provider_call_started görülmeden silmeye geçilmez", async () => {
    await seed();
    await seedReservations({ count: 60, ageMs: 600_000, offset: 0 });
    await seedReservations({
      count: 1,
      ageMs: 0,
      offset: 900,
      state: JournalState.providerCallStarted,
    });

    await expect(
      deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock()),
    ).rejects.toBeInstanceOf(AppError);
    expect(await exists(`users/${UID}`)).toBe(true);
  });
});

describe("3B/2 — bariyer state machine", () => {
  it("YENİ bariyer `deleting` ve expiresAt alanı YOK (TTL işlemez)", async () => {
    await raiseDeletionBarrier(db(), UID, Date.now());
    const data = (await barrierDoc().get()).data()!;
    expect(data["state"]).toBe("deleting");
    expect(data["expiresAt"]).toBeUndefined();
    expect(data["startedAt"]).toBeDefined();
    expect(JSON.stringify(data)).not.toContain(UID);
  });

  it("başarılı silme sonrası bariyer `deleted` + completedAt + TTL", async () => {
    await seed();
    const t0 = Date.now();
    await deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock());

    const data = (await barrierDoc().get()).data()!;
    expect(data["state"]).toBe("deleted");
    const completedAt = (data["completedAt"] as Timestamp).toMillis();
    const expiresAt = (data["expiresAt"] as Timestamp).toMillis();
    expect(completedAt).toBeGreaterThanOrEqual(t0);
    expect(expiresAt - completedAt).toBeGreaterThanOrEqual(BARRIER_TTL_MS);
    // Auth GERÇEKTEN silindikten SONRA yazıldı.
    await expect(auth().getUser(UID)).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
  });

  it("başarısız silmede bariyer `deleting` kalır ve TTL alanı OLUŞMAZ", async () => {
    await seed();
    await seedReservations({ count: 1, ageMs: 0 }); // genç → drain bitmez

    await expect(
      deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock()),
    ).rejects.toBeInstanceOf(AppError);

    const data = (await barrierDoc().get()).data()!;
    expect(data["state"]).toBe("deleting");
    expect(data["expiresAt"]).toBeUndefined();
  });

  it("retry startedAt'i DEĞİŞTİRMEZ", async () => {
    const t0 = Date.now();
    await raiseDeletionBarrier(db(), UID, t0);
    const before = (await barrierDoc().get()).data()!["startedAt"] as Timestamp;
    await raiseDeletionBarrier(db(), UID, t0 + 3_600_000);
    const after = (await barrierDoc().get()).data()!["startedAt"] as Timestamp;
    expect(after.toMillis()).toBe(before.toMillis());
  });

  it("LEGACY (PR #18) bariyeri: retry expiresAt'i KALDIRIR, startedAt korunur", async () => {
    // PR #18 biçimi: deleting + expiresAt
    await barrierDoc().set({
      schemaVersion: 1,
      state: "deleting",
      startedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + BARRIER_TTL_MS),
    });
    const before = (await barrierDoc().get()).data()!["startedAt"] as Timestamp;

    await raiseDeletionBarrier(db(), UID, Date.now());

    const data = (await barrierDoc().get()).data()!;
    expect(data["expiresAt"]).toBeUndefined();
    expect(data["state"]).toBe("deleting");
    expect((data["startedAt"] as Timestamp).toMillis()).toBe(before.toMillis());
  });

  it("`deleted` bariyer TEKRAR `deleting` yapılamaz", async () => {
    await raiseDeletionBarrier(db(), UID, Date.now());
    await completeDeletionBarrier(db(), UID, Date.now());
    const completedAt = (await barrierDoc().get()).data()![
      "completedAt"
    ] as Timestamp;

    await raiseDeletionBarrier(db(), UID, Date.now() + 1000);

    const data = (await barrierDoc().get()).data()!;
    expect(data["state"]).toBe("deleted");
    expect((data["completedAt"] as Timestamp).toMillis()).toBe(
      completedAt.toMillis(),
    );
  });

  it("terminal geçiş idempotenttir", async () => {
    await raiseDeletionBarrier(db(), UID, Date.now());
    await completeDeletionBarrier(db(), UID, Date.now());
    const first = (await barrierDoc().get()).data()!["expiresAt"] as Timestamp;
    await completeDeletionBarrier(db(), UID, Date.now() + 3_600_000);
    const second = (await barrierDoc().get()).data()!["expiresAt"] as Timestamp;
    expect(second.toMillis()).toBe(first.toMillis());
  });
});

describe("3B/3 — reward rate-limit yarışı", () => {
  const limiter = () =>
    new RateLimiter(new FirestoreRateLimitStore(), REWARD_TICKET_LIMITS);

  it("bariyer varken rate-limit belgesi OLUŞTURULMAZ", async () => {
    await seed();
    await raiseDeletionBarrier(db(), UID, Date.now());

    await expect(
      limiter().check(`${UID}:reward`, { accountUid: UID }),
    ).rejects.toMatchObject({ code: "account-deleting" });

    expect(await exists(`rateLimits/${UID}:reward`)).toBe(false);
  });

  it("bariyer YOKKEN rate-limit normal çalışır", async () => {
    await seed();
    await limiter().check(`${UID}:reward`, { accountUid: UID });
    expect(await exists(`rateLimits/${UID}:reward`)).toBe(true);
  });

  it("bariyerden ÖNCE oluşan rate-limit belgesi kaskat tarafından SİLİNİR", async () => {
    await seed();
    await limiter().check(`${UID}:reward`, { accountUid: UID });
    await db().doc(`rateLimits/${UID}`).set({ minute: { startMs: 0, count: 1 } });

    await deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock());

    expect(await exists(`rateLimits/${UID}:reward`)).toBe(false);
    expect(await exists(`rateLimits/${UID}`)).toBe(false);
  });

  it("kaskat, top-level rateLimits temizliğini DOĞRULAR", async () => {
    await seed();
    await deleteAccountCascade(UID, firestoreAccountDeletionPorts, testClock());
    expect(await exists(`rateLimits/${UID}`)).toBe(false);
    expect(await exists(`rateLimits/${UID}:reward`)).toBe(false);
  });

  it("top-level belge SİLİNEMEDİYSE Auth silinmez (doğrulama kapısı)", async () => {
    await seed();
    await db().doc(`rateLimits/${UID}:reward`).set({ minute: { startMs: 0, count: 1 } });

    // Top-level silme başarısız olmuş gibi davran: silme adımını no-op yap.
    const ports = {
      ...firestoreAccountDeletionPorts,
      deleteDocument: async (path: string) => {
        if (path.endsWith(":reward")) return; // sessizce başarısız
        await db().doc(path).delete();
      },
    };

    await expect(
      deleteAccountCascade(UID, ports, testClock()),
    ).rejects.toBeInstanceOf(AppError);

    await expect(auth().getUser(UID)).resolves.toMatchObject({ uid: UID });
    expect(await exists(`rateLimits/${UID}:reward`)).toBe(true);
  });
});
