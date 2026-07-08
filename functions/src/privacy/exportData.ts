/** KVKK veri dışa aktarma — Sprint 6; altyapı (App Check+bağlam) bağlı. */
import { onCall } from "firebase-functions/v2/https";

import { AppError, toHttpsError } from "../core/errors.js";
import { buildContext } from "../middleware/context.js";

export const exportData = onCall(
  { enforceAppCheck: true, consumeAppCheckToken: true },
  (request) => {
    const ctx = buildContext("exportData", request);
    throw toHttpsError(
      new AppError(
        "unimplemented",
        "Veri dışa aktarma Sprint 6'da devreye girecek.",
      ),
      ctx,
    );
  },
);
