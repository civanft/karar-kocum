/**
 * analyzeDecision callable — üretim grafiği + hata eşleme (PR #6C-3).
 * Akış AnalyzeService'te; yanıt {analysisId, analysis} — istemci anında
 * render eder, kalıcılık aiAnalyses/latest + K-2 canlı akışıyla.
 */
import { onCall } from "firebase-functions/v2/https";

import { functionRegion } from "../core/deployment.js";

import { AppError, toHttpsError } from "../core/errors.js";
import { log } from "../core/logger.js";
import { openaiApiKey } from "../core/secrets.js";
import type { RequestContext } from "../core/types.js";
import {
  buildContext,
  contextlessLogContext,
} from "../middleware/context.js";
import {
  FirestoreRateLimitStore,
  RateLimiter,
} from "../quota/rate_limiter.js";
import { PER_USER_ANALYZE_LIMITS } from "../config.js";
import { AnalyzeService } from "./analyze_service.js";
import { CostCircuitBreaker, FirestoreSpendStore } from "./cost_control.js";
import {
  DailyAnalysisLimiter,
  FirestoreDailyCounterStore,
} from "./daily_limit.js";
import { FirestoreAnalysisPorts } from "./firestore_ports.js";
import { createOpenAIClient, OpenAIGateway } from "./openai_gateway.js";
import {
  DailyTokenGuard,
  FirestoreTokenCounterStore,
} from "./token_counter.js";

export const analyzeDecision = onCall(
  {
    region: functionRegion,
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    secrets: [openaiApiKey],
    memory: "512MiB",
    timeoutSeconds: 60,
    concurrency: 20,
    maxInstances: 10, // global maliyet freni (6B)
  },
  async (request) => {
    let ctx: RequestContext | undefined;
    try {
      ctx = buildContext("analyzeDecision", request);
      const service = new AnalyzeService(
        new FirestoreAnalysisPorts(ctx.uid),
        new OpenAIGateway(createOpenAIClient(openaiApiKey.value())),
        new RateLimiter(new FirestoreRateLimitStore(), PER_USER_ANALYZE_LIMITS),
        new CostCircuitBreaker(new FirestoreSpendStore()),
        new DailyAnalysisLimiter(new FirestoreDailyCounterStore()),
        new DailyTokenGuard(new FirestoreTokenCounterStore()),
      );
      return await service.run(ctx, request.data);
    } catch (error) {
      const logCtx = ctx ?? contextlessLogContext("analyzeDecision");
      if (error instanceof AppError) {
        log("warn", "analysis_failed", logCtx, { errorCode: error.code });
      }
      throw toHttpsError(error, logCtx);
    }
  },
);
