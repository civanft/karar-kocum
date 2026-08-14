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
  } catch {
    // Auth'a GEÇİLMEZ: veri dururken hesabı silmek yetim veri bırakır.
    throw new AppError("internal", "Veriler silinemedi, tekrar dene.");
  }

  // [3] Auth kullanıcısı en son.
  try {
    await ports.deleteAuthUser(uid);
  } catch (error) {
    if (!isUserNotFound(error)) {
      throw new AppError("internal", "Hesap silinemedi, tekrar dene.");
    }
    // Zaten yok → idempotent başarı.
  }

  return { deleted: true };
}
