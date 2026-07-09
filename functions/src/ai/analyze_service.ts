/**
 * Analiz orkestratörü — SADELEŞTİRİLMİŞ MVP akışı (6B + 6C-1 + 6C-2):
 * doğrula → oku → rate/kredi/kesici → Gemini → tek transaction → yanıt.
 * Kaldırılanlar: cache, prompt registry, metrik modülü, aiJobs, tier.
 * Kota adaleti KORUNDU: kredi yalnız başarılı commit'te düşer.
 */
import { AppError } from "../core/errors.js";
import { log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";
import {
  GEMINI_MODEL,
  INITIAL_FREE_CREDITS,
  MAX_OUTPUT_TOKENS,
} from "./config.js";
import type { CostCircuitBreaker } from "./cost_control.js";
import { computeCostUsd } from "./cost_control.js";
import type { AiGateway } from "./gemini_gateway.js";
import { buildUserMessage, PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt.js";
import {
  analyzeRequestSchema,
  decisionContentSchema,
  type AnalysisOutput,
} from "./schema.js";

/** aiAnalyses altında SABİT belge kimliği — geçmiş yok, üzerine yazılır. */
export const LATEST_ANALYSIS_ID = "latest";

export interface StoredAnalysis extends AnalysisOutput {
  model: string;
  promptVersion: string;
}

export interface CreditsSnapshot {
  plan: "free" | "premium";
  /** Kalan kredi; alan hiç yazılmamışsa BAŞLANGIÇ (5) kabul edilir. */
  remaining: number;
}

export interface AnalysisPorts {
  /** Kararı SUNUCUDAN oku — istemci payload'ına güven yok. */
  readDecisionContent(decisionId: string): Promise<unknown | null>;
  peekCredits(): Promise<CreditsSnapshot>;
  /**
   * Atomik: krediyi yeniden doğrula + aiAnalyses/latest + status
   * TEK transaction'da. remaining > 0 şartıyla düşüm → negatif imkânsız.
   */
  commitAnalysis(params: {
    decisionId: string;
    analysis: StoredAnalysis;
    initialCredits: number;
  }): Promise<string>; // analysisId ('latest')
}

export interface RateGuard {
  check(uid: string): Promise<void>;
}

export class AnalyzeService {
  constructor(
    private readonly ports: AnalysisPorts,
    private readonly gateway: AiGateway,
    private readonly rateGuard: RateGuard,
    private readonly breaker: CostCircuitBreaker,
    private readonly now: () => number = Date.now,
  ) {}

  async run(
    ctx: RequestContext,
    rawRequest: unknown,
  ): Promise<{ analysisId: string; analysis: StoredAnalysis }> {
    const startedMs = this.now();

    // [1-2] istek + içerik doğrulama (auth callable katmanında yapıldı)
    const request = analyzeRequestSchema.safeParse(rawRequest);
    if (!request.success) {
      throw new AppError("invalid-argument", "Geçersiz istek.");
    }
    const { decisionId } = request.data;

    const rawContent = await this.ports.readDecisionContent(decisionId);
    if (rawContent == null) {
      throw new AppError("invalid-argument", "Karar bulunamadı.");
    }
    const content = decisionContentSchema.safeParse(rawContent);
    if (!content.success) {
      throw new AppError(
        "invalid-argument",
        "Karar içeriği analiz için uygun değil.",
      );
    }

    // [3] rate limit + kredi ön kontrolü + günlük maliyet kesici
    await this.rateGuard.check(ctx.uid);
    const credits = await this.ports.peekCredits();
    if (credits.plan === "free" && credits.remaining <= 0) {
      throw new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
        remaining: 0,
        initial: INITIAL_FREE_CREDITS,
      });
    }
    await this.breaker.ensureAllowed(credits.plan);

    // [4] Gemini — moderasyon üretim çağrısına gömülü (6C-1 §2);
    // moderated/unavailable hataları burada fırlar, kredi YANMAZ.
    const completion = await this.gateway.completeAnalysis({
      system: SYSTEM_PROMPT,
      user: buildUserMessage(content.data),
      model: GEMINI_MODEL,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
    });

    // [5] tek transaction: kredi ANCAK burada, başarıyla birlikte düşer
    const analysis: StoredAnalysis = {
      ...completion.output,
      model: GEMINI_MODEL,
      promptVersion: PROMPT_VERSION,
    };
    const analysisId = await this.ports.commitAnalysis({
      decisionId,
      analysis,
      initialCredits: INITIAL_FREE_CREDITS,
    });

    // [6] maliyet kaydı + tek satır kapanış logu (metrik modülü yok — 6B)
    const costUsd = computeCostUsd(GEMINI_MODEL, completion.usage);
    await this.breaker.record(costUsd);
    log("info", "analysis_completed", ctx, {
      model: GEMINI_MODEL,
      promptVersion: PROMPT_VERSION,
      tokensIn: completion.usage.inputTokens,
      tokensOut: completion.usage.outputTokens,
      costUsd,
      durationMs: this.now() - startedMs,
    });

    return { analysisId, analysis };
  }
}
