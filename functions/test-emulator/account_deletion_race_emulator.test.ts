/**
 * İŞ PAKETİ 3 — hesap silme doğrusallaştırmasının GERÇEK Firestore + Auth
 * emulator'ünde kanıtlanması.
 *
 * Kanıtlanan değişmez:
 *   "Bariyer commit edildikten sonra eski UID'ye ait hiçbir istemci veya
 *    sunucu işlemi kalıcı kullanıcı verisi oluşturamaz; bariyerden önce
 *    commit edilen tüm kullanıcı verisi kaskat tarafından silinir; Auth
 *    hesabı yalnız veri temizliği tamamlandıktan sonra silinir."
 *
 * Fixture'lar tamamen sentetiktir; `demo-` öneki canlı erişimi yapısal
 * olarak imkânsız kılar.
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { contentFingerprint } from "../src/ai/analysis_fingerprint";
import { JournalState } from "../src/ai/analysis_journal";
import { FirestoreAnalysisPorts } from "../src/ai/firestore_ports";
import { estimateUsage } from "../src/ai/usage_estimate";
import { computeCostUsd } from "../src/ai/cost_control";
import {
  ACCOUNT_DELETION_BLOCKS,
  raiseDeletionBarrier,
} from "../src/privacy/account_deletion_barrier";
import { deleteAccountCascade } from "../src/privacy/delete_account_service";
import { firestoreAccountDeletionPorts } from "../src/privacy/firestore_account_deletion_ports";
import { FirestoreTicketStore } from "../src/rewards/reward_service";
import { AppError } from "../src/core/errors";

const PROJECT_ID = "demo-karar";
const UID = "silinen-sentetik-kullanici";
const OTHER = "korunan-sentetik-kullanici";
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

const ANALYSIS = {
  summary: "Sentetik özet.",
  strengths: ["g1"],
  weaknesses: ["z1"],
  risks: ["r1"],
  recommendation: "Sentetik öneri.",
  confidence: "medium" as const,
  model: "gpt-4.1-mini",
  promptVersion: "mvp-1",
};
const USAGE = { inputTokens: 1500, outputTokens: 600 };
const ESTIMATE = estimateUsage({
  systemPrompt: "s".repeat(500),
  userPrompt: "u".repeat(500),
  maxOutputTokens: 800,
  model: ANALYSIS.model,
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
const rid = (seed: string) => seed.repeat(24).slice(0, 24);
const barrierDoc = (uid: string) => db().doc(`${ACCOUNT_DELETION_BLOCKS}/${uid}`);

/** Testte zaman ilerlemez; drain beklemesi anında biter. */
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
  for (const uid of [UID, OTHER]) {
    await db().recursiveDelete(db().doc(`users/${uid}`));
    await barrierDoc(uid).delete();
    await db().doc(`rateLimits/${uid}`).delete();
    await db().doc(`rateLimits/${uid}:reward`).delete();
    try {
      await auth().deleteUser(uid);
    } catch {
      // yok → no-op
    }
  }
  for (const id of OPS) await db().doc(`ops/${id}`).delete();
}

async function seed(uid: string, credits = 5): Promise<void> {
  await auth().createUser({ uid });
  await db()
    .doc(`users/${uid}`)
    .set({ plan: "free", freeAnalysisCredits: credits, rewardCredits: 0 });
  await db()
    .doc(`users/${uid}/decisions/${DECISION_ID}`)
    .set({ ...CONTENT, status: "draft" });
}

async function decisionFingerprint(uid: string): Promise<string> {
  const snap = await db().doc(`users/${uid}/decisions/${DECISION_ID}`).get();
  const d = snap.data()!;
  return contentFingerprint({
    content: {
      title: d["title"],
      options: d["options"],
      criteria: d["criteria"],
    } as never,
    model: ANALYSIS.model,
    promptVersion: ANALYSIS.promptVersion,
  });
}

const exists = async (path: string) => (await db().doc(path).get()).exists;
const empty = async (path: string) =>
  (await db().collection(path).limit(1).get()).empty;

async function cascade(uid = UID) {
  return deleteAccountCascade(uid, firestoreAccountDeletionPorts, testClock());
}

beforeEach(async () => {
  assertEmulatorOnly();
  await wipe();
});

describe("bariyer temel davranışı", () => {
  it("idempotenttir ve retry süreyi İLERİ TAŞIMAZ", async () => {
    const t0 = Date.now();
    const first = await raiseDeletionBarrier(db(), UID, t0);
    expect(first.created).toBe(true);
    const before = (await barrierDoc(UID).get()).data()!["expiresAt"] as Timestamp;

    const second = await raiseDeletionBarrier(db(), UID, t0 + 3_600_000);
    expect(second.created).toBe(false);
    const after = (await barrierDoc(UID).get()).data()!["expiresAt"] as Timestamp;
    expect(after.toMillis()).toBe(before.toMillis());
  });

  it("expiresAt en az 48 saat ileridedir ve PII taşımaz", async () => {
    const t0 = Date.now();
    await raiseDeletionBarrier(db(), UID, t0);
    const data = (await barrierDoc(UID).get()).data()!;
    const expires = (data["expiresAt"] as Timestamp).toMillis();
    expect(expires - t0).toBeGreaterThanOrEqual(48 * 3600 * 1000);
    expect(Object.keys(data).sort()).toEqual([
      "expiresAt",
      "schemaVersion",
      "startedAt",
      "state",
    ]);
    expect(JSON.stringify(data)).not.toContain(UID);
  });
});

describe("sunucu yazma yolları bariyerden sonra veri OLUŞTURAMAZ", () => {
  it("AI rezervasyonu reddedilir", async () => {
    await seed(UID);
    await raiseDeletionBarrier(db(), UID, Date.now());

    const outcome = await new FirestoreAnalysisPorts(UID)
      .reserve({
        requestId: rid("a"),
        decisionId: DECISION_ID,
        contentFingerprint: await decisionFingerprint(UID),
        estimate: ESTIMATE,
      })
      .catch((e: unknown) => e);

    expect(outcome).toBeInstanceOf(AppError);
    expect((outcome as AppError).code).toBe("account-deleting");
    expect(await empty(`users/${UID}/analysisRequests`)).toBe(true);
    expect(await exists(`rateLimits/${UID}`)).toBe(false);
  });

  it("sağlayıcı çağrısı BAŞLATILMAZ", async () => {
    await seed(UID);
    const ports = new FirestoreAnalysisPorts(UID);
    const id = rid("b");
    await ports.reserve({
      requestId: id,
      decisionId: DECISION_ID,
      contentFingerprint: await decisionFingerprint(UID),
      estimate: ESTIMATE,
    });
    // Rezervasyon AÇIKKEN bariyer doğar.
    await raiseDeletionBarrier(db(), UID, Date.now());

    await expect(ports.markProviderCallStarted(id)).rejects.toMatchObject({
      code: "account-deleting",
    });
    const journal = await db().doc(`users/${UID}/analysisRequests/${id}`).get();
    expect(journal.data()!["state"]).toBe(JournalState.reserved);
  });

  it("ödül bileti OLUŞTURULMAZ", async () => {
    await seed(UID);
    await raiseDeletionBarrier(db(), UID, Date.now());
    const store = new FirestoreTicketStore();
    await expect(store.create(UID, Date.now() + 600_000)).rejects.toMatchObject({
      code: "account-deleting",
    });
    expect(await empty(`users/${UID}/rewardTickets`)).toBe(true);
  });

  it("SSV callback kredi YAZMAZ ve kullanıcı belgesini DİRİLTMEZ", async () => {
    await seed(UID);
    const store = new FirestoreTicketStore();
    const ticketId = await store.create(UID, Date.now() + 600_000);
    await raiseDeletionBarrier(db(), UID, Date.now());
    // Kullanıcı ağacı silinmiş olsun.
    await db().recursiveDelete(db().doc(`users/${UID}`));

    const outcome = await store.grantIfPending(UID, ticketId, "tx-1", Date.now());

    expect(outcome).toBe("blocked");
    expect(await exists(`users/${UID}`)).toBe(false);
  });

  it("BAŞKA kullanıcı etkilenmez", async () => {
    await seed(UID);
    await seed(OTHER);
    await raiseDeletionBarrier(db(), UID, Date.now());

    const outcome = await new FirestoreAnalysisPorts(OTHER).reserve({
      requestId: rid("c"),
      decisionId: DECISION_ID,
      contentFingerprint: await decisionFingerprint(OTHER),
      estimate: ESTIMATE,
    });
    expect(outcome.status).toBe("created");
  });
});

describe("kaskat doğrusallaştırması", () => {
  it("bariyerden ÖNCE commit edilen veri KALDIRILIR", async () => {
    await seed(UID);
    await db().doc(`users/${UID}/decisions/${DECISION_ID}/aiAnalyses/latest`)
      .set({ summary: "eski analiz" });
    await db().doc(`users/${UID}/subscriptions/olay-1`).set({ p: "premium" });
    await db().doc(`rateLimits/${UID}`).set({ minute: 1 });
    await db().doc(`rateLimits/${UID}:reward`).set({ minute: 1 });

    await cascade();

    expect(await exists(`users/${UID}`)).toBe(false);
    expect(await empty(`users/${UID}/decisions`)).toBe(true);
    expect(await empty(`users/${UID}/analysisRequests`)).toBe(true);
    expect(await empty(`users/${UID}/analysisReservations`)).toBe(true);
    expect(await empty(`users/${UID}/rewardTickets`)).toBe(true);
    expect(await empty(`users/${UID}/subscriptions`)).toBe(true);
    expect(await exists(`rateLimits/${UID}`)).toBe(false);
    expect(await exists(`rateLimits/${UID}:reward`)).toBe(false);
    // Bariyer DURUYOR (TTL kaldırır) ve Auth kullanıcısı YOK.
    expect(await exists(`${ACCOUNT_DELETION_BLOCKS}/${UID}`)).toBe(true);
    await expect(auth().getUser(UID)).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
  });

  it("8 PARALEL deleteAccount TEK güvenli sonuç üretir", async () => {
    await seed(UID);
    const results = await Promise.allSettled(
      Array.from({ length: 8 }, () => cascade()),
    );
    // Hiçbiri veri bırakmaz; en az biri başarılıdır.
    expect(results.some((r) => r.status === "fulfilled")).toBe(true);
    expect(await exists(`users/${UID}`)).toBe(false);
    expect(await exists(`${ACCOUNT_DELETION_BLOCKS}/${UID}`)).toBe(true);
    await expect(auth().getUser(UID)).rejects.toMatchObject({
      code: "auth/user-not-found",
    });
  });

  it("devam eden AI isteği silme sonrası veriyi DİRİLTEMEZ", async () => {
    await seed(UID);
    const ports = new FirestoreAnalysisPorts(UID);
    const id = rid("d");
    const fp = await decisionFingerprint(UID);
    await ports.reserve({
      requestId: id,
      decisionId: DECISION_ID,
      contentFingerprint: fp,
      estimate: ESTIMATE,
    });
    await ports.markProviderCallStarted(id);
    // Rezervasyonu YAŞLANDIR: açan çağrının timeout'u dolmuş sayılır.
    await db()
      .doc(`users/${UID}/analysisRequests/${id}`)
      .update({ reservedAt: Timestamp.fromMillis(Date.now() - 600_000) });

    await cascade();
    expect(await exists(`users/${UID}`)).toBe(false);

    // Sağlayıcı sonucu SİLMEDEN SONRA döndü: hiçbir şey diriltilmemeli.
    await ports.recordProviderSuccess({ requestId: id, analysis: ANALYSIS, usage: USAGE });
    await expect(
      ports.finalize({
        requestId: id,
        decisionId: DECISION_ID,
        analysis: ANALYSIS,
        initialCredits: 5,
        usage: USAGE,
        costUsd: computeCostUsd(ANALYSIS.model, USAGE),
      }),
    ).rejects.toBeInstanceOf(AppError);

    expect(await exists(`users/${UID}`)).toBe(false);
    expect(await empty(`users/${UID}/decisions`)).toBe(true);
    expect(await empty(`users/${UID}/analysisRequests`)).toBe(true);
  });

  it("provider_succeeded + silme yarışı maliyeti TAM BİR kez işler", async () => {
    await seed(UID);
    const ports = new FirestoreAnalysisPorts(UID);
    const id = rid("e");
    await ports.reserve({
      requestId: id,
      decisionId: DECISION_ID,
      contentFingerprint: await decisionFingerprint(UID),
      estimate: ESTIMATE,
    });
    await ports.markProviderCallStarted(id);
    await ports.recordProviderSuccess({ requestId: id, analysis: ANALYSIS, usage: USAGE });
    await db()
      .doc(`users/${UID}/analysisRequests/${id}`)
      .update({ reservedAt: Timestamp.fromMillis(Date.now() - 600_000) });

    await cascade();

    const day = new Date().toISOString().slice(0, 10);
    const tokens = (await db().doc("ops/dailyTokens").get()).data()?.[day];
    // Gerçek maliyet BİR kez kaydedildi ve KAYBOLMADI.
    expect(typeof tokens).toBe("number");
    expect(tokens).toBe(USAGE.inputTokens + USAGE.outputTokens);
    // Rezerve sayaçlar kapandı.
    const reserved =
      (await db().doc("ops/dailyTokensReserved").get()).data()?.[day] ?? 0;
    expect(reserved).toBe(0);
    expect(await exists(`users/${UID}`)).toBe(false);
  });

  it("drain kapanmazsa Auth SİLİNMEZ ve veri KALIR", async () => {
    await seed(UID);
    const ports = new FirestoreAnalysisPorts(UID);
    const id = rid("f");
    await ports.reserve({
      requestId: id,
      decisionId: DECISION_ID,
      contentFingerprint: await decisionFingerprint(UID),
      estimate: ESTIMATE,
    });
    await ports.markProviderCallStarted(id);
    // reservedAt ŞİMDİ: kayıt genç, drain onu kapatamaz.

    await expect(cascade()).rejects.toBeInstanceOf(AppError);

    expect(await exists(`users/${UID}`)).toBe(true);
    await expect(auth().getUser(UID)).resolves.toMatchObject({ uid: UID });
  });

  it("ops sayaçları ve BAŞKA kullanıcı korunur", async () => {
    await seed(UID);
    await seed(OTHER);
    const day = new Date().toISOString().slice(0, 10);
    await db().doc("ops/dailyAnalysisCount").set({ [day]: 7 });

    await cascade();

    expect((await db().doc("ops/dailyAnalysisCount").get()).data()![day]).toBe(7);
    expect(await exists(`users/${OTHER}`)).toBe(true);
    expect(await exists(`users/${OTHER}/decisions/${DECISION_ID}`)).toBe(true);
    expect(await exists(`${ACCOUNT_DELETION_BLOCKS}/${OTHER}`)).toBe(false);
    await expect(auth().getUser(OTHER)).resolves.toMatchObject({ uid: OTHER });
  });
});
