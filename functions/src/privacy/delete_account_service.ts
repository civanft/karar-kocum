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
  /** users/{uid} ağacını alt koleksiyonlarıyla (decisions → aiAnalyses,
   *  rewardTickets, subscriptions) birlikte siler. */
  recursiveDeleteUser(uid: string): Promise<void>;
  /** Tek belgeyi siler; belge yoksa no-op. */
  deleteDocument(path: string): Promise<void>;
  /** Firebase Auth kullanıcısını siler. */
  deleteAuthUser(uid: string): Promise<void>;
}

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
export type AccountDeletionFailureStage = "firestore" | "auth";

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

export async function deleteAccountCascade(
  uid: string,
  ports: AccountDeletionPorts,
): Promise<{ deleted: true }> {
  // [1] Firestore: kullanıcı ağacı (alt koleksiyonlar dahil).
  try {
    await ports.recursiveDeleteUser(uid);
    // [2] Firestore: users ağacının dışındaki UID'li belgeler.
    for (const path of topLevelPaths(uid)) {
      await ports.deleteDocument(path);
    }
  } catch (cause) {
    // Auth'a GEÇİLMEZ: veri dururken hesabı silmek yetim veri bırakır.
    throw withDiagnostic(
      new AppError("internal", "Veriler silinemedi, tekrar dene."),
      describeCause("firestore", cause),
    );
  }

  // [3] Auth kullanıcısı en son.
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

  return { deleted: true };
}
