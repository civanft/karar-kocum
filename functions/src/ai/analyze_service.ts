/**
 * Analiz orkestratörü — AI-ANALIZ-TASARIMI.md §1.2 boru hattının [3]-[11]
 * adımları, birebir sırayla. Tüm dış dünya port'lardan enjekte edilir →
 * emulator'sız birim test edilebilir. Callable yalnız üretim grafiğini kurar.
 *
 * Streaming kararı (§10 açık karar 1): FALLBACK yolu uygulanmıştır —
 * non-stream callable + K-2 canlı Firestore akışı (editör sonucu anında
 * görür). Callable-streaming spike'ı Sprint 3 UI cilasında değerlendirilecek.
 */
import { AppError } from "../core/errors.js";
import { emitMetric, finishRequest, startTimer } from "../core/metrics.js";
import type { RequestContext } from "../core/types.js";
import { computeInputHash } from "./cache.js";
import { FREE_MONTHLY_QUOTA, tierConfig, type Tier } from "./config.js";
import type { CostCircuitBreaker } from "./cost_control.js";
import { computeCostUsd } from "./cost_control.js";
import type { AiGateway } from "./openai_gateway.js";
import { getPrompt, resolveActivePromptVersion } from "./prompts/registry.js";
import {
  analyzeRequestSchema,
  decisionContentSchema,
  toStoredAnalysis,
  type DecisionContent,
} from "./schema.js";

// ---- Port'lar (üretim: Firestore adapter; test: bellek içi sahteler) ----

export interface StoredAnalysis {
  id: string;
  tier: Tier;
  summary: string;
  risks: string[];
  perOption: Record<string, { strengths: string[]; weaknesses: string[] }>;
  suggestedCriteria: Array<{ name: string; defaultWeight: number }>;
  confidence: "low" | "medium" | "high";
  confidenceReason: string;
  model: string;
  promptVersion: string;
  inputHash: string;
}

export interface QuotaSnapshot {
  plan: "free" | "premium";
  month: string;
  used: number;
}

export interface AnalysisPorts {
  /** [3] Kararı SUNUCUDAN oku — istemci payload'ına güven yok. */
  readDecisionContent(decisionId: string): Promise<unknown | null>;
  /** [5] Aynı inputHash'li mevcut analiz. */
  findCachedAnalysis(
    decisionId: string,
    inputHash: string,
  ): Promise<StoredAnalysis | null>;
  /** [6] Kota ön kontrolü (salt okuma — düşüm YOK). */
  peekQuota(currentMonth: string): Promise<QuotaSnapshot>;
  /** [10] Atomik: kota yeniden doğrula + analiz + işaretçi + kota artışı. */
  commitAnalysis(params: {
    decisionId: string;
    analysis: Omit<StoredAnalysis, "id">;
    currentMonth: string;
    freeQuotaLimit: number;
  }): Promise<string>; // analysisId
  /** [11] Maliyet muhasebesi (best-effort). */
  writeJob(job: {
    decisionId: string;
    tier: Tier;
    status: "ok" | "cache_hit";
    model: string;
    promptVersion: string;
    tokensIn: number;
    tokensOut: number;
    costUsd: number;
    durationMs: number;
    repaired: boolean;
  }): Promise<void>;
}

export interface RateGuard {
  check(uid: string): Promise<void>;
}

/** Kendine zarar kategorisi için güvenli yönlendirme (§4.2, PRD R1). */
export const SELF_HARM_REDIRECT =
  "Bu konu bir karar analizinden daha önemli. Zor bir dönemden geçiyorsan " +
  "yalnız değilsin — 182'yi arayabilir ya da güvendiğin birine ulaşabilirsin.";

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
  ): Promise<{ analysisId: string; analysis: StoredAnalysis; cached: boolean }> {
    const stopTotal = startTimer();

    // [4a] istek doğrulama
    const parsedRequest = analyzeRequestSchema.safeParse(rawRequest);
    if (!parsedRequest.success) {
      throw new AppError("invalid-argument", "Geçersiz istek.");
    }
    const { decisionId, tier } = parsedRequest.data;

    // [3] kararı sunucudan oku
    const rawContent = await this.ports.readDecisionContent(decisionId);
    if (rawContent == null) {
      throw new AppError("invalid-argument", "Karar bulunamadı.");
    }

    // [4b] içerik doğrulama (Y-3 limitleri — rules'u aşan istemciye karşı)
    const content = decisionContentSchema.safeParse(rawContent);
    if (!content.success) {
      throw new AppError(
        "invalid-argument",
        "Karar içeriği analiz için uygun değil.",
      );
    }

    // [5] önbellek — isabet: kota/rate HİÇ harcanmaz (§5)
    const promptVersion = await resolveActivePromptVersion(this.now);
    const { model, maxOutputTokens } = tierConfig(tier);
    const inputHash = computeInputHash({
      content: content.data,
      tier,
      promptVersion,
      model,
    });
    const cached = await this.ports.findCachedAnalysis(decisionId, inputHash);
    if (cached) {
      emitMetric(ctx, "ai_cache_hit", 1, { tier });
      await this.safeWriteJob(ctx, {
        decisionId,
        tier,
        status: "cache_hit",
        model,
        promptVersion,
        tokensIn: 0,
        tokensOut: 0,
        costUsd: 0,
        durationMs: stopTotal(),
        repaired: false,
      });
      finishRequest(ctx, "ok", { cached: true });
      return { analysisId: cached.id, analysis: cached, cached: true };
    }

    // [6] rate limit + kota ön kontrolü + devre kesici
    await this.rateGuard.check(ctx.uid);
    const month = currentMonth(this.now);
    const quota = await this.ports.peekQuota(month);
    if (quota.plan === "free" && quota.used >= FREE_MONTHLY_QUOTA) {
      throw new AppError("quota-exceeded", "Aylık analiz hakkın doldu.", {
        limit: FREE_MONTHLY_QUOTA,
      });
    }
    await this.breaker.ensureAllowed(tier);

    // [7] moderasyon — hassas içerik: analiz YOK, kota YANMAZ (§4.2)
    const prompt = getPrompt(promptVersion);
    const userMessage = prompt.buildUserMessage(content.data);
    const moderation = await this.gateway.moderate(userMessage);
    if (moderation.flagged) {
      throw new AppError(
        "moderated",
        moderation.selfHarm
          ? SELF_HARM_REDIRECT
          : "Bu içerik analiz edilemiyor.",
        { selfHarm: moderation.selfHarm },
      );
    }

    // [8]-[9] LLM çağrısı (retry + şema doğrulama + onarım gateway'de)
    const completion = await this.gateway.completeAnalysis({
      model,
      system: prompt.system,
      user: userMessage,
      maxOutputTokens,
    });
    if (completion.repaired) emitMetric(ctx, "ai_schema_failure", 1, { tier });

    // [10] atomik yazım — kota ANCAK burada, başarıyla birlikte düşer
    const analysis: Omit<StoredAnalysis, "id"> = {
      tier,
      ...toStoredAnalysis(completion.output),
      model,
      promptVersion,
      inputHash,
    };
    const analysisId = await this.ports.commitAnalysis({
      decisionId,
      analysis,
      currentMonth: month,
      freeQuotaLimit: FREE_MONTHLY_QUOTA,
    });

    // [11] maliyet muhasebesi + metrikler
    const costUsd = computeCostUsd(model, completion.usage);
    await this.breaker.record(costUsd);
    const durationMs = stopTotal();
    await this.safeWriteJob(ctx, {
      decisionId,
      tier,
      status: "ok",
      model,
      promptVersion,
      tokensIn: completion.usage.inputTokens,
      tokensOut: completion.usage.outputTokens,
      costUsd,
      durationMs,
      repaired: completion.repaired,
    });
    emitMetric(ctx, "ai_cost_usd", costUsd, { tier, model });
    emitMetric(ctx, "ai_latency_total_ms", durationMs, { tier });
    finishRequest(ctx, "ok", { cached: false });

    return { analysisId, analysis: { id: analysisId, ...analysis }, cached: false };
  }

  /** aiJobs yazımı best-effort: muhasebe hatası kullanıcı yanıtını bozmaz. */
  private async safeWriteJob(
    ctx: RequestContext,
    job: Parameters<AnalysisPorts["writeJob"]>[0],
  ): Promise<void> {
    try {
      await this.ports.writeJob(job);
    } catch {
      emitMetric(ctx, "ai_error", 1, { stage: "job_write" });
    }
  }
}

export function currentMonth(now: () => number = Date.now): string {
  return new Date(now()).toISOString().slice(0, 7); // "2026-07"
}

export type { DecisionContent };
