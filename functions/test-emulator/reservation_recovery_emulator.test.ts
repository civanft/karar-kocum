/**
 * İŞ PAKETİ 2C — rezervasyon kökeni (provenance) ve orphan recovery'nin
 * GERÇEK Firestore transaction sınırında doğrulanması.
 *
 * 2B muhasebeyi atomik yaptı ama rezervasyonun KİMLİĞİNİ saklamadı:
 * hangi güne ait olduğu, kredi gerçekten rezerve edilip edilmediği ve
 * hangi tahminle açıldığı işlem anında YENİDEN türetiliyordu. Gün
 * dönümü, plan değişimi ve yeniden deploy bu türetmeleri yanlışlar.
 *
 * Emulator zorunlu; `demo-` öneki canlı erişimi yapısal olarak imkânsız
 * kılar. Fixture'lar tamamen sentetiktir.
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { JournalState } from "../src/ai/analysis_journal";
import { AnalyzeService } from "../src/ai/analyze_service";
import { computeCostUsd, utcDayKey } from "../src/ai/cost_control";
import { FirestoreAnalysisPorts } from "../src/ai/firestore_ports";
import { estimateUsage } from "../src/ai/usage_estimate";
import type { AiGateway, AnalysisCompletion } from "../src/ai/openai_gateway";
import { hashUid } from "../src/core/logger";
import type { RequestContext } from "../src/core/types";
import type { AnalysisOutput } from "../src/ai/schema";

const PROJECT_ID = "demo-karar";
const UID = "emulator-sentetik-koken";
const DECISION_ID = "karar-1";

function assertEmulatorOnly(): void {
  if (!process.env["FIRESTORE_EMULATOR_HOST"]) {
    throw new Error(
      "Emulator zorunlu: FIRESTORE_EMULATOR_HOST tanımlı değil. " +
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

const OUTPUT: AnalysisOutput = {
  summary: "Sentetik özet.",
  strengths: ["g1"],
  weaknesses: ["z1"],
  risks: ["r1"],
  recommendation: "Sentetik öneri.",
  confidence: "medium",
};

const ANALYSIS = { ...OUTPUT, model: "gpt-4.1-mini", promptVersion: "mvp-1" };
const USAGE = { inputTokens: 1500, outputTokens: 600 };
const COST_USD = computeCostUsd(ANALYSIS.model, USAGE);
const ESTIMATE = estimateUsage({
  systemPrompt: "s".repeat(1000),
  userPrompt: "u".repeat(1000),
  maxOutputTokens: 800,
  model: ANALYSIS.model,
});

class FakeGateway implements AiGateway {
  attempts = 0;
  async completeAnalysis(): Promise<AnalysisCompletion> {
    this.attempts++;
    return { output: OUTPUT, usage: USAGE };
  }
}

const ctx = (): RequestContext => ({
  fn: "analyzeDecision",
  jobId: "job-1",
  uid: UID,
  uidHash: hashUid(UID),
  startedAtMs: Date.now(),
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
const ports = () => new FirestoreAnalysisPorts(UID);
const rid = (seed: string) => seed.repeat(24).slice(0, 24);
const today = () => utcDayKey();
const yesterday = () =>
  new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);

const OPS = [
  "dailySpend",
  "dailyTokens",
  "dailyAnalysisCount",
  "dailySpendReserved",
  "dailyTokensReserved",
] as const;

async function wipe(): Promise<void> {
  await db().recursiveDelete(db().doc(`users/${UID}`));
  for (const id of OPS) await db().doc(`ops/${id}`).delete();
  await db().doc(`rateLimits/${UID}`).delete();
}

async function seed(credits = 5, plan = "free"): Promise<void> {
  await db()
    .doc(`users/${UID}`)
    .set({ plan, freeAnalysisCredits: credits, rewardCredits: 0 });
  await db()
    .doc(`users/${UID}/decisions/${DECISION_ID}`)
    .set({ ...CONTENT, status: "draft" });
}

const num = async (path: string, field: string): Promise<number> => {
  const snap = await db().doc(path).get();
  const v = snap.exists ? snap.data()?.[field] : 0;
  return typeof v === "number" ? v : 0;
};

const reservedCredits = () =>
  num(`users/${UID}/analysisReservations/state`, "credits");
const tokensReserved = (day: string) => num("ops/dailyTokensReserved", day);
const spendReserved = (day: string) => num("ops/dailySpendReserved", day);
const tokensActual = (day: string) => num("ops/dailyTokens", day);
const spendActual = (day: string) => num("ops/dailySpend", day);
const credits = () => num(`users/${UID}`, "freeAnalysisCredits");

const journalRef = (id: string) =>
  db().doc(`users/${UID}/analysisRequests/${id}`);

/**
 * Rezervasyonu açıp sağlayıcı sonucunu dayanıklı yazar — ama FİNALİZE ETMEZ.
 * Rezervasyon bilerek AÇIK bırakılır; testler tam olarak bu pencereyi ölçer.
 */
async function reserveThroughProvider(
  id: string,
  fingerprint = "fp-sabit",
): Promise<void> {
  const p = ports();
  const outcome = await p.reserve({
    requestId: id,
    decisionId: DECISION_ID,
    contentFingerprint: fingerprint,
    estimate: ESTIMATE,
  });
  if (outcome.status !== "created") {
    throw new Error(`fixture: rezervasyon açılamadı (${outcome.status})`);
  }
  const started = await p.markProviderCallStarted(id);
  if (!started) throw new Error("fixture: provider_call_started reddedildi");
  await p.recordProviderSuccess({ requestId: id, analysis: ANALYSIS, usage: USAGE });
}

/** Kararın GERÇEK fingerprint'i — finalize bunu bekler. */
async function decisionFingerprint(): Promise<string> {
  const { contentFingerprint } = await import("../src/ai/analysis_fingerprint");
  const snap = await db().doc(`users/${UID}/decisions/${DECISION_ID}`).get();
  const d = snap.data()!;
  return contentFingerprint({
    content: { title: d["title"], options: d["options"], criteria: d["criteria"] } as never,
    model: ANALYSIS.model,
    promptVersion: ANALYSIS.promptVersion,
  });
}

/** Rezervasyonun DÜNE ait olduğunu taklit eder: sayaçları güne taşır. */
async function moveReservationToYesterday(): Promise<void> {
  const t = await tokensReserved(today());
  const s = await spendReserved(today());
  await db()
    .doc("ops/dailyTokensReserved")
    .set({ [today()]: 0, [yesterday()]: t }, { merge: true });
  await db()
    .doc("ops/dailySpendReserved")
    .set({ [today()]: 0, [yesterday()]: s }, { merge: true });
  await journalRef(rid("a")).update({ reservationDay: yesterday() });
}

beforeEach(async () => {
  assertEmulatorOnly();
  await wipe();
});

describe("2C — gün dönümü (midnight)", () => {
  it("dünkü rezervasyon DÜNÜN sayacından kapanır, bugünü negatife düşürmez", async () => {
    await seed();
    const id = rid("a");
    await reserveThroughProvider(id, await decisionFingerprint());
    await moveReservationToYesterday();

    await ports().finalize({
      requestId: id,
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    // Dünün rezervasyonu KAPANDI.
    expect(await tokensReserved(yesterday())).toBe(0);
    expect(await spendReserved(yesterday())).toBeCloseTo(0, 12);
    // Bugünün rezervasyonu NEGATİFE düşmedi.
    expect(await tokensReserved(today())).toBeGreaterThanOrEqual(0);
    expect(await spendReserved(today())).toBeGreaterThanOrEqual(0);
    // Gerçek tüketim rezervasyonun ait olduğu güne yazıldı.
    expect(await tokensActual(yesterday())).toBe(2100);
    expect(await tokensActual(today())).toBe(0);
  });
});

describe("2C — plan değişimi", () => {
  it("rezervasyon FREE, finalize PREMIUM: kredi rezervasyonu yine de kapanır", async () => {
    await seed(5, "free");
    const id = rid("b");
    await reserveThroughProvider(id, await decisionFingerprint());
    expect(await reservedCredits()).toBe(1);

    await db().doc(`users/${UID}`).update({ plan: "premium" });

    await ports().finalize({
      requestId: id,
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    // Rezervasyon SIZMADI: kullanıcı kalıcı olarak bir kredi slotu kaybetmedi.
    expect(await reservedCredits()).toBe(0);
  });

  it("rezervasyon PREMIUM, finalize FREE: kredi sayacı NEGATİFE düşmez", async () => {
    await seed(5, "premium");
    const id = rid("c");
    await reserveThroughProvider(id, await decisionFingerprint());
    // Premium'da kredi hiç rezerve edilmez.
    expect(await reservedCredits()).toBe(0);

    await db().doc(`users/${UID}`).update({ plan: "free" });

    await ports().finalize({
      requestId: id,
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    expect(await reservedCredits()).toBeGreaterThanOrEqual(0);
  });
});

describe("2C — deployment/config değişimi", () => {
  it("kapanış journal'daki miktarı kullanır: fazla ya da eksik serbest bırakmaz", async () => {
    await seed();
    const fp = await decisionFingerprint();
    // İKİ rezervasyon aç. Birini kapatınca geriye TAM OLARAK diğerinin
    // miktarı kalmalı. Tek rezervasyonla test edilirse `max(0, …)` koruması
    // fazla serbest bırakmayı maskeler — bu yüzden iki tane.
    await reserveThroughProvider(rid("d"), fp);
    await reserveThroughProvider(rid("d2"), fp);
    expect(await tokensReserved(today())).toBe(ESTIMATE.tokens * 2);

    await ports().finalize({
      requestId: rid("d"),
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    // Yeniden deploy edilmiş bir revizyon BAŞKA bir tahmin hesaplasa bile
    // kapanan miktar journal'daki miktardır.
    expect(await tokensReserved(today())).toBe(ESTIMATE.tokens);
    expect(await spendReserved(today())).toBeCloseTo(ESTIMATE.usd, 12);
  });
});

describe("2C — sayaç değişmezleri", () => {
  it("başarılı akışların hiçbirinde rezerve sayaçlar negatif olmaz", async () => {
    await seed();
    for (const seedChar of ["e", "f", "g"]) {
      const id = rid(seedChar);
      await reserveThroughProvider(id, await decisionFingerprint());
      await ports().finalize({
        requestId: id,
        decisionId: DECISION_ID,
        analysis: ANALYSIS,
        initialCredits: 5,
        usage: USAGE,
        costUsd: COST_USD,
      });
      expect(await tokensReserved(today())).toBeGreaterThanOrEqual(0);
      expect(await spendReserved(today())).toBeGreaterThanOrEqual(0);
      expect(await reservedCredits()).toBeGreaterThanOrEqual(0);
    }
    expect(await credits()).toBe(2);
  });
});

/**
 * Orphan recovery: süreç rezervasyonu açtıktan sonra ölürse journal
 * `reserved` / `provider_call_started` durumunda ASILI kalır. Kredi
 * rezervasyonu kullanıcıya iade edilmediği için kullanıcı kalıcı olarak
 * kilitlenebilir. Kurtarma, kullanıcı YENİ bir analiz başlattığında
 * fırsatçı (opportunistic) olarak çalışmalıdır.
 */
const STALE_AGO_MS = 60 * 60 * 1000; // eşiğin çok üstünde

/** Süreç ölmüş gibi ASILI bir rezervasyon bırakır. */
async function orphan(
  id: string,
  state: JournalState,
  opts: { expired: boolean; day?: string } = { expired: true },
): Promise<void> {
  const day = opts.day ?? today();
  const expiresAtMs = opts.expired
    ? Date.now() - STALE_AGO_MS
    : Date.now() + STALE_AGO_MS;

  await journalRef(id).set({
    state,
    decisionId: DECISION_ID,
    contentFingerprint: "fp-orphan",
    accountingVersion: 2,
    reservationDay: day,
    estimateTokens: ESTIMATE.tokens,
    estimateUsd: ESTIMATE.usd,
    creditReserved: true,
    planAtReservation: "free",
    reservedAt: Timestamp.fromMillis(Date.now() - STALE_AGO_MS),
    reservationExpiresAt: Timestamp.fromMillis(expiresAtMs),
    ...(state === JournalState.providerSucceeded ? { analysis: ANALYSIS } : {}),
  });
  // Rezervasyon sayaçlarını da aç.
  await db()
    .doc("ops/dailyTokensReserved")
    .set({ [day]: ESTIMATE.tokens }, { merge: true });
  await db()
    .doc("ops/dailySpendReserved")
    .set({ [day]: ESTIMATE.usd }, { merge: true });
  await db()
    .doc(`users/${UID}/analysisReservations/state`)
    .set({ credits: 1 }, { merge: true });
}

/** Kullanıcının YENİ bir analiz başlatması. */
async function startNewAnalysis(id: string): Promise<FakeGateway> {
  const gateway = new FakeGateway();
  const service = new AnalyzeService(new FirestoreAnalysisPorts(UID), gateway);
  await service
    .run(ctx(), { decisionId: DECISION_ID, requestId: id })
    .catch(() => undefined);
  return gateway;
}

describe("2C — orphan recovery", () => {
  it("STALE `reserved`: sağlayıcı hiç başlamadı → rezervasyon serbest, GERÇEK tüketim YAZILMAZ", async () => {
    await seed();
    await orphan(rid("h"), JournalState.reserved);

    await startNewAnalysis(rid("i"));

    const stale = await journalRef(rid("h")).get();
    expect(stale.data()!["state"]).toBe(JournalState.terminalFailed);
    // Sağlayıcı çağrılmadığı KANITLI: gerçek sayaç artmaz.
    expect(await tokensActual(today())).toBe(2100); // yalnız YENİ analizinki
    // Orphan'ın rezervasyonu kapandı (yeni analiz kendi rezervasyonunu
    // açıp kapattığı için net 0 kalmalı).
    expect(await tokensReserved(today())).toBe(0);
    expect(await reservedCredits()).toBe(0);
  });

  it("STALE `provider_call_started`: sonuç BİLİNMİYOR → tahmin gerçek sayaca çevrilir, kredi iade edilir", async () => {
    await seed();
    await orphan(rid("j"), JournalState.providerCallStarted);

    const gateway = await startNewAnalysis(rid("k"));

    const stale = await journalRef(rid("j")).get();
    expect(stale.data()!["state"]).toBe(JournalState.uncertain);
    // Sağlayıcı YENİDEN çağrılmadı: yalnız yeni analizin çağrısı var.
    expect(gateway.attempts).toBe(1);
    // Tahmin bir kez gerçek tüketime dönüştü (2100 yeni analiz + tahmin).
    expect(await tokensActual(today())).toBe(2100 + ESTIMATE.tokens);
    expect(await tokensReserved(today())).toBe(0);
    expect(await reservedCredits()).toBe(0);
  });

  it("AKTİF (süresi dolmamış) rezervasyon reconcile EDİLMEZ", async () => {
    await seed();
    await orphan(rid("l"), JournalState.providerCallStarted, { expired: false });

    await startNewAnalysis(rid("m"));

    const active = await journalRef(rid("l")).get();
    expect(active.data()!["state"]).toBe(JournalState.providerCallStarted);
    expect(await reservedCredits()).toBe(1); // hâlâ açık
  });

  it("kullanıcı hiç dönmezse ESKİ GÜN rezervasyonu bugünün bütçesini etkilemez", async () => {
    await seed();
    await orphan(rid("n"), JournalState.reserved, {
      expired: true,
      day: yesterday(),
    });

    // Bugünün rezervasyon sayacı DÜNKÜ orphan'dan etkilenmez.
    expect(await tokensReserved(today())).toBe(0);
    expect(await spendReserved(today())).toBeCloseTo(0, 12);

    // Yeni analiz normal çalışır.
    const gateway = await startNewAnalysis(rid("o"));
    expect(gateway.attempts).toBe(1);
    // Dünün rezervasyonu muhasebe doğruluğu için yine de kapanır.
    expect(await tokensReserved(yesterday())).toBe(0);
  });

  it("aynı orphan'a 8 PARALEL reconciliation: muhasebe TAM BİR kez", async () => {
    await seed();
    await orphan(rid("p"), JournalState.providerCallStarted);

    const p = ports();
    await Promise.all(
      Array.from({ length: 8 }, () =>
        p.reconcileStaleReservations(Date.now(), 5).catch(() => 0),
      ),
    );

    expect(await reservedCredits()).toBe(0);
    expect(await tokensActual(today())).toBe(ESTIMATE.tokens);
    expect(await tokensReserved(today())).toBe(0);
  });

  it("`creditReserved: false` olan kayıt kredi sayacını AZALTMAZ", async () => {
    await seed();
    const id = rid("q");
    await orphan(id, JournalState.reserved);
    await journalRef(id).update({ creditReserved: false, planAtReservation: "premium" });
    await db().doc(`users/${UID}/analysisReservations/state`).set({ credits: 0 });

    await ports().reconcileStaleReservations(Date.now(), 5);

    expect(await reservedCredits()).toBe(0); // negatife DÜŞMEDİ
  });

  it("provenance'ı EKSİK eski kayıt: sayaç bozulmaz, kayıt terminal olur", async () => {
    await seed();
    const id = rid("r");
    // 2B döneminden kalma kayıt: day/creditReserved/plan YOK.
    await journalRef(id).set({
      state: JournalState.reserved,
      decisionId: DECISION_ID,
      contentFingerprint: "fp-legacy",
      estimateTokens: ESTIMATE.tokens,
      estimateUsd: ESTIMATE.usd,
      reservationExpiresAt: Timestamp.fromMillis(Date.now() - STALE_AGO_MS),
    });

    await ports().reconcileStaleReservations(Date.now(), 5);

    const rec = await journalRef(id).get();
    expect(rec.data()!["state"]).toBe(JournalState.terminalFailed);
    // Kesin bilgi olmadığı için sayaçlara DOKUNULMADI — negatif üretilmedi.
    expect(await tokensReserved(today())).toBeGreaterThanOrEqual(0);
    expect(await reservedCredits()).toBeGreaterThanOrEqual(0);
  });
});
