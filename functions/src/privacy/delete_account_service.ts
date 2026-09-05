/**
 * Hesap silme kaskadı (PR-R1) — saf orkestrasyon, Admin SDK'dan AYRIK.
 *
 * Sözleşme:
 *  - UID YALNIZ çağıranın doğrulanmış kimliğinden gelir (callable katmanı
 *    request.auth.uid verir); istemci payload'ı bu akışa giremez.
 *  - Sıra KRİTİK: önce Firestore, en son Auth. Auth önce silinseydi
 *    kullanıcının token'ı geçersizleşir ve kalan veri yetim kalırdı.
 *  - İdempotent: olmayan belge/kullanıcı no-op'tur; ikinci çağrı da başarılı.
 *  - Loglama/hata: ham uid ve upstream detay ASLA istemciye/mesaja sızmaz.
 */
import { AppError } from "../core/errors.js";

export interface AccountDeletionPorts {
  /**
   * [1] BARİYER — idempotent. Tekrar çağrıda süre İLERİ TAŞINMAZ.
   * Bariyerden sonra hiçbir istemci/sunucu yolu yeni kullanıcı verisi
   * oluşturamaz (Rules + Admin SDK guard).
   */
  raiseBarrier(uid: string): Promise<void>;

  /**
   * [3] DRAIN — bariyerden ÖNCE açılmış AI rezervasyonlarını güvenle
   * kapatır ve GERİYE KALAN açık rezervasyon sayısını döndürür.
   *
   * `olderThanMs`: bir rezervasyonun "artık çalışmıyor" sayılabilmesi için
   * geçmesi gereken süre. analyzeDecision'ın fonksiyon timeout'undan
   * (60 sn) büyük olmalıdır; daha genç kayıtlar HENÜZ çalışıyor olabilir
   * ve zorla kapatılmaz.
   */
  drainOpenReservations(
    uid: string,
    olderThanMs: number,
  ): Promise<{ open: number }>;

  /** users/{uid} ağacını alt koleksiyonlarıyla (decisions → aiAnalyses,
   *  rewardTickets, subscriptions, analysisRequests, analysisReservations)
   *  birlikte siler. */
  recursiveDeleteUser(uid: string): Promise<void>;
  /** Tek belgeyi siler; belge yoksa no-op. */
  deleteDocument(path: string): Promise<void>;
  /** [6] Temizliğin GERÇEKTEN tamamlandığını doğrular. */
  userDataRemains(uid: string): Promise<boolean>;
  /** Firebase Auth kullanıcısını siler. */
  deleteAuthUser(uid: string): Promise<void>;
}

/** Test edilebilir zaman/bekleme — üretimde gerçek saat ve timer. */
export interface DeletionClock {
  now(): number;
  sleep(ms: number): Promise<void>;
}

export const systemDeletionClock: DeletionClock = {
  now: () => Date.now(),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

/**
 * Bir rezervasyon bu süre boyunca açık kaldıysa onu açan çağrı ARTIK
 * çalışmıyordur: analyzeDecision'ın fonksiyon timeout'u 60 sn.
 * 90 sn, timeout + soğuk başlatma/ağ payını kapsayan güvenli eşiktir.
 */
export const RESERVATION_SETTLED_AFTER_MS = 90_000;

/** Drain için toplam bekleme bütçesi (deleteAccount timeout'u 300 sn). */
export const DRAIN_MAX_WAIT_MS = 120_000;

/** Drain yoklama aralığı. */
export const DRAIN_POLL_MS = 5_000;

/** UID'e bağlı, users ağacının DIŞINDA kalan top-level belgeler. */
function topLevelPaths(uid: string): string[] {
  return [
    `rateLimits/${uid}`, // analyzeDecision limiti
    `rateLimits/${uid}:reward`, // createRewardTicket limiti (ayrı belge)
  ];
}

function isUserNotFound(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { code?: unknown }).code === "auth/user-not-found"
  );
}

/** Hatanın hangi adımda oluştuğu — sabit küme, PII taşımaz. */
export type AccountDeletionFailureStage =
  | "barrier"
  | "drain"
  | "firestore"
  | "auth";

/**
 * Üretimde teşhis için taşınan TEK bilgi. Hepsi sabit/denetlenmiş
 * değerlerdir; ham mesaj, stack, belge yolu veya uid ASLA girmez.
 */
export interface AccountDeletionDiagnostic {
  failureStage: AccountDeletionFailureStage;
  causeType: string;
  causeCode: string;
}

/**
 * İzinli kod biçimi. '/' ve ':' bilinçli olarak DIŞARIDA: belge yolu ya da
 * "uid:reward" gibi bir anahtar yanlışlıkla kod alanına düşerse geçemesin.
 */
const SAFE_TOKEN = /^[A-Za-z0-9_.-]{1,64}$/;

function safeToken(value: unknown): string {
  if (typeof value !== "string" && typeof value !== "number") return "unknown";
  const text = String(value);
  return SAFE_TOKEN.test(text) ? text : "unknown";
}

/**
 * Ham hatayı güvenli teşhis alanlarına indirger.
 *
 * NEDEN: Firestore Admin hatalarının message/stack'i belge YOLUNU taşır ve
 * yol uid içerir. Log hijyeni ham uid'i yasaklar (§9.2); bu yüzden hatadan
 * yalnız sınıf adı ve kod alanı — o da biçim denetiminden geçerek — alınır.
 */
export function describeCause(
  failureStage: AccountDeletionFailureStage,
  cause: unknown,
): AccountDeletionDiagnostic {
  const code = (cause as { code?: unknown } | null | undefined)?.code;
  return {
    failureStage,
    causeType: safeToken(
      (cause as { constructor?: { name?: unknown } } | null | undefined)
        ?.constructor?.name,
    ),
    causeCode: safeToken(code),
  };
}

/** Teşhis, Symbol ile iliştirilir: JSON'a serileşmez, kazara sızmaz. */
const DIAGNOSTIC = Symbol("accountDeletionDiagnostic");

function withDiagnostic(
  error: AppError,
  diagnostic: AccountDeletionDiagnostic,
): AppError {
  (error as unknown as Record<symbol, unknown>)[DIAGNOSTIC] = diagnostic;
  return error;
}

/** Handler bunu okuyup loglar; başka hiçbir yerde hata detayı yoktur. */
export function deletionDiagnosticOf(
  error: unknown,
): AccountDeletionDiagnostic | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  return (error as Record<symbol, AccountDeletionDiagnostic | undefined>)[
    DIAGNOSTIC
  ];
}

/**
 * DOĞRUSALLAŞTIRILMIŞ HESAP SİLME (İş Paketi 3).
 *
 * SIRA KRİTİK ve her adım bir öncekinin değişmezine dayanır:
 *
 *  1. BARİYER — idempotent. Bundan sonra hiçbir istemci veya sunucu yolu
 *     yeni kullanıcı verisi OLUŞTURAMAZ.
 *  2. DRAIN — bariyerden ÖNCE açılmış AI rezervasyonları güvenle kapanır.
 *     Kapanmadan silmeye geçilirse devam eden analiz veriyi DİRİLTİR.
 *  3. RECURSIVE DELETE — users/{uid} ağacı.
 *  4. TOP-LEVEL — UID'ye bağlı, ağacın dışındaki belgeler.
 *  5. DOĞRULAMA — temizlik gerçekten bitti mi.
 *  6. AUTH — EN SON. Veri dururken hesabı silmek yetim veri bırakırdı.
 *  7. BARİYER KALIR — TTL politikası kaldırır. Başarı yolunda SİLİNMEZ:
 *     eski ID token bir saate kadar geçerli kalabilir ve bariyer o token
 *     doğal olarak geçersizleşmeden kaldırılmamalıdır.
 *
 * Her adım idempotenttir; herhangi bir adımdan sonra gelen retry akışı
 * kaldığı yerden güvenle tamamlar.
 */
export async function deleteAccountCascade(
  uid: string,
  ports: AccountDeletionPorts,
  clock: DeletionClock = systemDeletionClock,
): Promise<{ deleted: true }> {
  // [1] BARİYER — İLK adım. Başarısızsa hiçbir silme yapılmaz.
  try {
    await ports.raiseBarrier(uid);
  } catch (cause) {
    throw withDiagnostic(
      new AppError("internal", "Silme başlatılamadı, tekrar dene."),
      describeCause("barrier", cause),
    );
  }

  // [2] DRAIN — bounded bekleme. Bloklayıcı meşgul-bekleme YOK.
  try {
    const deadline = clock.now() + DRAIN_MAX_WAIT_MS;
    for (;;) {
      const { open } = await ports.drainOpenReservations(
        uid,
        RESERVATION_SETTLED_AFTER_MS,
      );
      if (open === 0) break;
      if (clock.now() >= deadline) {
        // Güvenle kapanamayan iş var: AUTH SİLİNMEZ, veri SİLİNMEZ.
        // Bariyer duruyor, bu yüzden yeni veri de oluşamaz; kullanıcı
        // tekrar denediğinde akış kaldığı yerden devam eder.
        throw new AppError(
          "ai-unavailable",
          "Silme işlemi tamamlanamadı, birazdan tekrar dene.",
        );
      }
      await clock.sleep(DRAIN_POLL_MS);
    }
  } catch (cause) {
    if (cause instanceof AppError) throw cause;
    throw withDiagnostic(
      new AppError("internal", "Silme işlemi tamamlanamadı, tekrar dene."),
      describeCause("drain", cause),
    );
  }

  // [3]+[4] Firestore: kullanıcı ağacı ve UID'li top-level belgeler.
  try {
    await ports.recursiveDeleteUser(uid);
    for (const path of topLevelPaths(uid)) {
      await ports.deleteDocument(path);
    }
  } catch (cause) {
    throw withDiagnostic(
      new AppError("internal", "Veriler silinemedi, tekrar dene."),
      describeCause("firestore", cause),
    );
  }

  // [5] DOĞRULAMA — Auth'a geçmeden önce temizlik gerçekten bitmiş olmalı.
  try {
    if (await ports.userDataRemains(uid)) {
      throw new AppError("internal", "Veriler silinemedi, tekrar dene.");
    }
  } catch (cause) {
    if (cause instanceof AppError) throw cause;
    throw withDiagnostic(
      new AppError("internal", "Veriler silinemedi, tekrar dene."),
      describeCause("firestore", cause),
    );
  }

  // [6] Auth kullanıcısı EN SON.
  try {
    await ports.deleteAuthUser(uid);
  } catch (error) {
    if (!isUserNotFound(error)) {
      throw withDiagnostic(
        new AppError("internal", "Hesap silinemedi, tekrar dene."),
        describeCause("auth", error),
      );
    }
    // Zaten yok → idempotent başarı.
  }

  // [7] Bariyer KALIR — TTL kaldırır. Burada silinmez.
  return { deleted: true };
}
