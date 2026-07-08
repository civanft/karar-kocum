/**
 * AI analiz proxy'si — boru hattı iskeleti (AI-ANALIZ-TASARIMI.md §1.2).
 * PR #3 kapsamı: [1] App Check (runtime) → [2] auth/bağlam → [6-rate] limit.
 * OpenAI çağrısı, moderasyon, kota ve Firestore yazımı PR #4'te —
 * o güne dek son adım kontrollü 'unimplemented' hatasıdır (kota yanmaz).
 */
import { onCall } from "firebase-functions/v2/https";

import { AppError, toHttpsError } from "../core/errors.js";
import { emitMetric, finishRequest } from "../core/metrics.js";
import { openaiApiKey } from "../core/secrets.js";
import { buildContext } from "../middleware/context.js";
import {
  DEFAULT_ANALYZE_LIMITS,
  FirestoreRateLimitStore,
  RateLimiter,
} from "../quota/rate_limiter.js";

const limiter = () =>
  new RateLimiter(new FirestoreRateLimitStore(), DEFAULT_ANALYZE_LIMITS);

export const analyzeDecision = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true, // replay koruması (§4.1)
    secrets: [openaiApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
    concurrency: 20,
    maxInstances: 30, // global maliyet freni (§1.1)
  },
  async (request) => {
    const ctx = buildContext("analyzeDecision", request);
    try {
      await limiter().check(ctx.uid);
      throw new AppError(
        "unimplemented",
        "AI analizi henüz devrede değil (PR #4).",
      );
    } catch (error) {
      if (error instanceof AppError && error.code === "rate-limited") {
        emitMetric(ctx, "rate_limit_rejection", 1);
      }
      finishRequest(ctx, "error");
      throw toHttpsError(error, ctx);
    }
  },
);
