/**
 * Firestore rules testleri — emulator zorunlu (npm run test:rules).
 * Kapsam: sahiplik, sunucu-sahipli alanlar, Y-5 negatif senaryoları.
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;

const validDecision = (ownerUid: string) => ({
  ownerUid,
  title: "Telefon seçimi",
  status: "draft",
  options: [
    { id: "a", title: "iPhone", pros: [], cons: [] },
    { id: "b", title: "Samsung", pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Fiyat", weight: 8, source: "user" }],
  scores: {},
  isFavorite: false,
  searchTokens: ["telefon"],
});

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-karar",
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

const db = (uid: string) => env.authenticatedContext(uid).firestore();

describe("users belgesi", () => {
  it("kullanıcı kendi profilini free planla oluşturabilir", async () => {
    await assertSucceeds(
      db("ali").doc("users/ali").set({ plan: "free", locale: "tr" }),
    );
  });

  it("NEGATİF: premium planla oluşturma reddedilir", async () => {
    await assertFails(
      db("ali").doc("users/ali").set({ plan: "premium" }),
    );
  });

  it("NEGATİF: plan/quota alanları istemciden değiştirilemez", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin
        .firestore()
        .doc("users/ali")
        .set({ plan: "free", quota: { month: "2026-07", used: 1 } });
    });
    await assertFails(
      db("ali").doc("users/ali").update({ plan: "premium" }),
    );
    await assertFails(
      db("ali")
        .doc("users/ali")
        .update({ quota: { month: "2026-07", used: 0 } }),
    );
    // ama zararsız alan güncellenebilir:
    await assertSucceeds(
      db("ali").doc("users/ali").update({ locale: "en" }),
    );
  });

  it("NEGATİF: başkasının profili okunamaz", async () => {
    await assertFails(db("veli").doc("users/ali").get());
  });
});

describe("decisions belgesi", () => {
  it("sahibi geçerli karar oluşturabilir ve okuyabilir", async () => {
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/d1").set(validDecision("ali")),
    );
    await assertSucceeds(db("ali").doc("users/ali/decisions/d1").get());
  });

  it("NEGATİF (Y-5): ownerUid ≠ yol uid'i → reddedilir", async () => {
    await assertFails(
      db("ali").doc("users/ali/decisions/d1").set(validDecision("veli")),
    );
  });

  it("NEGATİF: başkasının kararına yazma/okuma reddedilir", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin
        .firestore()
        .doc("users/ali/decisions/d1")
        .set(validDecision("ali"));
    });
    await assertFails(db("veli").doc("users/ali/decisions/d1").get());
    await assertFails(
      db("veli")
        .doc("users/ali/decisions/d1")
        .update({ title: "Ele geçirildi" }),
    );
  });

  it("NEGATİF: limit ihlalleri — tek seçenek, uzun başlık", async () => {
    const single = validDecision("ali");
    single.options = [single.options[0]!];
    await assertFails(
      db("ali").doc("users/ali/decisions/d1").set(single),
    );

    const longTitle = { ...validDecision("ali"), title: "x".repeat(101) };
    await assertFails(
      db("ali").doc("users/ali/decisions/d2").set(longTitle),
    );
  });

  it("NEGATİF: latestAnalysisId ve status='analyzed' istemciden yazılamaz", async () => {
    await assertFails(
      db("ali")
        .doc("users/ali/decisions/d1")
        .set({ ...validDecision("ali"), latestAnalysisId: "sahte" }),
    );
    await assertFails(
      db("ali")
        .doc("users/ali/decisions/d2")
        .set({ ...validDecision("ali"), status: "analyzed" }),
    );

    // update yolu:
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/d3").set(validDecision("ali")),
    );
    await assertFails(
      db("ali")
        .doc("users/ali/decisions/d3")
        .update({ latestAnalysisId: "sahte" }),
    );
    await assertFails(
      db("ali").doc("users/ali/decisions/d3").update({ status: "analyzed" }),
    );
    // arşivleme serbest:
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/d3").update({
        status: "archived",
        ...validDecision("ali"),
      }),
    );
  });
});

describe("sunucu-sahipli koleksiyonlar", () => {
  it("NEGATİF: aiAnalyses istemciden yazılamaz, sahibi okuyabilir", async () => {
    await assertFails(
      db("ali")
        .doc("users/ali/decisions/d1/aiAnalyses/a1")
        .set({ summary: "sahte analiz" }),
    );
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin
        .firestore()
        .doc("users/ali/decisions/d1/aiAnalyses/a1")
        .set({ summary: "gerçek analiz" });
    });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/d1/aiAnalyses/a1").get(),
    );
    await assertFails(
      db("veli").doc("users/ali/decisions/d1/aiAnalyses/a1").get(),
    );
  });

  it("NEGATİF: subscriptions istemciden yazılamaz", async () => {
    await assertFails(
      db("ali")
        .doc("users/ali/subscriptions/e1")
        .set({ type: "INITIAL_PURCHASE" }),
    );
  });

  it("NEGATİF: aiJobs tamamen kapalı", async () => {
    await assertFails(db("ali").doc("aiJobs/j1").get());
    await assertFails(db("ali").doc("aiJobs/j1").set({ uid: "ali" }));
  });

  it("templates herkese okunur, kimseye yazılmaz", async () => {
    await assertSucceeds(db("ali").doc("templates/t1").get());
    await assertFails(db("ali").doc("templates/t1").set({ title: "x" }));
  });
});
