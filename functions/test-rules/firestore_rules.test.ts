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

  it("NEGATİF (6C-2): freeAnalysisCredits İLE profil oluşturulamaz", async () => {
    await assertFails(
      db("ali")
        .doc("users/ali")
        .set({ plan: "free", freeAnalysisCredits: 9999 }),
    );
  });

  it("NEGATİF (7A): rewardCredits istemciden yazılamaz", async () => {
    await assertFails(
      db("ali").doc("users/ali").set({ plan: "free", rewardCredits: 99 }),
    );
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin
        .firestore()
        .doc("users/ali")
        .set({ plan: "free", rewardCredits: 1 });
    });
    await assertFails(
      db("ali").doc("users/ali").update({ rewardCredits: 100 }),
    );
  });

  it("NEGATİF (7A): rewardTickets istemciye tamamen kapalı", async () => {
    await assertFails(
      db("ali")
        .doc("users/ali/rewardTickets/t1")
        .set({ status: "granted" }),
    );
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin
        .firestore()
        .doc("users/ali/rewardTickets/t1")
        .set({ status: "pending" });
    });
    await assertFails(db("ali").doc("users/ali/rewardTickets/t1").get());
    await assertFails(
      db("ali")
        .doc("users/ali/rewardTickets/t1")
        .update({ status: "granted" }),
    );
  });

  it("NEGATİF (6C-2): freeAnalysisCredits istemciden güncellenemez", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin
        .firestore()
        .doc("users/ali")
        .set({ plan: "free", freeAnalysisCredits: 2 });
    });
    // artırma, sıfırlama ve silme girişimlerinin tümü reddedilir:
    await assertFails(
      db("ali").doc("users/ali").update({ freeAnalysisCredits: 5 }),
    );
    await assertFails(
      db("ali").doc("users/ali").update({ freeAnalysisCredits: 0 }),
    );
    // zararsız alan güncellemesi hâlâ serbest:
    await assertSucceeds(
      db("ali").doc("users/ali").update({ locale: "tr" }),
    );
  });
});

describe("decisions belgesi", () => {
  // ---- Sprint B: "Kararımı Verdim" taahhüt alanları ----

  it("SPRINT B: taahhüt update'i İZİNLİ (decisionStatus/chosenOptionId/decidedAt)", async () => {
    await db("ali").doc("users/ali/decisions/sb1").set(validDecision("ali"));
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/sb1").update({
        decisionStatus: "decided",
        chosenOptionId: "a",
        decidedAt: new Date(),
      }),
    );
  });

  it("SPRINT B: geri alma İZİNLİ (open + alanlar null)", async () => {
    await db("ali").doc("users/ali/decisions/sb2").set({
      ...validDecision("ali"),
      decisionStatus: "decided",
      chosenOptionId: "a",
      decidedAt: new Date(),
    });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/sb2").update({
        decisionStatus: "open",
        chosenOptionId: null,
        decidedAt: null,
      }),
    );
  });

  it("SPRINT B: create taahhüt alanlarıyla da geçer (şema kabul)", async () => {
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/sb3").set({
        ...validDecision("ali"),
        decisionStatus: "open",
      }),
    );
  });

  it("SPRINT B REGRESYON: taahhüt alanları sunucu korumasını DELMEZ", async () => {
    await db("ali").doc("users/ali/decisions/sb4").set(validDecision("ali"));
    // latestAnalysisId hâlâ yazılamaz — taahhüt alanıyla birlikte de:
    await assertFails(
      db("ali").doc("users/ali/decisions/sb4").update({
        decisionStatus: "decided",
        chosenOptionId: "a",
        latestAnalysisId: "sahte",
      }),
    );
    // status='analyzed' hâlâ engelli:
    await assertFails(
      db("ali").doc("users/ali/decisions/sb4").update({
        decisionStatus: "decided",
        status: "analyzed",
      }),
    );
  });

  it("HOTFIX: BOŞ taslak create İZİNLİ (0 seçenek — 'Devam Et' yolu)", async () => {
    await assertSucceeds(
      db("ali")
        .doc("users/ali/decisions/blank1")
        .set({ ...validDecision("ali"), options: [], criteria: [] }),
    );
  });

  it("HOTFIX: 2 seçenekli create izinli kalır (şablon yolu)", async () => {
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/tmpl1").set(validDecision("ali")),
    );
  });

  it("HOTFIX: üst sınır KORUNUR — 11 seçenekli create reddedilir", async () => {
    const options = Array.from({ length: 11 }, (_, i) => ({
      id: `o${i}`,
      title: `Seçenek ${i}`,
      pros: [],
      cons: [],
    }));
    await assertFails(
      db("ali")
        .doc("users/ali/decisions/toomany")
        .set({ ...validDecision("ali"), options }),
    );
  });

  it("HOTFIX: tek seçeneğe düşüren update izinli (silme akışı)", async () => {
    await db("ali").doc("users/ali/decisions/upd1").set(validDecision("ali"));
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/upd1").update({
        options: [{ id: "a", title: "iPhone", pros: [], cons: [] }],
      }),
    );
  });

  it("sahibi geçerli karar oluşturabilir ve okuyabilir", async () => {
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/d1").set(validDecision("ali")),
    );
    await assertSucceeds(db("ali").doc("users/ali/decisions/d1").get());
  });

  it("hotfix madde 5: decisionCount 50'de yeni karar reddedilir", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc("users/ali").set({
        plan: "free",
        decisionCount: 50,
      });
    });
    await assertFails(
      db("ali").doc("users/ali/decisions/d51").set(validDecision("ali")),
    );

    // 49'da yeni karar geçer:
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc("users/ali").set({
        plan: "free",
        decisionCount: 49,
      });
    });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/d50").set(validDecision("ali")),
    );
  });

  it("hotfix madde 5: decisionCount sıfırlama hilesi engellenir (±1)", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await admin.firestore().doc("users/ali").set({
        plan: "free",
        decisionCount: 40,
      });
    });
    // 40 → 0 sıçraması reddedilir:
    await assertFails(
      db("ali").doc("users/ali").update({ decisionCount: 0 }),
    );
    // 40 → 41 (increment) serbest:
    await assertSucceeds(
      db("ali").doc("users/ali").update({ decisionCount: 41 }),
    );
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

  it("NEGATİF: limit ihlalleri — uzun başlık, fazla kriter", async () => {
    // NOT: 'tek seçenek reddedilir' beklentisi HOTFIX ile bilinçli
    // kaldırıldı — taslaklar az seçenekle yaşayabilir; 'analiz için
    // min 2' kuralı Functions/zod'da (analyze_service.test: tek seçenek
    // → invalid-argument). Rules yalnız üst sınır şeklini korur.
    const longTitle = { ...validDecision("ali"), title: "x".repeat(101) };
    await assertFails(
      db("ali").doc("users/ali/decisions/d2").set(longTitle),
    );

    const manyCriteria = {
      ...validDecision("ali"),
      criteria: Array.from({ length: 16 }, (_, i) => ({
        id: `c${i}`,
        name: `K${i}`,
        weight: 5,
        source: "user",
      })),
    };
    await assertFails(
      db("ali").doc("users/ali/decisions/d3").set(manyCriteria),
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

  // ---- SPRINT C.2: 1 hafta kontrolü — karar başına TEK kayıt ----

  it("SPRINT C.2: ilk check-in yazımı İZİNLİ", async () => {
    await db("ali").doc("users/ali/decisions/c1").set({
      ...validDecision("ali"),
      decisionStatus: "decided",
      chosenOptionId: "a",
    });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/c1").update({
        checkInStatus: "happy",
        checkedInAt: new Date(),
      }),
    );
  });

  it("SPRINT C.2: ikinci check-in REDDEDİLİR (tek kayıt kuralı)", async () => {
    await db("ali").doc("users/ali/decisions/c2").set({
      ...validDecision("ali"),
      decisionStatus: "decided",
      chosenOptionId: "a",
      checkInStatus: "happy",
      checkedInAt: new Date(),
    });
    await assertFails(
      db("ali").doc("users/ali/decisions/c2").update({
        checkInStatus: "regret",
        checkedInAt: new Date(),
      }),
    );
  });

  it("SPRINT C.2: yazılmış check-in SİLİNEMEZ", async () => {
    await db("ali").doc("users/ali/decisions/c3").set({
      ...validDecision("ali"),
      checkInStatus: "neutral",
      checkedInAt: new Date(),
    });
    await assertFails(
      db("ali").doc("users/ali/decisions/c3").update({ checkInStatus: null }),
    );
  });

  it("SPRINT C.2: geçersiz check-in değeri REDDEDİLİR", async () => {
    await db("ali").doc("users/ali/decisions/c4").set(validDecision("ali"));
    await assertFails(
      db("ali").doc("users/ali/decisions/c4").update({
        checkInStatus: "harika",
        checkedInAt: new Date(),
      }),
    );
  });

  it("SPRINT C.2: check-in'e dokunmayan güncellemeler ETKİLENMEZ", async () => {
    await db("ali").doc("users/ali/decisions/c5").set({
      ...validDecision("ali"),
      checkInStatus: "happy",
      checkedInAt: new Date(),
    });
    // Başlık değişimi, cevap yazılmış olsa bile serbest kalmalı:
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/c5").update({ title: "Yeni başlık" }),
    );
  });

  it("SPRINT C.2 REGRESYON: check-in sunucu korumasını DELMEZ", async () => {
    await db("ali").doc("users/ali/decisions/c6").set(validDecision("ali"));
    await assertFails(
      db("ali").doc("users/ali/decisions/c6").update({
        checkInStatus: "happy",
        latestAnalysisId: "sahte",
      }),
    );
  });

  it("SPRINT C.2: başkasının kararına check-in yazılamaz", async () => {
    await db("ali").doc("users/ali/decisions/c7").set(validDecision("ali"));
    await assertFails(
      db("veli").doc("users/ali/decisions/c7").update({
        checkInStatus: "happy",
      }),
    );
  });

});
