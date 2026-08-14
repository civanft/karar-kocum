/** KVKK / Store P0 hesap silme kaskadı (PR-R1, sertleştirme PR-R1B). */
import { onCall, type CallableRequest } from "firebase-functions/v2/https";

import { toHttpsError } from "../core/errors.js";
import { log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";
import { buildContext } from "../middleware/context.js";
import {
  deleteAccountCascade,
  type AccountDeletionPorts,
} from "./delete_account_service.js";
import { firestoreAccountDeletionPorts } from "./firestore_account_deletion_ports.js";

export const deleteAccountOptions = {
  enforceAppCheck: true,
  consumeAppCheckToken: true,
  memory: "512MiB",
  timeoutSeconds: 300,
  maxInstances: 3,
} as const;

/**
 * Oturum kurulmadan hata oluşursa loglama için kullanılan bağlam.
 *
 * NEDEN: buildContext auth yoksa AppError fırlatır. Bu çağrı try'ın DIŞINDA
 * kalsaydı hata toHttpsError'dan geçmez, Firebase onu anonim `internal`e
 * çevirirdi — istemci "geçici hata, tekrar dene" sanır ve sonsuza dek
 * yeniden denerdi. Oysa doğru cevap `unauthenticated`tir.
 */
function contextlessLogContext(): RequestContext {
  return {
    fn: "deleteAccount",
    jobId: "no-auth",
    uid: "", // kimlik yok — hash'lenecek bir şey de yok
    uidHash: "anonymous",
    startedAtMs: Date.now(),
  };
}

/**
 * Callable gövdesi — portlar enjekte edilebilir olduğu için test edilebilir.
 * UID YALNIZ doğrulanmış oturumdan gelir; `request.data` HİÇ okunmaz.
 */
export async function handleDeleteAccount(
  request: CallableRequest,
  ports: AccountDeletionPorts,
): Promise<{ deleted: true }> {
  let ctx: RequestContext | undefined;
  try {
    ctx = buildContext("deleteAccount", request);
    const result = await deleteAccountCascade(ctx.uid, ports);
    log("info", "account_deleted", ctx, { deleted: true });
    return result;
  } catch (error) {
    const logCtx = ctx ?? contextlessLogContext();
    const cause = (error as { cause?: unknown }).cause;
    if (cause !== undefined) {
      // Yalnız SUNUCU log'una; istemciye giden mesaj toHttpsError'da genel.
      log("error", "account_deletion_cause", logCtx, {
        reason: cause instanceof Error ? cause.message : String(cause),
      });
    }
    throw toHttpsError(error, logCtx);
  }
}

export const deleteAccount = onCall(deleteAccountOptions, (request) =>
  handleDeleteAccount(request, firestoreAccountDeletionPorts),
);
