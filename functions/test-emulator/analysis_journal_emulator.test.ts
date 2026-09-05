/**
 * İŞ PAKETİ 2 — journal idempotency'sinin GERÇEK Firestore transaction
 * sınırında doğrulanması.
 *
 * Birim testleri portları mock'lar; orada "paralel çağrıdan yalnız biri
 * kazanır" iddiası test kodumuzun kendi kilidine dayanır. Burada üretimde
 * koşan adaptörün (FirestoreAnalysisPorts) kendisi gerçek emulator'e karşı
 * çalışır; kazananı Firestore'un iyimser eşzamanlılık denetimi seçer.
 * Böylece ancak gerçek transaction motorunun cevaplayabileceği soru
 * kanıtlanır: eşzamanlı finalize'da kredi KAÇ KEZ düşer?
 *
 * Çalıştırma: npm run test:emulator
 *
 * CANLI ERİŞİM YAPISAL OLARAK ENGELLİ:
 *  - proje kimliği `demo-` önekli olmak ZORUNDA (Firebase bu öneki yalnız
 *    emulator'e ayırır; böyle bir bulut projesi oluşturulamaz)
 *  - emulator host değişkeni yoksa test HİÇ BAŞLAMAZ (fail-fast)
 *
 * Fixture'lar tamamen sentetiktir: gerçek UID veya gerçek kullanıcı içeriği
 * KULLANILMAZ.
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { contentFingerprint } from "../src/ai/analysis_fingerprint";
import { computeCostUsd } from "../src/ai/cost_control";
import { estimateUsage } from "../src/ai/usage_estimate";
import { JournalState } from "../src/ai/analysis_journal";
import { FirestoreAnalysisPorts } from "../src/ai/firestore_ports";
import { LATEST_ANALYSIS_ID, type StoredAnalysis } from "../src/ai/analyze_service";

const PROJECT_ID = "demo-karar";
const UID = "emulator-sentetik-kullanici";
const DECISION_ID = "karar-1";
const REQUEST_ID = "b".repeat(24);
const PARALLEL = 8;

/** Emulator dışına çıkmayı imkânsız kılan ön koşullar. */
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

const DECISION_CONTENT = {
  title: "Sentetik karar başlığı",
  options: [
    { id: "o1", title: "Birinci seçenek", description: null, pros: [], cons: [] },
    { id: "o2", title: "İkinci seçenek", description: null, pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Ölçüt", weight: 5 }],
};

const ANALYSIS: StoredAnalysis = {
  summary: "Sentetik özet.",
  strengths: ["g1"],
  weaknesses: ["z1"],
  risks: ["r1"],
  recommendation: "Sentetik öneri.",
  confidence: "medium",
  model: "test-model",
  promptVersion: "v1",
};

/** Rezervasyon tahmini — üretimdeki formülün aynısı. */
const ESTIMATE = estimateUsage({
  systemPrompt: "s".repeat(1000),
  userPrompt: "u".repeat(1000),
  maxOutputTokens: 800,
  model: ANALYSIS.model,
});

const USAGE = { inputTokens: 1500, outputTokens: 600 };
const COST_USD = computeCostUsd(ANALYSIS.model, USAGE);

const FINGERPRINT = contentFingerprint({
  content: DECISION_CONTENT as never,
  model: ANALYSIS.model,
  promptVersion: ANALYSIS.promptVersion,
});

let app: App;

beforeAll(() => {
  assertEmulatorOnly();
  // Kimlik bilgisi VERİLMEZ: emulator host'u ayarlıyken Admin SDK yalnız
  // emulator'e konuşur, ADC'ye hiç başvurmaz.
  app = initializeApp({ projectId: PROJECT_ID });
});

afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore();
const ports = () => new FirestoreAnalysisPorts(UID);
const userRef = () => db().doc(`users/${UID}`);
const decisionRef = () => db().doc(`users/${UID}/decisions/${DECISION_ID}`);
const journalRef = () =>
  db().doc(`users/${UID}/analysisRequests/${REQUEST_ID}`);

async function wipe(): Promise<void> {
  await db().recursiveDelete(userRef());
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

/** Kredi düşümünün gözlemlenebilmesi için havuz AÇIKÇA yazılır. */
async function seed(): Promise<void> {
  await userRef().set({ plan: "free", freeAnalysisCredits: 5, rewardCredits: 0 });
  await decisionRef().set({ ...DECISION_CONTENT, status: "draft" });
}

async function seedProviderSucceeded(): Promise<void> {
  await seed();
  await ports().reserve({
    requestId: REQUEST_ID,
    decisionId: DECISION_ID,
    contentFingerprint: FINGERPRINT,
    estimate: ESTIMATE,
  });
  // Üretim sırası: reserved → provider_call_started → provider_succeeded.
  // Ara adım ATLANAMAZ; journal geçiş kapısı buna izin vermez.
  const started = await ports().markProviderCallStarted(REQUEST_ID);
  if (!started) throw new Error("fixture: provider_call_started geçişi reddedildi");
  await ports().recordProviderSuccess({
    requestId: REQUEST_ID,
    analysis: ANALYSIS,
    usage: { inputTokens: 10, outputTokens: 20 },
  });
}

beforeEach(async () => {
  assertEmulatorOnly();
  await wipe();
});

describe("gerçek transaction — reserve yarışı", () => {
  it(`${PARALLEL} paralel reserve'den YALNIZ biri created alır`, async () => {
    await seed();

    const results = await Promise.all(
      Array.from({ length: PARALLEL }, () =>
        ports().reserve({
          requestId: REQUEST_ID,
          decisionId: DECISION_ID,
          contentFingerprint: FINGERPRINT,
          estimate: ESTIMATE,
        }),
      ),
    );

    expect(results.filter((r) => r.status === "created")).toHaveLength(1);
    const snap = await journalRef().get();
    expect(snap.exists).toBe(true);
    expect(snap.data()!["state"]).toBe(JournalState.reserved);
  });
});

describe("gerçek transaction — provider çağrısı yarışı", () => {
  it(`${PARALLEL} paralel markProviderCallStarted'dan YALNIZ biri true alır`, async () => {
    await seed();
    await ports().reserve({
      requestId: REQUEST_ID,
      decisionId: DECISION_ID,
      contentFingerprint: FINGERPRINT,
      estimate: ESTIMATE,
    });

    const results = await Promise.all(
      Array.from({ length: PARALLEL }, () =>
        ports().markProviderCallStarted(REQUEST_ID),
      ),
    );

    expect(results.filter(Boolean)).toHaveLength(1);
  });
});

describe("gerçek transaction — finalize yarışı", () => {
  it("paralel finalize'da kredi TAM BİR KEZ düşer", async () => {
    await seedProviderSucceeded();

    const results = await Promise.all(
      Array.from({ length: PARALLEL }, () =>
        ports().finalize({
          requestId: REQUEST_ID,
          decisionId: DECISION_ID,
          analysis: ANALYSIS,
          initialCredits: 5,
          usage: USAGE,
          costUsd: COST_USD,
        }),
      ),
    );

    expect(results.every((r) => r.outcome === "completed")).toBe(true);
    expect(results.every((r) => r.analysisId === LATEST_ANALYSIS_ID)).toBe(true);

    const user = await userRef().get();
    expect(user.data()!["freeAnalysisCredits"]).toBe(4);

    const journal = await journalRef().get();
    expect(journal.data()!["state"]).toBe(JournalState.completed);

    const decision = await decisionRef().get();
    expect(decision.data()!["status"]).toBe("analyzed");

    const analyses = await decisionRef().collection("aiAnalyses").get();
    expect(analyses.size).toBe(1);
    expect(analyses.docs[0]!.id).toBe(LATEST_ANALYSIS_ID);
  });

  it("tamamlanmış isteğin YENİDEN finalize'ı krediyi bir daha düşürmez", async () => {
    await seedProviderSucceeded();
    await ports().finalize({
      requestId: REQUEST_ID,
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    const again = await ports().finalize({
      requestId: REQUEST_ID,
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    expect(again.outcome).toBe("completed");
    const user = await userRef().get();
    expect(user.data()!["freeAnalysisCredits"]).toBe(4);
  });

  it("karar analiz sürerken DEĞİŞTİYSE superseded olur ve kredi YANMAZ", async () => {
    await seedProviderSucceeded();
    await decisionRef().update({ title: "Kullanıcı başlığı değiştirdi" });

    const result = await ports().finalize({
      requestId: REQUEST_ID,
      decisionId: DECISION_ID,
      analysis: ANALYSIS,
      initialCredits: 5,
      usage: USAGE,
      costUsd: COST_USD,
    });

    expect(result.outcome).toBe("superseded");
    const user = await userRef().get();
    expect(user.data()!["freeAnalysisCredits"]).toBe(5);

    const analyses = await decisionRef().collection("aiAnalyses").get();
    expect(analyses.size).toBe(0);

    const journal = await journalRef().get();
    expect(journal.data()!["state"]).toBe(JournalState.superseded);
  });
});
