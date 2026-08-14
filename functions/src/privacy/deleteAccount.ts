/** KVKK / Store P0 hesap silme kaskadı (PR-R1). */
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

import { toHttpsError } from "../core/errors.js";
import { log } from "../core/logger.js";
import { buildContext } from "../middleware/context.js";
import {
  deleteAccountCascade,
  type AccountDeletionPorts,
} from "./delete_account_service.js";

/** Üretim portları — Admin SDK Rules'u bypass eder (kaskad için gerekli). */
const productionPorts: AccountDeletionPorts = {
  recursiveDeleteUser: async (uid) => {
    // BulkWriter tabanlı; alt koleksiyonları kendi gezer ve SINIRLI retry
    // uygular (sonsuz döngü yok).
    await getFirestore().recursiveDelete(getFirestore().doc(`users/${uid}`));
  },
  deleteDocument: async (path) => {
    await getFirestore().doc(path).delete(); // yoksa no-op
  },
  deleteAuthUser: async (uid) => {
    await getAuth().deleteUser(uid);
  },
};

export const deleteAccount = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    memory: "512MiB",
    timeoutSeconds: 300,
    maxInstances: 3,
  },
  async (request) => {
    // UID YALNIZ doğrulanmış oturumdan; request.data hiç okunmaz.
    const ctx = buildContext("deleteAccount", request);
    try {
      const result = await deleteAccountCascade(ctx.uid, productionPorts);
      log("info", "account_deleted", ctx, { deleted: true });
      return result;
    } catch (error) {
      throw toHttpsError(error, ctx);
    }
  },
);
