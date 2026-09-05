/**
 * İş Paketi 2B test koşumu — AnalyzeService için paylaşılan sahteler.
 *
 * [HarnessPorts] üretim adaptörüyle AYNI sözleşmeyi taşır:
 *  - kabul kontrolü + TÜM rezervasyonlar tek atomik adımda (reserve),
 *  - journal create-if-absent idempotency kapısı,
 *  - kredi + spend + token muhasebesi finalize'ın İÇİNDE,
 *  - terminal başarısızlıkta rezervasyon kapanışı (settleFailure).
 *
 * Gerçek Firestore transaction semantiği yalnız emulator testleriyle
 * kanıtlanır; burada kanıtlanan şey SÖZLEŞMEDİR.
 */
import { canTransition, JournalState } from "../../src/ai/analysis_journal";
import {
  AnalyzeService,
  LATEST_ANALYSIS_ID,
  type AnalysisPorts,
  type JournalRecord,
  type ReserveOutcome,
  type StoredAnalysis,
} from "../../src/ai/analyze_service";
import type { UsageEstimate } from "../../src/ai/usage_estimate";
import type { AiGateway, AnalysisCompletion } from "../../src/ai/openai_gateway";
import type { AnalysisOutput } from "../../src/ai/schema";
import { AppError } from "../../src/core/errors";
import { hashUid } from "../../src/core/logger";
import type { RequestContext } from "../../src/core/types";

export const ctx: RequestContext = {
  fn: "analyzeDecision",
  jobId: "job-1",
  uid: "u1",
  uidHash: hashUid("u1"),
  startedAtMs: Date.now(),
};

/** Kanonik 24 karakterlik requestId üretir (şema ile uyumlu). */
export const reqId = (seed: string) => seed.repeat(24).slice(0, 24);

export const validContent = {
  title: "Telefon seçimi",
  options: [
    { id: "a", title: "iPhone", pros: ["kamera"], cons: ["fiyat"] },
    { id: "b", title: "Samsung", pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Fiyat", weight: 8 }],
};

export const validOutput: AnalysisOutput = {
  summary: "Dengeli bir karşılaştırma.",
  strengths: ["Kriterler tutarlı"],
  weaknesses: ["Zayıf yön"],
  risks: ["Risk"],
  recommendation: "iPhone.",
  confidence: "medium",
};

/** Sayaç + hata enjeksiyonu: muhasebe yazımının çökmesini taklit eder. */
export interface Counter {
  /** Kaç kez GERÇEK tüketim yazıldı. */
  records: number;
  /** Toplam gerçek tüketim. */
  total: number;
  /** Bir sonraki yazımı çökert. */
  failNext: boolean;
}

export interface HarnessLimits {
  dailyAnalyses: number;
  dailyTokens: number;
  dailyUsd: number;
}

const newCounter = (): Counter => ({ records: 0, total: 0, failNext: false });

export class HarnessPorts implements AnalysisPorts {
  content: unknown | null = validContent;
  plan: "free" | "premium" = "free";
  /** null = alan hiç yazılmamış (yeni kullanıcı) → sunucu lazy-init. */
  credits: number | null = null;
  commits = 0;
  lastAnalysis: StoredAnalysis | null = null;
  /** Finalize sırasında karar değişmiş gibi davran (superseded testi). */
  fingerprintOverride: string | null = null;
  failOn: { recordProviderSuccess?: boolean; finalize?: boolean } = {};
  readonly journal = new Map<string, JournalRecord>();

  /** Kabul kontrolünü rate ile reddettir. */
  rateReject = false;

  /** Rezerve edilmiş (henüz kesinleşmemiş) miktarlar. */
  reserved = { credits: 0, tokens: 0, usd: 0 };

  constructor(
    readonly limits: HarnessLimits,
    private readonly counters: {
      rate: { checks: number };
      daily: { slots: number; total: number };
      tokens: Counter;
      spend: Counter;
    },
  ) {}

  async readDecisionContent() {
    return this.content;
  }

  async readJournal(requestId: string) {
    return this.journal.get(requestId) ?? null;
  }

  /** Kabul + rezervasyon: üretimdeki tek transaction'ın bellek içi ikizi. */
  async reserve(p: {
    requestId: string;
    decisionId: string;
    contentFingerprint: string;
    estimate: UsageEstimate;
  }): Promise<ReserveOutcome> {
    // IDEMPOTENCY KAPISI — kayıt varsa HİÇBİR sayaç artmaz.
    const existing = this.journal.get(p.requestId);
    if (existing) return { status: "existing", record: existing };

    if (this.rateReject) {
      return {
        status: "rejected",
        error: new AppError("rate-limited", "bekle", { retryAfterSeconds: 30 }),
      };
    }

    const free = this.plan === "premium";
    const available = (this.credits ?? 5) - this.reserved.credits;
    if (!free && available <= 0) {
      return {
        status: "rejected",
        error: new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
          remaining: 0,
          initial: 5,
        }),
      };
    }
    if (this.counters.daily.total >= this.limits.dailyAnalyses) {
      return {
        status: "rejected",
        error: new AppError("daily-limit", "Bugünkü analiz limiti doldu.", {
          dailyLimit: this.limits.dailyAnalyses,
        }),
      };
    }
    if (
      this.counters.tokens.total + this.reserved.tokens + p.estimate.tokens >
      this.limits.dailyTokens
    ) {
      return {
        status: "rejected",
        error: new AppError("daily-limit", "Bugünkü analiz limiti doldu.", {
          dailyTokenLimit: this.limits.dailyTokens,
        }),
      };
    }
    if (
      !free &&
      this.counters.spend.total + this.reserved.usd + p.estimate.usd >
        this.limits.dailyUsd
    ) {
      return {
        status: "rejected",
        error: new AppError("ai-unavailable", "AI analizi yoğunlukta.", {
          circuitBreaker: true,
        }),
      };
    }

    const record: JournalRecord = {
      state: JournalState.reserved,
      decisionId: p.decisionId,
      contentFingerprint: p.contentFingerprint,
    };
    this.journal.set(p.requestId, record);
    this.counters.rate.checks++;
    this.counters.daily.slots++;
    this.counters.daily.total++;
    this.reserved.tokens += p.estimate.tokens;
    this.reserved.usd += p.estimate.usd;
    if (!free) this.reserved.credits++;
    return { status: "created", record };
  }

  async markProviderCallStarted(requestId: string) {
    const r = this.journal.get(requestId);
    if (!r || !canTransition(r.state, JournalState.providerCallStarted)) {
      return false;
    }
    r.state = JournalState.providerCallStarted;
    return true;
  }

  async recordProviderSuccess(p: {
    requestId: string;
    analysis: StoredAnalysis;
    usage: { inputTokens: number; outputTokens: number };
  }) {
    if (this.failOn.recordProviderSuccess) {
      this.failOn.recordProviderSuccess = false;
      throw new Error("journal yazımı başarısız (enjekte)");
    }
    const r = this.journal.get(p.requestId);
    if (!r || !canTransition(r.state, JournalState.providerSucceeded)) return;
    r.state = JournalState.providerSucceeded;
    r.analysis = p.analysis;
    r.usage = p.usage;
  }

  /** Rezervasyonu kapatır; `actual` verilirse gerçek tüketimi yazar. */
  private release(
    estimate: UsageEstimate,
    actual: { tokens: number; usd: number } | null,
  ): void {
    if (this.counters.spend.failNext) {
      this.counters.spend.failNext = false;
      throw new Error("spend yazımı başarısız (enjekte)");
    }
    if (this.counters.tokens.failNext) {
      this.counters.tokens.failNext = false;
      throw new Error("token yazımı başarısız (enjekte)");
    }
    this.reserved.tokens -= estimate.tokens;
    this.reserved.usd -= estimate.usd;
    if (this.plan !== "premium") this.reserved.credits--;
    if (actual) {
      this.counters.spend.records++;
      this.counters.spend.total += actual.usd;
      this.counters.tokens.records++;
      this.counters.tokens.total += actual.tokens;
    }
  }

  async settleFailure(p: {
    requestId: string;
    state: JournalState;
    estimate: UsageEstimate;
    billed: boolean;
  }) {
    const r = this.journal.get(p.requestId);
    if (!r || !canTransition(r.state, p.state)) return;
    r.state = p.state;
    this.release(
      p.estimate,
      // Sağlayıcıya çağrı yapıldıysa ücretlendirilmiş olabiliriz.
      p.billed ? { tokens: p.estimate.tokens, usd: p.estimate.usd } : null,
    );
  }

  async finalize(p: {
    requestId: string;
    expectedFingerprint: string;
    analysis: StoredAnalysis;
    initialCredits: number;
    usage: { inputTokens: number; outputTokens: number };
    costUsd: number;
    estimate: UsageEstimate;
  }): Promise<{ outcome: "completed" | "superseded"; analysisId: string }> {
    if (this.failOn.finalize) {
      this.failOn.finalize = false;
      throw new Error("finalize başarısız (enjekte)");
    }
    const r = this.journal.get(p.requestId);
    if (!r) throw new AppError("internal", "journal yok");

    // Terminal durumlar: HİÇBİR muhasebe tekrar uygulanmaz.
    if (r.state === JournalState.completed) {
      return { outcome: "completed", analysisId: LATEST_ANALYSIS_ID };
    }
    if (r.state === JournalState.superseded) {
      return { outcome: "superseded", analysisId: LATEST_ANALYSIS_ID };
    }

    const actual = {
      tokens: p.usage.inputTokens + p.usage.outputTokens,
      usd: p.costUsd,
    };

    if (this.fingerprintOverride !== null) {
      // Kredi YANMAZ ama gerçek maliyet kaydedilir.
      this.release(p.estimate, actual);
      r.state = JournalState.superseded;
      return { outcome: "superseded", analysisId: LATEST_ANALYSIS_ID };
    }

    if (this.plan !== "premium") {
      const remaining = this.credits ?? p.initialCredits;
      if (remaining <= 0) {
        throw new AppError("quota-exceeded", "bitti", { remaining: 0 });
      }
      this.release(p.estimate, actual);
      this.credits = remaining - 1;
    } else {
      this.release(p.estimate, actual);
    }
    this.commits++;
    this.lastAnalysis = p.analysis;
    r.state = JournalState.completed;
    return { outcome: "completed", analysisId: LATEST_ANALYSIS_ID };
  }
}

export class HarnessGateway implements AiGateway {
  completions = 0;
  attempts = 0;
  failWith: AppError | null = null;
  delayMs = 0;

  async completeAnalysis(): Promise<AnalysisCompletion> {
    this.attempts++;
    if (this.delayMs) {
      await new Promise((r) => setTimeout(r, this.delayMs));
    }
    if (this.failWith) throw this.failWith;
    this.completions++;
    return {
      output: validOutput,
      usage: { inputTokens: 1500, outputTokens: 600 },
    };
  }
}

export interface Harness {
  service: AnalyzeService;
  ports: HarnessPorts;
  gateway: HarnessGateway;
  rate: { checks: number };
  daily: { slots: number; total: number };
  tokens: Counter;
  spend: Counter;
}

export function buildService(overrides?: {
  limits?: Partial<HarnessLimits>;
  spendTotal?: number;
  tokenTotal?: number;
  dailyTotal?: number;
}): Harness {
  const rate = { checks: 0 };
  const daily = { slots: 0, total: overrides?.dailyTotal ?? 0 };
  const tokens = newCounter();
  const spend = newCounter();
  tokens.total = overrides?.tokenTotal ?? 0;
  spend.total = overrides?.spendTotal ?? 0;

  const limits: HarnessLimits = {
    dailyAnalyses: 20,
    dailyTokens: 375_000,
    dailyUsd: 0.15,
    ...overrides?.limits,
  };
  const ports = new HarnessPorts(limits, { rate, daily, tokens, spend });
  const gateway = new HarnessGateway();
  const service = new AnalyzeService(ports, gateway);
  return { service, ports, gateway, rate, daily, tokens, spend };
}
