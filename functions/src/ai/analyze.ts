/**
 * AI analiz callable'ı — üretim grafiği kurulumu + hata eşleme.
 * Boru hattının kendisi AnalyzeService'te (test edilebilir, §1.2 sırası).
 * Yanıt: tam analiz (non-stream fallback, §10.1) — K-2 canlı akışı
 * sayesinde editör Firestore yazımını zaten anında görür.
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
import { AnalyzeService } from "./analyze_service.js";
import {
  CostCircuitBreaker,
  FirestoreSpendStore,
} from "./cost_control.js";
import { FirestoreAnalysisPorts } from "./firestore_ports.js";
import { OpenAiGateway } from "./openai_gateway.js";

export const analyzeDecision = onCall(
  {
    enforceAppCheck: true,
    consumeAppCheckToken: true,
    secrets: [openaiApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
    concurrency: 20,
    maxInstances: 30,
  },
  async (request) => {
    const ctx = buildContext("analyzeDecision", request);
    try {
      const service = new AnalyzeService(
        new FirestoreAnalysisPorts(ctx.uid),
        new OpenAiGateway(openaiApiKey.value()),
        new RateLimiter(new FirestoreRateLimitStore(), DEFAULT_ANALYZE_LIMITS),
        new CostCircuitBreaker(new FirestoreSpendStore()),
      );
      return await service.run(ctx, request.data);
    } catch (error) {
      if (error instanceof AppError) {
        emitMetric(ctx, "ai_error", 1, { code: error.code });
        if (error.code === "rate-limited") {
          emitMetric(ctx, "rate_limit_rejection", 1);
        }
      }
      finishRequest(ctx, "error");
      throw toHttpsError(error, ctx);
    }
  },
);
