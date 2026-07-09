/**
 * Boru hattı orkestrasyon testleri — AI-ANALIZ-TASARIMI.md §1.2 sırası
 * ve kota adaleti kuralları, tamamı sahte port'larla (emulator'sız).
 */
import { beforeEach, describe, expect, it } from "vitest";

import {
  AnalyzeService,
  SELF_HARM_REDIRECT,
  type AnalysisPorts,
  type StoredAnalysis,
} from "../src/ai/analyze_service";
import { CostCircuitBreaker, type SpendStore } from "../src/ai/cost_control";
import type {
  AiGateway,
  AnalysisCompletion,
  ModerationResult,
} from "../src/ai/openai_gateway";
import { clearPromptVersionCache } from "../src/ai/prompts/registry";
import type { AnalysisOutput } from "../src/ai/schema";
import { AppError } from "../src/core/errors";
import { hashUid } from "../src/core/logger";
import type { RequestContext } from "../src/core/types";

const ctx: RequestContext = {
  fn: "analyzeDecision",
  jobId: "job-1",
  uid: "u1",
  uidHash: hashUid("u1"),
  startedAtMs: Date.now(),
};

const validContent = {
  title: "Telefon seçimi",
  options: [
    { id: "a", title: "iPhone", pros: ["kamera"], cons: ["fiyat"] },
    { id: "b", title: "Samsung", pros: [], cons: [] },
  ],
  criteria: [{ id: "c1", name: "Fiyat", weight: 8 }],
};

const validOutput: AnalysisOutput = {
  summary: "Dengeli bir karşılaştırma.",
  risks: ["Fiyat farkı bütçeyi zorlayabilir"],
  perOption: [
    { optionId: "a", strengths: ["kamera"], weaknesses: ["fiyat"] },
    { optionId: "b", strengths: ["fiyat"], weaknesses: [] },
  ],
  suggestedCriteria: [{ name: "Batarya", defaultWeight: 6 }],
  confidence: "medium",
  confidenceReason: "Kriter sayısı sınırlı.",
};

class FakePorts implements AnalysisPorts {
  content: unknown | null = validContent;
  cached: StoredAnalysis | null = null;
  plan: "free" | "premium" = "free";
  /** null = alan hiç yazılmamış (yeni kullanıcı) → sunucu lazy-init. */
  credits: number | null = null;
  commits = 0;
  jobs: Array<{ status: string; costUsd: number }> = [];

  async readDecisionContent() {
    return this.content;
  }

  async findCachedAnalysis() {
    return this.cached;
  }

  async peekCredits() {
    return {
      plan: this.plan,
      remaining: this.credits ?? 5,
    };
  }

  async commitAnalysis(params: { initialCredits: number }): Promise<string> {
    // Gerçek transaction'ın eşleniği: yeniden doğrula + düş.
    if (this.plan !== "premium") {
      const remaining = this.credits ?? params.initialCredits;
      if (remaining <= 0) {
        throw new AppError("quota-exceeded", "bitti", { remaining: 0 });
      }
      this.credits = remaining - 1;
    }
    this.commits++;
    return `analysis-${this.commits}`;
  }

  async writeJob(job: { status: string; costUsd: number }) {
    this.jobs.push(job);
  }
}

class FakeGateway implements AiGateway {
  moderationResult: ModerationResult = {
    flagged: false,
    selfHarm: false,
    categories: [],
  };
  completions = 0;
  moderations = 0;

  async moderate(): Promise<ModerationResult> {
    this.moderations++;
    return this.moderationResult;
  }

  async completeAnalysis(): Promise<AnalysisCompletion> {
    this.completions++;
    return {
      output: validOutput,
      usage: { inputTokens: 1500, outputTokens: 700 },
      repaired: false,
    };
  }
}

class FakeSpend implements SpendStore {
  total = 0;
  async todayTotal() {
    return this.total;
  }
  async add(_day: string, usd: number) {
    this.total += usd;
  }
}

class FakeRate {
  calls = 0;
  shouldReject = false;
  async check() {
    this.calls++;
    if (this.shouldReject) {
      throw new AppError("rate-limited", "bekle", { retryAfterSeconds: 30 });
    }
  }
}

function make(overrides?: { spendTotal?: number }) {
  const ports = new FakePorts();
  const gateway = new FakeGateway();
  const rate = new FakeRate();
  const spend = new FakeSpend();
  spend.total = overrides?.spendTotal ?? 0;
  const breaker = new CostCircuitBreaker(spend, 50);
  const service = new AnalyzeService(ports, gateway, rate, breaker);
  return { service, ports, gateway, rate, spend };
}

beforeEach(() => clearPromptVersionCache());

const request = { decisionId: "d1", tier: "basic" };

describe("AnalyzeService — mutlu yol", () => {
  it("analizi üretir, commit'ler ve maliyet muhasebesi yazar", async () => {
    const { service, ports, spend } = make();
    const result = await service.run(ctx, request);

    expect(result.cached).toBe(false);
    expect(result.analysis.summary).toBe(validOutput.summary);
    expect(result.analysis.perOption["a"]!.strengths).toEqual(["kamera"]);
    expect(ports.commits).toBe(1);
    expect(ports.credits).toBe(4); // kredi başarıyla birlikte düştü (5→4)
    expect(ports.jobs[0]!.status).toBe("ok");
    expect(ports.jobs[0]!.costUsd).toBeGreaterThan(0);
    expect(spend.total).toBeGreaterThan(0); // devre kesici sayacı beslendi
  });
});

describe("önbellek (§5)", () => {
  it("isabet: rate/kota/LLM hiç çalışmaz, kota yanmaz", async () => {
    const { service, ports, gateway, rate } = make();
    ports.cached = {
      id: "eski-analiz",
      tier: "basic",
      summary: "önbellekten",
      risks: [],
      perOption: {},
      suggestedCriteria: [],
      confidence: "high",
      confidenceReason: "x",
      model: "gpt-4o-mini",
      promptVersion: "v1",
      inputHash: "h",
    };

    const result = await service.run(ctx, request);

    expect(result.cached).toBe(true);
    expect(result.analysisId).toBe("eski-analiz");
    expect(rate.calls).toBe(0); // önbellek rate limit'ten ÖNCE (§1.2)
    expect(gateway.moderations).toBe(0);
    expect(gateway.completions).toBe(0);
    expect(ports.credits, 'kredi yanmadı').toBeNull();
    expect(ports.jobs[0]!.status).toBe("cache_hit");
  });
});

describe("kota adaleti (§1.2 kural)", () => {
  it("free kota dolu → quota-exceeded, LLM çağrılmaz", async () => {
    const { service, ports, gateway } = make();
    ports.credits = 0; // kredisi bitmiş kullanıcı

    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("quota-exceeded");
    expect(gateway.completions).toBe(0);
  });

  it("kredi 1→0: analiz geçer, İKİNCİSİ reddedilir, negatif imkânsız",
    async () => {
      const { service, ports, gateway } = make();
      ports.credits = 1;

      const first = await service.run(ctx, request);
      expect(first.cached).toBe(false);
      expect(ports.credits).toBe(0); // tam sıfır — eksiye geçmedi

      const error = await service
        .run(ctx, { decisionId: "d2", tier: "basic" })
        .catch((e: unknown) => e);
      expect((error as AppError).code).toBe("quota-exceeded");
      expect(ports.credits).toBe(0); // red, değeri DEĞİŞTİRMEDİ
      expect(gateway.completions).toBe(1); // ikinci istek LLM'e gitmedi
    });

  it("yeni kullanıcı (alan yok): lazy-init 5'ten başlar, 4'e düşer",
    async () => {
      const { service, ports } = make();
      expect(ports.credits).toBeNull(); // alan hiç yazılmamış

      await service.run(ctx, request);
      expect(ports.credits).toBe(4); // 5 (örtük) - 1
    });

  it("premium kota sınırından etkilenmez", async () => {
    const { service, ports } = make();
    ports.plan = "premium";
    ports.credits = 0; // premium için anlamsız — bypass beklenir

    const result = await service.run(ctx, { ...request, tier: "advanced" });
    expect(result.cached).toBe(false);
    expect(ports.commits).toBe(1);
  });

  it("moderasyon reddi kota YAKMAZ ve LLM'e gitmez", async () => {
    const { service, ports, gateway } = make();
    gateway.moderationResult = {
      flagged: true,
      selfHarm: false,
      categories: ["violence"],
    };

    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("moderated");
    expect(gateway.completions).toBe(0);
    expect(ports.credits).toBeNull(); // kredi yanmadı
    expect(ports.commits).toBe(0);
  });

  it("kendine zarar: güvenli yönlendirme mesajı döner", async () => {
    const { service, gateway } = make();
    gateway.moderationResult = {
      flagged: true,
      selfHarm: true,
      categories: ["self-harm"],
    };

    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).message).toBe(SELF_HARM_REDIRECT);
    expect((error as AppError).details?.["selfHarm"]).toBe(true);
  });
});

describe("devre kesici (§4.3)", () => {
  it("günlük eşik aşıldı → free tier ai-unavailable", async () => {
    const { service } = make({ spendTotal: 51 });
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["circuitBreaker"]).toBe(true);
  });

  it("premium tier kesiciden etkilenmez", async () => {
    const { service, ports } = make({ spendTotal: 51 });
    ports.plan = "premium";
    const result = await service.run(ctx, { ...request, tier: "advanced" });
    expect(result.cached).toBe(false);
  });
});

describe("girdi doğrulama", () => {
  it("olmayan karar → invalid-argument", async () => {
    const { service, ports } = make();
    ports.content = null;
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");
  });

  it("tek seçenekli karar analiz edilemez (Y-3)", async () => {
    const { service, ports } = make();
    ports.content = { ...validContent, options: [validContent.options[0]] };
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");
  });

  it("bozuk istek payload'ı → invalid-argument", async () => {
    const { service } = make();
    const error = await service
      .run(ctx, { yanlisAlan: true })
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");
  });
});

describe("rate limit sırası", () => {
  it("rate reddi LLM'den önce keser, kota yanmaz", async () => {
    const { service, ports, gateway, rate } = make();
    rate.shouldReject = true;
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("rate-limited");
    expect(gateway.completions).toBe(0);
    expect(ports.credits).toBeNull(); // kredi yanmadı
  });
});
