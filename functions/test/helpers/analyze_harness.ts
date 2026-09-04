/**
 * İş Paketi 2 test koşumu — journal'lı AnalyzeService için paylaşılan
 * sahteler. Gerçek Firestore implementasyonuyla AYNI sözleşmeyi taşır:
 * geçiş kapıları, create-if-absent rezervasyon, fingerprint doğrulaması.
 */
import {
  canTransition,
  JournalState,
} from "../../src/ai/analysis_journal";
import {
  AnalyzeService,
  LATEST_ANALYSIS_ID,
  type AnalysisPorts,
  type JournalRecord,
  type StoredAnalysis,
} from "../../src/ai/analyze_service";
import { CostCircuitBreaker } from "../../src/ai/cost_control";
import { DailyAnalysisLimiter } from "../../src/ai/daily_limit";
import { DailyTokenGuard } from "../../src/ai/token_counter";
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

export class HarnessPorts implements AnalysisPorts {
  content: unknown | null = validContent;
  plan: "free" | "premium" = "free";
  credits: number | null = null;
  commits = 0;
  lastAnalysis: StoredAnalysis | null = null;
  fingerprintOverride: string | null = null;
  failOn: { recordProviderSuccess?: boolean; finalize?: boolean } = {};
  readonly journal = new Map<string, JournalRecord>();

  async readDecisionContent() {
    return this.content;
  }
  async peekCredits() {
    return { plan: this.plan, remaining: this.credits ?? 5 };
  }
  async readJournal(requestId: string) {
    return this.journal.get(requestId) ?? null;
  }
  async reserve(p: {
    requestId: string;
    decisionId: string;
    contentFingerprint: string;
  }) {
    const existing = this.journal.get(p.requestId);
    if (existing) return { created: false, record: existing };
    const record: JournalRecord = {
      state: JournalState.reserved,
      decisionId: p.decisionId,
      contentFingerprint: p.contentFingerprint,
    };
    this.journal.set(p.requestId, record);
    return { created: true, record };
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
  async markOutcome(p: { requestId: string; state: JournalState }) {
    const r = this.journal.get(p.requestId);
    if (!r || !canTransition(r.state, p.state)) return;
    r.state = p.state;
  }
  async finalize(p: {
    requestId: string;
    expectedFingerprint: string;
    analysis: StoredAnalysis;
    initialCredits: number;
  }): Promise<{ outcome: "completed" | "superseded"; analysisId: string }> {
    if (this.failOn.finalize) {
      this.failOn.finalize = false;
      throw new Error("finalize başarısız (enjekte)");
    }
    const r = this.journal.get(p.requestId);
    if (!r) throw new AppError("internal", "journal yok");
    if (r.state === JournalState.completed) {
      return { outcome: "completed", analysisId: LATEST_ANALYSIS_ID };
    }
    if (r.state === JournalState.superseded) {
      return { outcome: "superseded", analysisId: LATEST_ANALYSIS_ID };
    }
    if (this.fingerprintOverride !== null) {
      r.state = JournalState.superseded;
      return { outcome: "superseded", analysisId: LATEST_ANALYSIS_ID };
    }
    if (this.plan !== "premium") {
      const remaining = this.credits ?? p.initialCredits;
      if (remaining <= 0) {
        throw new AppError("quota-exceeded", "bitti", { remaining: 0 });
      }
      this.credits = remaining - 1;
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
    return { output: validOutput, usage: { inputTokens: 1500, outputTokens: 600 } };
  }
}

export interface Harness {
  service: AnalyzeService;
  ports: HarnessPorts;
  gateway: HarnessGateway;
  rate: { checks: number };
  daily: { slots: number };
  tokens: { records: number };
  spend: { records: number };
}

export function buildService(): Harness {
  const ports = new HarnessPorts();
  const gateway = new HarnessGateway();
  const rate = { checks: 0 };
  const daily = { slots: 0 };
  const tokens = { records: 0 };
  const spend = { records: 0 };

  const breaker = new CostCircuitBreaker({
    todayTotal: async () => 0,
    add: async () => {
      spend.records++;
    },
  });
  const dailyLimiter = new DailyAnalysisLimiter({
    reserve: async () => {
      daily.slots++;
      return true;
    },
  });
  const tokenGuard = new DailyTokenGuard({
    todayTotal: async () => 0,
    add: async () => {
      tokens.records++;
    },
  });

  const service = new AnalyzeService(
    ports,
    gateway,
    {
      check: async () => {
        rate.checks++;
      },
    },
    breaker,
    dailyLimiter,
    tokenGuard,
  );
  return { service, ports, gateway, rate, daily, tokens, spend };
}
