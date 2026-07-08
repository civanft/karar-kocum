/** Eksik kriter önerisi — PR #3: altyapı bağlı, LLM çağrısı PR #4. */
import { onCall } from "firebase-functions/v2/https";

import { AppError, toHttpsError } from "../core/errors.js";
import { finishRequest } from "../core/metrics.js";
import { openaiApiKey } from "../core/secrets.js";
import { buildContext } from "../middleware/context.js";
import {
  DEFAULT_SUGGEST_LIMITS,
  FirestoreRateLimitStore,
  RateLimiter,
} from "../quota/rate_limiter.js";

const limiter = () =>
  new RateLimiter(new FirestoreRateLimitStore(), DEFAULT_SUGGEST_LIMITS);

export const suggestCriteria = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    secrets: [openaiApiKey],
    memory: "256MiB",
    timeoutSeconds: 60,
    concurrency: 20,
  },
  async (request) => {
    const ctx = buildContext("suggestCriteria", request);
    try {
      await limiter().check(ctx.uid);
      throw new AppError(
        "unimplemented",
        "Kriter önerisi henüz devrede değil (PR #4).",
      );
    } catch (error) {
      finishRequest(ctx, "error");
      throw toHttpsError(error, ctx);
    }
  },
);
