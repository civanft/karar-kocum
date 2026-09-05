/**
 * HESAP SİLME BARİYERİ (İş Paketi 3) — tek merkez.
 *
 * ═══ NEDEN GEREKLİ ═══
 *
 * Hesap silme kaskadı `users/{uid}` ağacını sildikten SONRA Auth
 * kullanıcısı silinene kadar eski Firebase ID token GEÇERLİ kalır (token
 * ömrü bir saate kadar çıkabilir). O pencerede:
 *  - istemci bir karar yazarsa silinmiş veri DİRİLİR ve yetim kalır;
 *  - devam eden bir AI analizi finalize olursa kullanıcı ağacı yeniden
 *    oluşur;
 *  - bir ödül callback'i kredi yazarsa kullanıcı belgesi yeniden doğar.
 *
 * Bariyer, silme başlarken yazılan İÇERİK TAŞIMAYAN bir belgedir.
 * Varlığı hem Firestore Rules'ta (istemci yazmaları) hem de Admin SDK
 * yollarında (sunucu yazmaları) yeni kullanıcı verisi oluşumunu kapatır.
 *
 * ═══ NEDEN YALNIZ RULES YETMEZ ═══
 *
 * Admin SDK Rules'u BYPASS eder. Bu yüzden sunucu yazma yolları bariyeri
 * KENDİ transaction'ları İÇİNDE okumak zorundadır: transaction öncesi tek
 * bir `get()` yapmak, "bariyer ile yazım aynı anda commit ederse" yarışını
 * çözmez. Firestore transaction'ı okunan belgeyi çakışma kümesine alır;
 * bariyer araya girerse transaction yeniden çalışır ve bu kez bariyeri
 * görür.
 *
 * ═══ VERİ MİNİMİZASYONU ═══
 *
 * Belge gövdesi PII TAŞIMAZ: yalnız şema sürümü, durum ve iki zaman damgası.
 * UID yalnız belge KİMLİĞİDİR — doğrudan lookup için zorunludur (sorgu
 * gerektirmez, indeks gerektirmez).
 *
 * ═══ DURUM MAKİNESİ (İş Paketi 3B) ═══
 *
 *   deleting  → silme SÜRÜYOR.  `expiresAt` alanı YOKTUR.
 *   deleted   → silme BİTTİ ve Auth kullanıcısı gerçekten kaldırıldı.
 *               `completedAt` ve `expiresAt` yazılır.
 *
 * NEDEN `deleting` durumunda TTL alanı YOK: Firestore TTL yalnız timestamp
 * taşıyan `expiresAt` alanını işler. 3. Pakette bariyer oluşturulurken
 * `expiresAt` yazılıyordu; silme 48 saatten uzun süre tamamlanamazsa TTL
 * bariyeri kaldırır, Auth hesabı hâlâ dururken eski/yeni oturum tekrar
 * veri yazabilirdi. Bu FAIL-CLOSED DEĞİLDİ. Artık tamamlanmamış bir silme
 * bariyeri SÜRESİZ durur — güvenlik yönünde kalıcı bariyer, Auth mevcutken
 * bariyerin erken silinmesinden daha güvenlidir.
 *
 * `expiresAt` yalnız terminal geçişte ve `completedAt`'ten en az 48 saat
 * sonrasına yazılır. Gerekçe: eski ID token'lar bir saate kadar yaşayabilir,
 * TTL silmesi anlık değildir ve bariyer, kimlik belirteci doğal olarak
 * geçersizleşmeden KALDIRILMAMALIDIR.
 */
import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";

export const ACCOUNT_DELETION_BLOCKS = "accountDeletionBlocks";

/** Bariyer şeması sürümü — gövde alanları değişirse artar. */
export const BARRIER_SCHEMA_VERSION = 1;

/**
 * TERMİNAL bariyerin yaşam süresi. Eski ID token ömrü (~1 saat) + TTL
 * silmesinin anlık olmaması + güvenlik payı. 48 saat ALT sınırdır.
 * Yalnız `deleted` durumundaki bariyere uygulanır.
 */
export const BARRIER_TTL_MS = 48 * 60 * 60 * 1000;

/** Bariyer durumları — `deleted` → `deleting` geçişi YASAKTIR. */
export type BarrierState = "deleting" | "deleted";

export function barrierRef(db: Firestore, uid: string) {
  return db.doc(`${ACCOUNT_DELETION_BLOCKS}/${uid}`);
}

/** Bariyer varken kullanıcı verisi oluşturmaya çalışan her yolun hatası. */
export function accountDeletingError(): AppError {
  return new AppError(
    "account-deleting",
    "Hesap silme işlemi sürüyor — bu işlem yapılamaz.",
  );
}

/**
 * `deleting` bariyerini OLUŞTUR ya da MİGRE ET — idempotent.
 *
 *  - Yoksa: `deleting` + `startedAt` yazılır. TTL alanı YAZILMAZ.
 *  - Varsa ve `deleting` ise: `startedAt` İLERİ TAŞINMAZ. Eski (3. Paket)
 *    biçimde `expiresAt` taşıyorsa GÜVENLİ MİGRASYON olarak kaldırılır —
 *    aksi hâlde tamamlanmamış bir silme TTL ile açılabilirdi.
 *  - Varsa ve `deleted` ise: DOKUNULMAZ. Terminal bariyer tekrar
 *    `deleting` yapılamaz.
 */
export async function raiseDeletionBarrier(
  db: Firestore,
  uid: string,
  _nowMs: number,
): Promise<{ created: boolean; alreadyCompleted: boolean }> {
  const ref = barrierRef(db, uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.create(ref, {
        schemaVersion: BARRIER_SCHEMA_VERSION,
        state: "deleting" satisfies BarrierState,
        startedAt: FieldValue.serverTimestamp(),
      });
      return { created: true, alreadyCompleted: false };
    }

    const data = snap.data()!;
    if (data["state"] === "deleted") {
      return { created: false, alreadyCompleted: true };
    }

    // MİGRASYON: 3. Paket biçimindeki `deleting + expiresAt` kaydından TTL
    // alanını kaldır. `startedAt` KORUNUR.
    if (data["expiresAt"] !== undefined) {
      tx.update(ref, { expiresAt: FieldValue.delete() });
    }
    return { created: false, alreadyCompleted: false };
  });
}

/**
 * TERMİNAL GEÇİŞ — `deleting` → `deleted`.
 *
 * YALNIZ veri temizliği doğrulandıktan VE Auth kullanıcısı gerçekten
 * silindikten sonra çağrılır. TTL saati burada başlar.
 *
 * İdempotenttir: zaten `deleted` ise `completedAt`/`expiresAt` İLERİ
 * TAŞINMAZ. Bariyer hiçbir zaman `deleting`'e geri döndürülmez.
 */
export async function completeDeletionBarrier(
  db: Firestore,
  uid: string,
  nowMs: number,
): Promise<void> {
  const ref = barrierRef(db, uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    if (snap.data()!["state"] === "deleted") return;
    tx.update(ref, {
      state: "deleted" satisfies BarrierState,
      completedAt: Timestamp.fromMillis(nowMs),
      expiresAt: Timestamp.fromMillis(nowMs + BARRIER_TTL_MS),
    });
  });
}

/**
 * TRANSACTION İÇİNDE bariyer kontrolü — sunucu yazma yollarının kapısı.
 *
 * Okuma transaction'ın çakışma kümesine girer: bariyer yazımı araya
 * girerse transaction yeniden çalışır ve reddeder.
 *
 * ÖNEMLİ: Firestore tüm okumaların yazımlardan ÖNCE yapılmasını ister —
 * bu çağrı transaction'ın ilk okumalarıyla birlikte yapılmalıdır.
 */
export async function assertAccountActive(
  tx: FirebaseFirestore.Transaction,
  db: Firestore,
  uid: string,
): Promise<void> {
  const snap = await tx.get(barrierRef(db, uid));
  if (snap.exists) throw accountDeletingError();
}

/** Transaction dışı, en iyi çaba kontrol (yalnız erken çıkış için). */
export async function isAccountDeleting(
  db: Firestore,
  uid: string,
): Promise<boolean> {
  return (await barrierRef(db, uid).get()).exists;
}
