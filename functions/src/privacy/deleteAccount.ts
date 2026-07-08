/** KVKK hesap silme kaskadı — Sprint 6; altyapı (App Check+bağlam) bağlı. */
import { onCall } from "firebase-functions/v2/https";

import { AppError, toHttpsError } from "../core/errors.js";
import { buildContext } from "../middleware/context.js";

export const deleteAccount = onCall(
  { enforceAppCheck: true, consumeAppCheckToken: true },
  (request) => {
    const ctx = buildContext("deleteAccount", request);
    throw toHttpsError(
      new AppError("unimplemented", "Hesap silme Sprint 6'da devreye girecek."),
      ctx,
    );
  },
);
