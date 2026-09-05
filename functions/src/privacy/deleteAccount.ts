/** KVKK / Store P0 hesap silme kaskadı (PR-R1, sertleştirme PR-R1B). */
import { onCall, type CallableRequest } from "firebase-functions/v2/https";

import {
  deleteRuntimeServiceAccount,
  functionRegion,
} from "../core/deployment.js";

import { toHttpsError } from "../core/errors.js";
import { log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";
import {
  buildContext,
  contextlessLogContext,
} from "../middleware/context.js";
import {
  deleteAccountCascade,
  deletionDiagnosticOf,
  type AccountDeletionPorts,
} from "./delete_account_service.js";
import { firestoreAccountDeletionPorts } from "./firestore_account_deletion_ports.js";

export const deleteAccountOptions = {
  region: functionRegion,
  serviceAccount: deleteRuntimeServiceAccount,
  enforceAppCheck: true,
  consumeAppCheckToken: true,
  memory: "512MiB",
  timeoutSeconds: 300,
  maxInstances: 3,
} as const;

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
    log("info", "account_deleted", ctx, {
      deleted: true,
      barrierFinalized: result.barrierFinalized,
    });
    if (!result.barrierFinalized) {
      // Veri ve Auth GERÇEKTEN silindi; yalnız bariyerin terminal işareti
      // yazılamadı. Güvenlik yönünde fail-closed kalınır (bariyer süresiz
      // durur) ve nadir durumda manuel reconciliation gerekir. Sabit alan;
      // ham uid/yol/mesaj YOK.
      log("warn", "account_deletion_barrier_not_finalized", ctx, {
        reason: "terminal_transition_failed",
      });
    }
    // Dış sözleşme DEĞİŞMEZ: istemci yalnız { deleted: true } görür.
    return { deleted: true as const };
  } catch (error) {
    const logCtx = ctx ?? contextlessLogContext("deleteAccount");
    const diagnostic = deletionDiagnosticOf(error);
    if (diagnostic !== undefined) {
      // YALNIZ sabit alanlar: ham mesaj/stack/yol/uid loglanmaz (PR-R1C).
      log("error", "account_deletion_failed", logCtx, { ...diagnostic });
    }
    throw toHttpsError(error, logCtx);
  }
}

export const deleteAccount = onCall(deleteAccountOptions, (request) =>
  handleDeleteAccount(request, firestoreAccountDeletionPorts),
);
