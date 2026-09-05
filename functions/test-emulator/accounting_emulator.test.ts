/**
 * İŞ PAKETİ 2B — muhasebe ve rezervasyon bütünlüğünün GERÇEK Firestore
 * transaction sınırında doğrulanması.
 *
 * Üretim grafiğinin tamamı gerçektir: FirestoreAnalysisPorts, gerçek
 * ops/* sayaç depoları, gerçek rate limiter. YALNIZ OpenAI ağ geçidi
 * sahtedir — para harcamadan sağlayıcı sonucu üretir.
 *
 * Emulator zorunlu; `demo-` öneki canlı erişimi yapısal olarak imkânsız
 * kılar. Fixture'lar tamamen sentetiktir.
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
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
const UID = "emulator-sentetik-muhasebe";
const DECISION_ID = "karar-1";
const PARALLEL = 8;

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

class FakeGateway implements AiGateway {
  attempts = 0;
  async completeAnalysis(): Promise<AnalysisCompletion> {
    this.attempts++;
    return { output: OUTPUT, usage: { inputTokens: 1500, outputTokens: 600 } };
  }
}

const ctx = (): RequestContext => ({
  fn: "analyzeDecision",
  jobId: "job-1",
  uid: UID,
  uidHash: hashUid(UID),
  startedAtMs: Date.now(),
});

/** Üretim grafiği — yalnız gateway sahte. */
function buildService(gateway: AiGateway): AnalyzeService {
  return new AnalyzeService(new FirestoreAnalysisPorts(UID), gateway);
}

const ports = () => new FirestoreAnalysisPorts(UID);

const ANALYSIS = { ...OUTPUT, model: "gpt-4.1-mini", promptVersion: "mvp-1" };
const USAGE = { inputTokens: 1500, outputTokens: 600 };

/** Kararın GERÇEK fingerprint'i — finalize bunu bekler. */
async function decisionFingerprint(): Promise<string> {
  const { contentFingerprint } = await import("../src/ai/analysis_fingerprint");
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

/**
 * Rezervasyonu AÇIK bırakarak sağlayıcı sonucuna kadar ilerletir.
 * 2C: kapanmış bir rezervasyonu `provider_succeeded`'a geri almak üretimde
 * İMKÂNSIZDIR, bu yüzden fixture o durumu taklit etmez.
 */
async function openReservationWithResult(id: string): Promise<void> {
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

/** Testlerde kullanılan sabit tahmin (üretimdeki formülün aynısı). */
const ESTIMATE = estimateUsage({
  promptChars: 2000,
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
const rid = (seed: string) => seed.repeat(24).slice(0, 24);
const day = () => utcDayKey();

async function wipe(): Promise<void> {
  await db().recursiveDelete(db().doc(`users/${UID}`));
  for (const id of [
    "dailySpend",
    "dailyTokens",
    "dailyAnalysisCount",
    "dailySpendReserved",
    "dailyTokensReserved",
  ]) {
    await db().doc(`ops/${id}`).delete();
  }
  await db().doc(`rateLimits/${UID}`).delete();
}

async function seed(credits = 5): Promise<void> {
  await db()
    .doc(`users/${UID}`)
    .set({ plan: "free", freeAnalysisCredits: credits, rewardCredits: 0 });
  await db().doc(`users/${UID}/decisions/${DECISION_ID}`).set({
    ...CONTENT,
    status: "draft",
  });
}

const num = async (path: string, field: string): Promise<number> => {
  const snap = await db().doc(path).get();
  const value = snap.exists ? snap.data()?.[field] : 0;
  return typeof value === "number" ? value : 0;
};

const credits = async (): Promise<number> =>
  num(`users/${UID}`, "freeAnalysisCredits");
const spend = async (): Promise<number> => num("ops/dailySpend", day());
const tokens = async (): Promise<number> => num("ops/dailyTokens", day());
const slots = async (): Promise<number> => num("ops/dailyAnalysisCount", day());

beforeEach(async () => {
  assertEmulatorOnly();
  await wipe();
});

describe("gerçek transaction — paralel finalize muhasebesi", () => {
  it(`${PARALLEL} paralel finalize kredi/spend/token'ı TAM BİR kez uygular`, async () => {
    await seed();
    const gateway = new FakeGateway();
    const service = buildService(gateway);
    const id = rid("a");

    // Rezervasyon AÇIK ve sağlayıcı sonucu dayanıklı: kurtarma yolundaki
    // PARALEL yarış tam olarak bu pencerede oluşur.
    await openReservationWithResult(id);

    await Promise.all(
      Array.from({ length: PARALLEL }, () =>
        service
          .run(ctx(), { decisionId: DECISION_ID, requestId: id })
          .catch(() => undefined),
      ),
    );

    expect(await credits()).toBe(4);
    expect(await tokens()).toBe(2100);
    expect(await spend()).toBeGreaterThan(0);
    expect(await spend()).toBeLessThan(0.002);
    // Rezervasyon TAM BİR kez kapandı.
    expect(await num("ops/dailyTokensReserved", day())).toBe(0);
    expect(
      await num(`users/${UID}/analysisReservations/state`, "credits"),
    ).toBe(0);

    const journal = await db()
      .doc(`users/${UID}/analysisRequests/${id}`)
      .get();
    expect(journal.data()!["state"]).toBe(JournalState.completed);
    // Kapanış işareti: alanın YOKLUĞU rezervasyonun kapandığını gösterir.
    expect(journal.data()!["reservationExpiresAt"]).toBeUndefined();
  });
});

describe("gerçek transaction — farklı requestId eşzamanlılığı", () => {
  /**
   * Bu testler SERVİS üzerinden değil, doğrudan kabul transaction'ı üzerinden
   * yarıştırır. Nedeni kasıtlıdır: servis üzerinden yarıştırmak zamanlamaya
   * bağlı olur ve yanlışlıkla geçebilir. `reserve()` ise gerçek Firestore
   * iyimser eşzamanlılık denetimine tabidir — kazananı Firestore seçer.
   */
  const reserveWith = (id: string) =>
    ports().reserve({
      requestId: id,
      decisionId: DECISION_ID,
      contentFingerprint: "fp",
      estimate: ESTIMATE,
    });

  it("son ücretsiz kredi için yarışan FARKLI requestId'lerden yalnız biri kabul edilir", async () => {
    await seed(1);

    const results = await Promise.all([
      reserveWith(rid("b")),
      reserveWith(rid("c")),
    ]);

    expect(results.filter((r) => r.status === "created")).toHaveLength(1);
    const refused = results.find((r) => r.status === "rejected");
    expect(refused).toBeDefined();
    expect(
      (refused as { status: "rejected"; error: { code: string } }).error.code,
    ).toBe("quota-exceeded");
  });

  it("günlük analiz limitine yakın PARALEL istekler limiti AŞAMAZ", async () => {
    await seed(50);
    const { DAILY_GLOBAL_ANALYSIS_LIMIT } = await import("../src/config");
    await db()
      .doc("ops/dailyAnalysisCount")
      .set({ [day()]: DAILY_GLOBAL_ANALYSIS_LIMIT - 1 }, { merge: true });

    const results = await Promise.all(
      ["d", "e", "f", "g"].map((c) => reserveWith(rid(c))),
    );

    expect(results.filter((r) => r.status === "created")).toHaveLength(1);
    expect(await slots()).toBe(DAILY_GLOBAL_ANALYSIS_LIMIT);
  });

  it("günlük USD bütçesine yakın PARALEL istekler bütçeyi AŞAMAZ", async () => {
    await seed(50);
    const { DAILY_SPEND_LIMIT_USD } = await import("../src/config");
    // Bütçede tam olarak BİR rezervasyonluk yer bırak.
    await db()
      .doc("ops/dailySpend")
      .set(
        { [day()]: DAILY_SPEND_LIMIT_USD - 1.5 * ESTIMATE.usd },
        { merge: true },
      );

    const results = await Promise.all(
      ["h", "i", "j", "k"].map((c) => reserveWith(rid(c))),
    );

    expect(results.filter((r) => r.status === "created")).toHaveLength(1);
    const refused = results.find((r) => r.status === "rejected");
    expect(
      (refused as { status: "rejected"; error: { code: string } }).error.code,
    ).toBe("ai-unavailable");
  });

  it("günlük TOKEN tavanına yakın PARALEL istekler tavanı AŞAMAZ", async () => {
    await seed(50);
    const { DAILY_TOKEN_LIMIT } = await import("../src/config");
    await db()
      .doc("ops/dailyTokens")
      .set(
        { [day()]: DAILY_TOKEN_LIMIT - Math.floor(1.5 * ESTIMATE.tokens) },
        { merge: true },
      );

    const results = await Promise.all(
      ["l", "m", "n", "o"].map((c) => reserveWith(rid(c))),
    );

    expect(results.filter((r) => r.status === "created")).toHaveLength(1);
  });

  it("AYNI requestId ile paralel reserve rezervasyonları TEKRAR tüketmez", async () => {
    await seed(5);
    const id = rid("p");

    const results = await Promise.all(
      Array.from({ length: PARALLEL }, () => reserveWith(id)),
    );

    expect(results.filter((r) => r.status === "created")).toHaveLength(1);
    expect(results.filter((r) => r.status === "existing")).toHaveLength(
      PARALLEL - 1,
    );
    expect(await slots()).toBe(1);
    expect(await num("ops/dailyTokensReserved", day())).toBe(ESTIMATE.tokens);
    // Kredi rezervasyonu da TAM BİR kez artmış olmalı.
    expect(
      await num(`users/${UID}/analysisReservations/state`, "credits"),
    ).toBe(1);
  });
});

describe("gerçek transaction — kısmî yazım imkânsızlığı", () => {
  it("finalize transaction'ı çökerse HİÇBİR muhasebe yazımı kalmaz", async () => {
    await seed();
    const id = rid("q");

    // Rezervasyon AÇIK, sağlayıcı sonucu dayanıklı.
    await openReservationWithResult(id);

    const spendBefore = await spend();
    const tokensBefore = await tokens();
    const reservedBefore = await num("ops/dailyTokensReserved", day());
    expect(reservedBefore).toBe(ESTIMATE.tokens);

    // Krediyi sıfırla → finalize transaction'ı İÇERİDEN fırlatır.
    await db().doc(`users/${UID}`).update({
      freeAnalysisCredits: 0,
      rewardCredits: 0,
    });

    await expect(
      ports().finalize({
        requestId: id,
        decisionId: DECISION_ID,
        expectedFingerprint: await decisionFingerprint(),
        analysis: ANALYSIS,
        initialCredits: 0,
        usage: USAGE,
        costUsd: computeCostUsd(ANALYSIS.model, USAGE),
      }),
    ).rejects.toMatchObject({ code: "quota-exceeded" });

    // KISMÎ YAZIM YOK: hiçbir sayaç değişmedi, rezervasyon hâlâ AÇIK.
    expect(await spend()).toBeCloseTo(spendBefore, 12);
    expect(await tokens()).toBe(tokensBefore);
    expect(await num("ops/dailyTokensReserved", day())).toBe(reservedBefore);

    const journal = await db()
      .doc(`users/${UID}/analysisRequests/${id}`)
      .get();
    // Kurtarılabilir durumda kaldı ve rezervasyon işareti duruyor.
    expect(journal.data()!["state"]).toBe(JournalState.providerSucceeded);
    expect(journal.data()!["reservationExpiresAt"]).toBeDefined();
  });
});
