/**
 * Firestore rules testleri — emulator zorunlu (npm run test:rules).
 * Kapsam: sahiplik, sunucu-sahipli alanlar, Y-5 negatif senaryoları.
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestContext,
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

// uid → tek Firestore örneği. Aynı test içinde birden fazla context açmak
// "Firestore has already been started" hatası üretiyor (batch yardımcıları
// doğrudan çağrılarla birlikte kullanıldığında).
type TestFirestore = ReturnType<RulesTestContext["firestore"]>;
const clients = new Map<string, TestFirestore>();

const db = (uid: string): TestFirestore => {
  const cached = clients.get(uid);
  if (cached) return cached;
  const created = env.authenticatedContext(uid).firestore();
  clients.set(uid, created);
  return created;
};

/**
 * SECURITY: decisionCount mutasyonu artık AYNI batch'teki gerçek karar
 * create/delete'ine bağlıdır (decisionCountMutationId eşleme alanı).
 * Test yardımcıları üretimdeki repository batch'ini birebir taklit eder.
 *
 * @param count  batch SONRASI beklenen sayaç değeri (before ± 1)
 * @param withPlan  user belgesi henüz yokken zorunlu ('free'); mevcut
 *                  (özellikle premium) kullanıcıda GÖNDERİLMEZ.
 */
const atomicCreate = (
  uid: string,
  decisionId: string,
  data: object,
  opts: { count: number; withPlan?: boolean } = { count: 1 },
) => {
  const client = db(uid);
  const batch = client.batch();
  batch.set(client.doc(`users/${uid}/decisions/${decisionId}`), data);
  batch.set(
    client.doc(`users/${uid}`),
    {
      ...(opts.withPlan === false ? {} : { plan: "free" }),
      decisionCount: opts.count,
      decisionCountMutationId: decisionId,
    },
    { merge: true },
  );
  return batch.commit();
};

const atomicDelete = (
  uid: string,
  decisionId: string,
  opts: { count: number },
) => {
  const client = db(uid);
  const batch = client.batch();
  batch.delete(client.doc(`users/${uid}/decisions/${decisionId}`));
  batch.set(
    client.doc(`users/${uid}`),
    {
      decisionCount: opts.count,
      decisionCountMutationId: decisionId,
    },
    { merge: true },
  );
  return batch.commit();
};

/** Admin ile hazır kullanıcı + karar durumu kurar (rules baypas). */
const seed = (
  users: Record<string, object>,
  decisions: Record<string, object> = {},
) =>
  env.withSecurityRulesDisabled(async (admin) => {
    // admin.firestore() BİR KEZ: her çağrı settings uygulamaya çalışır ve
    // ikincisi "Firestore has already been started" hatası verir.
    const store = admin.firestore();
    for (const [path, data] of Object.entries({ ...users, ...decisions })) {
      await store.doc(path).set(data);
    }
  });

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
    // Setup admin ile: testin konusu UPDATE, create değil.
    await seed({}, { "users/ali/decisions/sb1": validDecision("ali") });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/sb1").update({
        decisionStatus: "decided",
        chosenOptionId: "a",
        decidedAt: new Date(),
      }),
    );
  });

  it("SPRINT B: geri alma İZİNLİ (open + alanlar null)", async () => {
    await seed({}, {
      "users/ali/decisions/sb2": {
        ...validDecision("ali"),
        decisionStatus: "decided",
        chosenOptionId: "a",
        decidedAt: new Date(),
      },
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
      atomicCreate("ali", "sb3", {
        ...validDecision("ali"),
        decisionStatus: "open",
      }),
    );
  });

  it("SPRINT B REGRESYON: taahhüt alanları sunucu korumasını DELMEZ", async () => {
    await seed({}, { "users/ali/decisions/sb4": validDecision("ali") });
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
      atomicCreate("ali", "blank1", {
        ...validDecision("ali"),
        options: [],
        criteria: [],
      }),
    );
  });

  it("HOTFIX: 2 seçenekli create izinli kalır (şablon yolu)", async () => {
    await assertSucceeds(
      atomicCreate("ali", "tmpl1", validDecision("ali")),
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
      atomicCreate("ali", "toomany", { ...validDecision("ali"), options }),
    );
  });

  it("HOTFIX: tek seçeneğe düşüren update izinli (silme akışı)", async () => {
    await seed({}, { "users/ali/decisions/upd1": validDecision("ali") });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/upd1").update({
        options: [{ id: "a", title: "iPhone", pros: [], cons: [] }],
      }),
    );
  });

  it("sahibi geçerli karar oluşturabilir ve okuyabilir", async () => {
    await assertSucceeds(atomicCreate("ali", "d1", validDecision("ali")));
    await assertSucceeds(db("ali").doc("users/ali/decisions/d1").get());
  });

  it("hotfix madde 5: 50/51 cap — 49→50 izinli, 50→51 reddedilir", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 50 } });
    await assertFails(
      atomicCreate("ali", "d51", validDecision("ali"), {
        count: 51,
        withPlan: false,
      }),
    );

    await seed({ "users/ali": { plan: "free", decisionCount: 49 } });
    await assertSucceeds(
      atomicCreate("ali", "d50", validDecision("ali"), {
        count: 50,
        withPlan: false,
      }),
    );
  });

  it("hotfix madde 5: sayaç sıçraması ve BAĞIMSIZ ±1 reddedilir", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 40 } });
    // 40 → 0 sıçraması reddedilir:
    await assertFails(db("ali").doc("users/ali").update({ decisionCount: 0 }));
    // SECURITY: 40 → 41 artık TEK BAŞINA da reddedilir (atomik karar
    // create'i olmadan sayaç ilerletilemez).
    await assertFails(db("ali").doc("users/ali").update({ decisionCount: 41 }));
  });

  it("NEGATİF (Y-5): ownerUid ≠ yol uid'i → reddedilir", async () => {
    await assertFails(atomicCreate("ali", "d1", validDecision("veli")));
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
    await assertFails(atomicCreate("ali", "d2", longTitle));

    const manyCriteria = {
      ...validDecision("ali"),
      criteria: Array.from({ length: 16 }, (_, i) => ({
        id: `c${i}`,
        name: `K${i}`,
        weight: 5,
        source: "user",
      })),
    };
    await assertFails(atomicCreate("ali", "d3", manyCriteria));
  });

  it("NEGATİF: latestAnalysisId ve status='analyzed' istemciden yazılamaz", async () => {
    await assertFails(
      atomicCreate("ali", "d1", {
        ...validDecision("ali"),
        latestAnalysisId: "sahte",
      }),
    );
    await assertFails(
      atomicCreate("ali", "d2", {
        ...validDecision("ali"),
        status: "analyzed",
      }),
    );

    // update yolu:
    await assertSucceeds(atomicCreate("ali", "d3", validDecision("ali")));
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
    await seed({}, {
      "users/ali/decisions/c1": {
        ...validDecision("ali"),
        decisionStatus: "decided",
        chosenOptionId: "a",
      },
    });
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/c1").update({
        checkInStatus: "happy",
        checkedInAt: new Date(),
      }),
    );
  });

  it("SPRINT C.2: ikinci check-in REDDEDİLİR (tek kayıt kuralı)", async () => {
    await seed({}, {
      "users/ali/decisions/c2": {
        ...validDecision("ali"),
        decisionStatus: "decided",
        chosenOptionId: "a",
        checkInStatus: "happy",
        checkedInAt: new Date(),
      },
    });
    await assertFails(
      db("ali").doc("users/ali/decisions/c2").update({
        checkInStatus: "regret",
        checkedInAt: new Date(),
      }),
    );
  });

  it("SPRINT C.2: yazılmış check-in SİLİNEMEZ", async () => {
    await seed({}, {
      "users/ali/decisions/c3": {
        ...validDecision("ali"),
        checkInStatus: "neutral",
        checkedInAt: new Date(),
      },
    });
    await assertFails(
      db("ali").doc("users/ali/decisions/c3").update({ checkInStatus: null }),
    );
  });

  it("SPRINT C.2: geçersiz check-in değeri REDDEDİLİR", async () => {
    await seed({}, { "users/ali/decisions/c4": validDecision("ali") });
    await assertFails(
      db("ali").doc("users/ali/decisions/c4").update({
        checkInStatus: "harika",
        checkedInAt: new Date(),
      }),
    );
  });

  it("SPRINT C.2: check-in'e dokunmayan güncellemeler ETKİLENMEZ", async () => {
    await seed({}, {
      "users/ali/decisions/c5": {
        ...validDecision("ali"),
        checkInStatus: "happy",
        checkedInAt: new Date(),
      },
    });
    // Başlık değişimi, cevap yazılmış olsa bile serbest kalmalı:
    await assertSucceeds(
      db("ali").doc("users/ali/decisions/c5").update({ title: "Yeni başlık" }),
    );
  });

  it("SPRINT C.2 REGRESYON: check-in sunucu korumasını DELMEZ", async () => {
    await seed({}, { "users/ali/decisions/c6": validDecision("ali") });
    await assertFails(
      db("ali").doc("users/ali/decisions/c6").update({
        checkInStatus: "happy",
        latestAnalysisId: "sahte",
      }),
    );
  });

  it("SPRINT C.2: başkasının kararına check-in yazılamaz", async () => {
    await seed({}, { "users/ali/decisions/c7": validDecision("ali") });
    await assertFails(
      db("veli").doc("users/ali/decisions/c7").update({
        checkInStatus: "happy",
      }),
    );
  });

});

// ---- SECURITY HOTFIX: decisionCount ↔ atomik karar yazımı bağı ----
//
// Açık: sayaç istemciden bağımsız ±1 değiştirilebiliyordu; tekrarlı
// azaltımla 50 karar sınırı aşılabiliyordu. Yeni invariant: sayaç yalnız
// AYNI batch'te gerçek bir karar create/delete edilirken ve
// decisionCountMutationId o karar id'sini taşırken ilerleyebilir.
describe("decisionCount atomikliği (security hotfix)", () => {
  it("1) ilk user + ilk karar aynı batch: İZİNLİ (0→1, marker doğru)", async () => {
    await assertSucceeds(
      atomicCreate("ali", "n1", validDecision("ali"), { count: 1 }),
    );
  });

  it("2) mevcut user + yeni karar: İZİNLİ (N→N+1)", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 3 } });
    await assertSucceeds(
      atomicCreate("ali", "n2", validDecision("ali"), {
        count: 4,
        withPlan: false,
      }),
    );
  });

  it("3) karar oluşturmadan sayaç +1: REDDEDİLİR", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 3 } });
    await assertFails(
      db("ali").doc("users/ali").update({
        decisionCount: 4,
        decisionCountMutationId: "hayali",
      }),
    );
  });

  it("4) karar silmeden sayaç -1: REDDEDİLİR (cap istismarı)", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 40 } });
    await assertFails(
      db("ali").doc("users/ali").update({
        decisionCount: 39,
        decisionCountMutationId: "hayali",
      }),
    );
  });

  it("5) karar create var ama sayaç artmıyor: REDDEDİLİR", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 3 } });
    await assertFails(
      db("ali").doc("users/ali/decisions/n5").set(validDecision("ali")),
    );
  });

  it("6) karar delete var ama sayaç azalmıyor: REDDEDİLİR", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 1 } },
      { "users/ali/decisions/n6": validDecision("ali") },
    );
    await assertFails(db("ali").doc("users/ali/decisions/n6").delete());
  });

  it("7) create'te YANLIŞ mutationId: REDDEDİLİR", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 3 } });
    const client = db("ali");
    const batch = client.batch();
    batch.set(client.doc("users/ali/decisions/n7"), validDecision("ali"));
    batch.set(
      client.doc("users/ali"),
      { decisionCount: 4, decisionCountMutationId: "baska-id" },
      { merge: true },
    );
    await assertFails(batch.commit());
  });

  it("8) delete'te YANLIŞ mutationId: REDDEDİLİR", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 2 } },
      { "users/ali/decisions/n8": validDecision("ali") },
    );
    const client = db("ali");
    const batch = client.batch();
    batch.delete(client.doc("users/ali/decisions/n8"));
    batch.set(
      client.doc("users/ali"),
      { decisionCount: 1, decisionCountMutationId: "baska-id" },
      { merge: true },
    );
    await assertFails(batch.commit());
  });

  it("9) BAŞKA kullanıcının kararı sayaç kanıtı olamaz: REDDEDİLİR", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 5 } },
      { "users/veli/decisions/vd1": validDecision("veli") },
    );
    // Veli'nin kararının id'siyle kendi sayacını düşürmeye çalışır:
    await assertFails(
      db("ali").doc("users/ali").update({
        decisionCount: 4,
        decisionCountMutationId: "vd1",
      }),
    );
  });

  it("10) marker alanını TEK BAŞINA değiştirme: REDDEDİLİR", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 1 } },
      { "users/ali/decisions/n10": validDecision("ali") },
    );
    await assertFails(
      db("ali").doc("users/ali").update({ decisionCountMutationId: "n10" }),
    );
  });

  it("11) 49→50 atomik create: İZİNLİ", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 49 } });
    await assertSucceeds(
      atomicCreate("ali", "n11", validDecision("ali"), {
        count: 50,
        withPlan: false,
      }),
    );
  });

  it("12) 50→51 atomik create: REDDEDİLİR (cap korunur)", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 50 } });
    await assertFails(
      atomicCreate("ali", "n12", validDecision("ali"), {
        count: 51,
        withPlan: false,
      }),
    );
  });

  it("13) geçerli atomik delete: İZİNLİ (N→N-1)", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 2 } },
      { "users/ali/decisions/n13": validDecision("ali") },
    );
    await assertSucceeds(atomicDelete("ali", "n13", { count: 1 }));
  });

  it("14) aynı silme üzerinden İKİNCİ decrement: REDDEDİLİR", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 2 } },
      { "users/ali/decisions/n14": validDecision("ali") },
    );
    await assertSucceeds(atomicDelete("ali", "n14", { count: 1 }));
    // Karar artık yok; aynı id ile ikinci azaltım kanıtsızdır:
    await assertFails(
      db("ali").doc("users/ali").update({
        decisionCount: 0,
        decisionCountMutationId: "n14",
      }),
    );
  });

  it("15) sayaç DIŞI profil güncellemesi çalışmaya devam eder", async () => {
    await seed({ "users/ali": { plan: "free", decisionCount: 3 } });
    await assertSucceeds(
      db("ali").doc("users/ali").update({ locale: "en" }),
    );
  });

  it("16) plan/kredi korumaları sayaç yolundan DELİNEMEZ", async () => {
    await seed(
      { "users/ali": { plan: "free", decisionCount: 1 } },
      { "users/ali/decisions/n16": validDecision("ali") },
    );
    const client = db("ali");
    // Geçerli atomik delete'e plan yükseltmesi iliştirilemez:
    const batch = client.batch();
    batch.delete(client.doc("users/ali/decisions/n16"));
    batch.set(
      client.doc("users/ali"),
      {
        decisionCount: 0,
        decisionCountMutationId: "n16",
        plan: "premium",
      },
      { merge: true },
    );
    await assertFails(batch.commit());

    // freeAnalysisCredits / rewardCredits de aynı yoldan yazılamaz:
    const batch2 = client.batch();
    batch2.delete(client.doc("users/ali/decisions/n16"));
    batch2.set(
      client.doc("users/ali"),
      {
        decisionCount: 0,
        decisionCountMutationId: "n16",
        freeAnalysisCredits: 999,
      },
      { merge: true },
    );
    await assertFails(batch2.commit());
  });

  it("17) eski user belgesi (marker alanı YOK) atomik create ile ilerler",
    async () => {
      // Migration'sız uyum: alanı hiç olmayan belge.
      await seed({ "users/ali": { plan: "free", decisionCount: 7 } });
      await assertSucceeds(
        atomicCreate("ali", "n17", validDecision("ali"), {
          count: 8,
          withPlan: false,
        }),
      );
    });
});
