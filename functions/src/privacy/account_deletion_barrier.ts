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
 * `expiresAt` en az 48 saat ileridedir. Gerekçe: eski ID token'lar bir
 * saate kadar yaşayabilir, TTL silmesi anlık değildir ve bariyer, eski
 * kimlik belirteci doğal olarak geçersizleşmeden KALDIRILMAMALIDIR.
 */
import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";

export const ACCOUNT_DELETION_BLOCKS = "accountDeletionBlocks";

/** Bariyer şeması sürümü — gövde alanları değişirse artar. */
export const BARRIER_SCHEMA_VERSION = 1;

/**
 * Bariyerin yaşam süresi. Eski ID token ömrü (~1 saat) + TTL silmesinin
 * anlık olmaması + güvenlik payı. 48 saat ALT sınırdır.
 */
export const BARRIER_TTL_MS = 48 * 60 * 60 * 1000;

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
 * Bariyeri OLUŞTUR — idempotent.
 *
 * Tekrar çağrıda `startedAt` ve `expiresAt` İLERİ TAŞINMAZ: her retry
 * süreyi uzatsaydı bariyer hiç sona ermeyebilirdi. Mevcut bariyer olduğu
 * gibi korunur.
 */
export async function raiseDeletionBarrier(
  db: Firestore,
  uid: string,
  nowMs: number,
): Promise<{ created: boolean }> {
  const ref = barrierRef(db, uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return { created: false };
    tx.create(ref, {
      schemaVersion: BARRIER_SCHEMA_VERSION,
      state: "deleting",
      startedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(nowMs + BARRIER_TTL_MS),
    });
    return { created: true };
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
