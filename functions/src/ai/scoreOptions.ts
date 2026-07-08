/** AI otomatik puanlama (premium) — PR #3: altyapı bağlı, LLM PR #4/5. */
import { onCall } from "firebase-functions/v2/https";

import { AppError, toHttpsError } from "../core/errors.js";
import { finishRequest } from "../core/metrics.js";
import { openaiApiKey } from "../core/secrets.js";
import { buildContext } from "../middleware/context.js";
import {
  DEFAULT_ANALYZE_LIMITS,
  FirestoreRateLimitStore,
  RateLimiter,
} from "../quota/rate_limiter.js";

const limiter = () =>
  new RateLimiter(new FirestoreRateLimitStore(), DEFAULT_ANALYZE_LIMITS);

export const scoreOptions = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    secrets: [openaiApiKey],
    memory: "512MiB",
    timeoutSeconds: 60,
    concurrency: 20,
  },
  async (request) => {
    const ctx = buildContext("scoreOptions", request);
    try {
      await limiter().check(ctx.uid);
      throw new AppError(
        "unimplemented",
        "AI puanlama henüz devrede değil (PR #4/5).",
      );
    } catch (error) {
      finishRequest(ctx, "error");
      throw toHttpsError(error, ctx);
    }
  },
);
