/**
 * İŞ PAKETİ 2D — stale `provider_succeeded` kurtarmasının GERÇEK Firestore
 * transaction sınırında doğrulanması.
 *
 * 2C, asılı `provider_succeeded` kaydının kredi rezervasyonunu serbest
 * bırakıp kaydı HÂLÂ finalize edilebilir bırakıyordu. Bu, aynı son kredinin
 * iki ayrı sağlayıcı isteğine dayanak olmasına açık bir pencere yaratır ve
 * `provider_succeeded && rezervasyon kapalı` gibi belirsiz bir ara durum
 * üretir.
 *
 * Emulator zorunlu; `demo-` öneki canlı erişimi yapısal olarak imkânsız
 * kılar. Fixture'lar tamamen sentetiktir.
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { contentFingerprint } from "../src/ai/analysis_fingerprint";
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
const UID = "emulator-sentetik-kurtarma";
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
const day = () => utcDayKey();
const journalRef = (id: string) =>
  db().doc(`users/${UID}/analysisRequests/${id}`);

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

async function seed(credits: number): Promise<void> {
  await db()
    .doc(`users/${UID}`)
    .set({ plan: "free", freeAnalysisCredits: credits, rewardCredits: 0 });
  await db()
    .doc(`users/${UID}/decisions/${DECISION_ID}`)
    .set({ ...CONTENT, status: "draft" });
}

const num = async (path: string, field: string): Promise<number> => {
  const snap = await db().doc(path).get();
  const v = snap.exists ? snap.data()?.[field] : 0;
  return typeof v === "number" ? v : 0;
};

const credits = () => num(`users/${UID}`, "freeAnalysisCredits");
const reservedCredits = () =>
  num(`users/${UID}/analysisReservations/state`, "credits");
const tokensActual = () => num("ops/dailyTokens", day());
const tokensReserved = () => num("ops/dailyTokensReserved", day());
const spendActual = () => num("ops/dailySpend", day());

async function decisionFingerprint(): Promise<string> {
  const snap = await db().doc(`users/${UID}/decisions/${DECISION_ID}`).get();
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

/** Rezervasyonu AÇIK bırakarak sağlayıcı sonucuna kadar ilerletir. */
async function openWithProviderResult(id: string): Promise<void> {
  const p = ports();
  const reserved = await p.reserve({
    requestId: id,
    decisionId: DECISION_ID,
    contentFingerprint: await decisionFingerprint(),
    estimate: ESTIMATE,
  });
  if (reserved.status !== "created") {
    throw new Error(`fixture: rezervasyon açılamadı (${reserved.status})`);
  }
  if (!(await p.markProviderCallStarted(id))) {
    throw new Error("fixture: provider_call_started reddedildi");
  }
  await p.recordProviderSuccess({ requestId: id, analysis: ANALYSIS, usage: USAGE });
}

/** Kaydı ASILI yapar: rezervasyon süresi geçmişe çekilir. */
async function makeStale(id: string): Promise<void> {
  await journalRef(id).update({
    reservationExpiresAt: Timestamp.fromMillis(Date.now() - 60 * 60 * 1000),
  });
}

beforeEach(async () => {
  assertEmulatorOnly();
  await wipe();
});

describe("2D — kredi yarışı", () => {
  it("stale provider_succeeded kurtarması AYNI krediyi ikinci bir isteğe AÇMAZ", async () => {
    await seed(1); // TEK kredi
    const a = rid("a");
    await openWithProviderResult(a);
    await makeStale(a);

    await ports().reconcileStaleReservations(Date.now(), 5);

    // Kurtarma A'yı ATOMİK olarak tamamlamalı: kredi TÜKETİLDİ.
    const ja = await journalRef(a).get();
    expect(ja.data()!["state"]).toBe(JournalState.completed);
    expect(await credits()).toBe(0);

    // B artık krediyi rezerve EDEMEZ → sağlayıcıya hiç ulaşmaz.
    const b = await ports().reserve({
      requestId: rid("b"),
      decisionId: DECISION_ID,
      contentFingerprint: await decisionFingerprint(),
      estimate: ESTIMATE,
    });
    expect(b.status).toBe("rejected");
    expect(
      (b as { status: "rejected"; error: { code: string } }).error.code,
    ).toBe("quota-exceeded");
  });

  it("`provider_succeeded && rezervasyon kapalı` BELİRSİZ durumu üretilmez", async () => {
    await seed(1);
    const a = rid("c");
    await openWithProviderResult(a);
    await makeStale(a);

    await ports().reconcileStaleReservations(Date.now(), 5);

    const d = (await journalRef(a).get()).data()!;
    const kapali = d["reservationExpiresAt"] === undefined;
    const belirsiz = d["state"] === JournalState.providerSucceeded && kapali;
    expect(belirsiz).toBe(false);
  });

  it("kurtarma sonrası kredi negatife düşmez, spend/token TEKRARLANMAZ", async () => {
    await seed(1);
    const a = rid("d");
    await openWithProviderResult(a);
    await makeStale(a);

    await ports().reconcileStaleReservations(Date.now(), 5);
    // İkinci kurtarma çağrısı hiçbir şeyi tekrarlamamalı.
    await ports().reconcileStaleReservations(Date.now(), 5);

    expect(await credits()).toBeGreaterThanOrEqual(0);
    expect(await credits()).toBe(0);
    expect(await tokensActual()).toBe(2100);
    expect(await spendActual()).toBeCloseTo(COST_USD, 12);
    expect(await tokensReserved()).toBe(0);
    expect(await reservedCredits()).toBe(0);
  });
});

describe("2D — atomik stale finalization", () => {
  it("karar DEĞİŞMEMİŞSE: analiz yazılır, karar analyzed, kredi bir kez", async () => {
    await seed(3);
    const a = rid("e");
    await openWithProviderResult(a);
    await makeStale(a);

    await ports().reconcileStaleReservations(Date.now(), 5);

    const analyses = await db()
      .doc(`users/${UID}/decisions/${DECISION_ID}`)
      .collection("aiAnalyses")
      .get();
    expect(analyses.size).toBe(1);
    expect(analyses.docs[0]!.data()["summary"]).toBe(OUTPUT.summary);

    const decision = await db()
      .doc(`users/${UID}/decisions/${DECISION_ID}`)
      .get();
    expect(decision.data()!["status"]).toBe("analyzed");
    expect(await credits()).toBe(2);
    expect(await tokensActual()).toBe(2100);
    expect((await journalRef(a).get()).data()!["state"]).toBe(
      JournalState.completed,
    );
    expect(
      (await journalRef(a).get()).data()!["reservationExpiresAt"],
    ).toBeUndefined();
  });

  it("karar DEĞİŞMİŞSE: superseded, kredi tüketilmez, gerçek maliyet bir kez", async () => {
    await seed(3);
    const a = rid("f");
    await openWithProviderResult(a);
    await db()
      .doc(`users/${UID}/decisions/${DECISION_ID}`)
      .update({ title: "Kullanıcı başlığı değiştirdi" });
    await makeStale(a);

    await ports().reconcileStaleReservations(Date.now(), 5);

    expect((await journalRef(a).get()).data()!["state"]).toBe(
      JournalState.superseded,
    );
    expect(await credits()).toBe(3); // KREDİ TÜKETİLMEDİ
    const analyses = await db()
      .doc(`users/${UID}/decisions/${DECISION_ID}`)
      .collection("aiAnalyses")
      .get();
    expect(analyses.size).toBe(0); // analiz BAĞLANMADI
    expect(await tokensActual()).toBe(2100); // gerçek maliyet BİR kez
    expect(await tokensReserved()).toBe(0);
    expect(await reservedCredits()).toBe(0);
  });

  it("saklanan sonuç ÇÖPE GİTMEZ: kullanıcı requestId'yi kaybetse bile yazılır", async () => {
    await seed(3);
    const a = rid("g");
    await openWithProviderResult(a);
    await makeStale(a);

    // Kullanıcı asla aynı requestId ile dönmüyor; yalnız kurtarma çalışıyor.
    await ports().reconcileStaleReservations(Date.now(), 5);

    const analyses = await db()
      .doc(`users/${UID}/decisions/${DECISION_ID}`)
      .collection("aiAnalyses")
      .get();
    expect(analyses.size).toBe(1);
  });

  it("8 PARALEL kurtarma YALNIZ BİR finalization üretir", async () => {
    await seed(3);
    const a = rid("h");
    await openWithProviderResult(a);
    await makeStale(a);

    const p = ports();
    await Promise.all(
      Array.from({ length: 8 }, () =>
        p.reconcileStaleReservations(Date.now(), 5).catch(() => 0),
      ),
    );

    expect(await credits()).toBe(2); // TAM BİR kredi
    expect(await tokensActual()).toBe(2100); // TAM BİR kez
    expect(await spendActual()).toBeCloseTo(COST_USD, 12);
    expect(await reservedCredits()).toBe(0);
    expect(await tokensReserved()).toBe(0);
  });

  it("sonrasında aynı requestId ile gelen çağrı COMPLETED sonucu döndürür", async () => {
    await seed(3);
    const a = rid("i");
    await openWithProviderResult(a);
    await makeStale(a);
    await ports().reconcileStaleReservations(Date.now(), 5);

    const gateway = new FakeGateway();
    const service = new AnalyzeService(new FirestoreAnalysisPorts(UID), gateway);
    const result = await service.run(ctx(), {
      decisionId: DECISION_ID,
      requestId: a,
    });

    expect(result.analysis.summary).toBe(OUTPUT.summary);
    expect(gateway.attempts).toBe(0); // sağlayıcı YENİDEN çağrılmadı
    expect(await credits()).toBe(2); // kredi İKİNCİ kez düşmedi
    expect(await tokensActual()).toBe(2100);
  });
});

describe("2D — anormal/legacy kayıtlar", () => {
  it("provider_succeeded + rezervasyon KAPALI (2C artığı) güvenli onarılır", async () => {
    await seed(3);
    const a = rid("j");
    await openWithProviderResult(a);
    // 2C'nin ürettiği anormal durum: rezervasyon kapatılmış ama kayıt
    // hâlâ provider_succeeded.
    await journalRef(a).update({
      reservationExpiresAt: (
        await import("firebase-admin/firestore")
      ).FieldValue.delete(),
    });

    const gateway = new FakeGateway();
    const service = new AnalyzeService(new FirestoreAnalysisPorts(UID), gateway);
    await service.run(ctx(), { decisionId: DECISION_ID, requestId: a });

    // Muhasebe İKİNCİ kez uygulanmadı; kayıt terminal oldu.
    expect((await journalRef(a).get()).data()!["state"]).toBe(
      JournalState.completed,
    );
    expect(await credits()).toBe(2);
    expect(await tokensReserved()).toBe(ESTIMATE.tokens); // 2C kapatmamıştı
  });

  it("provider_succeeded fakat SAKLANAN SONUÇ yok: sessizce kredi tüketmez", async () => {
    await seed(3);
    const a = rid("k");
    await openWithProviderResult(a);
    await journalRef(a).update({
      analysis: (await import("firebase-admin/firestore")).FieldValue.delete(),
    });
    await makeStale(a);

    await ports().reconcileStaleReservations(Date.now(), 5);

    const state = (await journalRef(a).get()).data()!["state"];
    expect([JournalState.uncertain, JournalState.terminalFailed]).toContain(
      state,
    );
    expect(await credits()).toBe(3); // KREDİ TÜKETİLMEDİ
    expect(await reservedCredits()).toBe(0); // rezervasyon serbest
  });
});
