/**
 * Karar Veriyorum — CANLI smoke test (karar-veriyorum-dev)
 * Gerçek Firebase projesine karşı: init, anonim auth, Google provider
 * kontrolü, Firestore CRUD ve rules negatif davranışları.
 */
import { initializeApp } from "firebase/app";
import { getAuth, signInAnonymously, deleteUser } from "firebase/auth";
import {
  getFirestore, doc, setDoc, getDoc, updateDoc, deleteDoc,
} from "firebase/firestore";
import { readSmokeFirebaseConfig } from "./firebase_config.mjs";

const config = readSmokeFirebaseConfig();

const results = [];
function record(step, ok, detail = "") {
  results.push({ step, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} | ${step}${detail ? " — " + detail : ""}`);
}

async function expectDenied(step, promise) {
  try {
    await promise;
    record(step, false, "İZİN VERİLDİ — rules deliği!");
  } catch (e) {
    const denied = String(e.code || e.message).includes("permission-denied");
    record(step, denied, denied ? "permission-denied (beklenen)" : `beklenmeyen hata: ${e.code}`);
  }
}

const validDecision = (ownerUid) => ({
  ownerUid,
  title: "Smoke test kararı",
  status: "draft",
  options: [
    { id: "a", title: "Seçenek A", pros: [], cons: [] },
    { id: "b", title: "Seçenek B", pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Fiyat", weight: 5, source: "user" }],
  scores: {},
  isFavorite: false,
  searchTokens: ["smoke", "test"],
  createdAt: new Date(),
  updatedAt: new Date(),
});

// [1] Init
let app, auth, db;
try {
  app = initializeApp(config);
  auth = getAuth(app);
  db = getFirestore(app);
  record("1. Firebase initialization", true, config.projectId);
} catch (e) {
  record("1. Firebase initialization", false, e.message);
  process.exit(1);
}

// [2] Anonim auth
let uid;
try {
  const cred = await signInAnonymously(auth);
  uid = cred.user.uid;
  record("2. Anonymous authentication", true, `uid=${uid.slice(0, 8)}…`);
} catch (e) {
  record("2. Anonymous authentication", false, `${e.code}: ${e.message}`);
  process.exit(1);
}

// [3] Google Sign-In sağlayıcısı etkin mi? (createAuthUri REST)
try {
  const r = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=${config.apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        providerId: "google.com",
        continueUri: "http://localhost",
        identifier: "smoke@example.com",
      }),
    },
  );
  const body = await r.json();
  const enabled = r.ok && (body.authUri || body.signinMethods !== undefined);
  record(
    "3. Google Sign-In sağlayıcısı",
    Boolean(enabled),
    enabled ? "provider yapılandırılmış (authUri üretildi)" : JSON.stringify(body.error?.message ?? body),
  );
} catch (e) {
  record("3. Google Sign-In sağlayıcısı", false, e.message);
}

// [4-5] Firestore bağlantısı + ilk karar oluşturma
const decisionRef = doc(db, `users/${uid}/decisions/smoke-d1`);
try {
  await setDoc(decisionRef, validDecision(uid));
  const snap = await getDoc(decisionRef);
  record("4. Firestore bağlantısı", true, "yazma+okuma çalışıyor");
  record("5. İlk karar oluşturma", snap.exists() && snap.data().title === "Smoke test kararı");
} catch (e) {
  record("4. Firestore bağlantısı", false, `${e.code}: ${e.message}`);
  record("5. İlk karar oluşturma", false, "önceki adım başarısız");
}

// [6] Güncelleme
try {
  await updateDoc(decisionRef, { title: "Güncellenmiş smoke kararı", updatedAt: new Date() });
  const snap = await getDoc(decisionRef);
  record("6. Karar güncelleme", snap.data()?.title === "Güncellenmiş smoke kararı");
} catch (e) {
  record("6. Karar güncelleme", false, `${e.code}`);
}

// [8] Rules negatifleri (silmeden önce)
await expectDenied(
  "8a. Rules: ownerUid sahteciliği (Y-5)",
  setDoc(doc(db, `users/${uid}/decisions/smoke-d2`), validDecision("baskasi")),
);
await expectDenied(
  "8b. Rules: başkasının kararını okuma",
  getDoc(doc(db, "users/baska-kullanici/decisions/x")),
);
await expectDenied(
  "8c. Rules: premium planla profil oluşturma",
  setDoc(doc(db, `users/${uid}`), { plan: "premium" }),
);
await expectDenied(
  "8d. Rules: aiAnalyses'e istemci yazımı",
  setDoc(doc(db, `users/${uid}/decisions/smoke-d1/aiAnalyses/sahte`), { summary: "sahte" }),
);
await expectDenied(
  "8e. Rules: latestAnalysisId istemciden set etme",
  updateDoc(decisionRef, { latestAnalysisId: "sahte" }),
);
await expectDenied(
  "8f. Rules: tek seçenekli karar (limit ihlali)",
  setDoc(doc(db, `users/${uid}/decisions/smoke-d3`), {
    ...validDecision(uid),
    options: [{ id: "a", title: "Tek", pros: [], cons: [] }],
  }),
);

// [7] Silme + temizlik
try {
  await deleteDoc(decisionRef);
  const snap = await getDoc(decisionRef);
  record("7. Karar silme", !snap.exists());
} catch (e) {
  record("7. Karar silme", false, `${e.code}`);
}
try {
  await deleteUser(auth.currentUser); // anonim test kullanıcısı geride kalmasın
  record("Temizlik: anonim kullanıcı silindi", true);
} catch (e) {
  record("Temizlik: anonim kullanıcı silindi", false, e.code);
}

const failed = results.filter((r) => !r.ok);
console.log(`\nSONUÇ: ${results.length - failed.length}/${results.length} adım geçti`);
process.exit(failed.length === 0 ? 0 : 1);
