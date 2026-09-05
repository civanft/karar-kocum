/**
 * PR-R1B — hesap silme kaskadının GERÇEK Admin SDK sınırında doğrulanması.
 *
 * Birim testleri portları mock'lar; burada üretimde koşan adaptörün
 * kendisi (recursiveDelete / doc().delete() / getAuth().deleteUser())
 * gerçek Firestore + Auth emulator'üne karşı çalışır. Böylece
 * "recursiveDelete alt koleksiyonları da siliyor mu" gibi ancak gerçek
 * SDK'nın cevaplayabileceği sorular kanıtlanır.
 *
 * Çalıştırma: npm run test:privacy
 *
 * CANLI ERİŞİM YAPISAL OLARAK ENGELLİ:
 *  - proje kimliği `demo-` önekli olmak ZORUNDA (Firebase bu öneki yalnız
 *    emulator'e ayırır; böyle bir bulut projesi oluşturulamaz)
 *  - iki emulator host değişkeni de yoksa test HİÇ BAŞLAMAZ (fail-fast)
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { deleteAccountCascade } from "../src/privacy/delete_account_service";
import { firestoreAccountDeletionPorts } from "../src/privacy/firestore_account_deletion_ports";

const PROJECT_ID = "demo-karar";
const TARGET_UID = "silinecek-kullanici";
const OTHER_UID = "korunacak-kullanici";

/** Emulator dışına çıkmayı imkânsız kılan ön koşullar. */
function assertEmulatorOnly(): void {
  const missing = [
    "FIRESTORE_EMULATOR_HOST",
    "FIREBASE_AUTH_EMULATOR_HOST",
  ].filter((key) => !process.env[key]);

  if (missing.length > 0) {
    throw new Error(
      `Emulator zorunlu: ${missing.join(", ")} tanımlı değil. ` +
        "Bu testi 'npm run test:privacy' ile çalıştır.",
    );
  }
  if (!PROJECT_ID.startsWith("demo-")) {
    throw new Error("Yalnız demo-* projesi kullanılabilir.");
  }
}

let app: App;

beforeAll(() => {
  assertEmulatorOnly();
  // Kimlik bilgisi VERİLMEZ: emulator host'ları ayarlıyken Admin SDK
  // yalnız emulator'e konuşur, ADC'ye hiç başvurmaz.
  // VARSAYILAN app: üretim adaptörü getFirestore()/getAuth() ile bu app'i
  // çözer. Adlandırılmış app kullanılsaydı test, üretimde koşan yolu değil
  // başka bir bağlantıyı sınardı.
  app = initializeApp({ projectId: PROJECT_ID });
});

afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore();
const auth = () => getAuth();

/** Silinecek ve korunacak kullanıcıların tam veri ağacını kurar. */
async function seed(): Promise<void> {
  const store = db();

  await store.doc(`users/${TARGET_UID}`).set({
    decisionCount: 2,
    freeCreditsRemaining: 3,
  });
  await store.doc(`users/${TARGET_UID}/decisions/karar-1`).set({
    ownerUid: TARGET_UID,
    title: "Telefon",
  });
  await store.doc(`users/${TARGET_UID}/decisions/karar-2`).set({
    ownerUid: TARGET_UID,
    title: "Şehir",
  });
  // İÇ İÇE alt koleksiyon — recursiveDelete'in asıl sınavı.
  await store
    .doc(`users/${TARGET_UID}/decisions/karar-1/aiAnalyses/latest`)
    .set({ summary: "analiz" });
  await store
    .doc(`users/${TARGET_UID}/rewardTickets/bilet-1`)
    .set({ status: "pending" });
  await store
    .doc(`users/${TARGET_UID}/subscriptions/olay-1`)
    .set({ product: "premium" });
  // İş Paketi 2: analiz journal'ı da kullanıcının ağacındadır ve
  // hesap silindiğinde ARKADA KALMAMALIDIR.
  await store
    .doc(`users/${TARGET_UID}/analysisRequests/${"c".repeat(24)}`)
    .set({ state: "completed", decisionId: "karar-1" });

  // users ağacının DIŞINDAKİ, uid'e bağlı sayaçlar.
  await store.doc(`rateLimits/${TARGET_UID}`).set({ minute: 1 });
  await store.doc(`rateLimits/${TARGET_UID}:reward`).set({ minute: 1 });

  // Korunması gerekenler.
  await store.doc(`users/${OTHER_UID}`).set({ decisionCount: 1 });
  await store
    .doc(`users/${OTHER_UID}/decisions/baska-karar`)
    .set({ ownerUid: OTHER_UID, title: "Dokunulmamalı" });
  await store
    .doc(`users/${OTHER_UID}/decisions/baska-karar/aiAnalyses/latest`)
    .set({ summary: "korunmalı" });
  await store.doc(`rateLimits/${OTHER_UID}`).set({ minute: 1 });
  await store.doc("ops/dailyAnalysisCount").set({ count: 7 });

  await auth().createUser({ uid: TARGET_UID });
  await auth().createUser({ uid: OTHER_UID });
}

async function wipe(): Promise<void> {
  const store = db();
  for (const uid of [TARGET_UID, OTHER_UID]) {
    await store.recursiveDelete(store.doc(`users/${uid}`));
    await store.doc(`rateLimits/${uid}`).delete();
    await store.doc(`rateLimits/${uid}:reward`).delete();
    try {
      await auth().deleteUser(uid);
    } catch {
      /* zaten yok */
    }
  }
  await store.doc("ops/dailyAnalysisCount").delete();
}

async function exists(path: string): Promise<boolean> {
  return (await db().doc(path).get()).exists;
}

async function authUserExists(uid: string): Promise<boolean> {
  try {
    await auth().getUser(uid);
    return true;
  } catch {
    return false;
  }
}

describe("hesap silme kaskadı — gerçek Firestore + Auth emulator", () => {
  beforeEach(async () => {
    await wipe();
    await seed();
  });

  it("hedef kullanıcının TÜM ağacını (iç içe dahil) siler", async () => {
    // Fixture gerçekten yazıldı mı? Yazılmadıysa aşağıdaki "silindi"
    // iddiaları BOŞ YERE geçerdi.
    expect(
      await exists(`users/${TARGET_UID}/analysisRequests/${"c".repeat(24)}`),
    ).toBe(true);

    await deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts);

    expect(await exists(`users/${TARGET_UID}`)).toBe(false);
    expect(await exists(`users/${TARGET_UID}/decisions/karar-1`)).toBe(false);
    expect(await exists(`users/${TARGET_UID}/decisions/karar-2`)).toBe(false);
    expect(
      await exists(`users/${TARGET_UID}/decisions/karar-1/aiAnalyses/latest`),
    ).toBe(false);
    expect(await exists(`users/${TARGET_UID}/rewardTickets/bilet-1`)).toBe(
      false,
    );
    expect(await exists(`users/${TARGET_UID}/subscriptions/olay-1`)).toBe(
      false,
    );
    expect(
      await exists(`users/${TARGET_UID}/analysisRequests/${"c".repeat(24)}`),
    ).toBe(false);
  });

  it("her iki rateLimits belgesini de siler", async () => {
    await deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts);

    expect(await exists(`rateLimits/${TARGET_UID}`)).toBe(false);
    expect(await exists(`rateLimits/${TARGET_UID}:reward`)).toBe(false);
  });

  it("Auth kullanıcısını siler", async () => {
    expect(await authUserExists(TARGET_UID)).toBe(true);

    await deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts);

    expect(await authUserExists(TARGET_UID)).toBe(false);
  });

  it("başka kullanıcının verisine ve Auth hesabına DOKUNMAZ", async () => {
    await deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts);

    expect(await exists(`users/${OTHER_UID}`)).toBe(true);
    expect(await exists(`users/${OTHER_UID}/decisions/baska-karar`)).toBe(true);
    expect(
      await exists(`users/${OTHER_UID}/decisions/baska-karar/aiAnalyses/latest`),
    ).toBe(true);
    expect(await exists(`rateLimits/${OTHER_UID}`)).toBe(true);
    expect(await authUserExists(OTHER_UID)).toBe(true);
  });

  it("ops global sayacını KORUR", async () => {
    await deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts);

    const ops = await db().doc("ops/dailyAnalysisCount").get();
    expect(ops.exists).toBe(true);
    expect(ops.data()?.count).toBe(7);
  });

  it("ikinci çalıştırma idempotenttir (boş ağaç + silinmiş Auth)", async () => {
    await deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts);

    await expect(
      deleteAccountCascade(TARGET_UID, firestoreAccountDeletionPorts),
    ).resolves.toMatchObject({ deleted: true });
  });

  it("hiç var olmayan kullanıcı için de başarılı biter", async () => {
    await expect(
      deleteAccountCascade("hic-olmayan-uid", firestoreAccountDeletionPorts),
    ).resolves.toMatchObject({ deleted: true });
  });

  it("emulator dışına çıkılmadığı doğrulanır", () => {
    expect(process.env.FIRESTORE_EMULATOR_HOST).toBeTruthy();
    expect(process.env.FIREBASE_AUTH_EMULATOR_HOST).toBeTruthy();
    expect(PROJECT_ID.startsWith("demo-")).toBe(true);
  });
});
