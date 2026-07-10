/**
 * Sadeleştirilmiş boru hattı testleri (6C-3): doğrulama → rate/kredi/
 * kesici sırası → Gemini → tek commit. Kota adaleti invariant'ları
 * (6C-2) korunur: hata/moderasyon/rate reddi kredi YAKMAZ.
 */
import { describe, expect, it } from "vitest";

import {
  AnalyzeService,
  LATEST_ANALYSIS_ID,
  type AnalysisPorts,
  type StoredAnalysis,
} from "../src/ai/analyze_service";
import { CostCircuitBreaker, type SpendStore } from "../src/ai/cost_control";
import {
  DailyAnalysisLimiter,
  type DailyCounterStore,
} from "../src/ai/daily_limit";
import {
  SELF_HARM_REDIRECT,
  type AiGateway,
  type AnalysisCompletion,
} from "../src/ai/gemini_gateway";
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
  strengths: ["Kriterler tutarlı"],
  weaknesses: ["Yaşam maliyeti düşük tartılmış"],
  risks: ["Kira artışı varsayımı"],
  recommendation: "Veriler iPhone seçeneğini gösteriyor.",
  confidence: "medium",
};

class FakePorts implements AnalysisPorts {
  content: unknown | null = validContent;
  plan: "free" | "premium" = "free";
  /** null = alan hiç yazılmamış (yeni kullanıcı) → sunucu lazy-init. */
  credits: number | null = null;
  commits = 0;
  lastAnalysis: StoredAnalysis | null = null;

  async readDecisionContent() {
    return this.content;
  }

  async peekCredits() {
    return { plan: this.plan, remaining: this.credits ?? 5 };
  }

  async commitAnalysis(params: {
    analysis: StoredAnalysis;
    initialCredits: number;
  }): Promise<string> {
    if (this.plan !== "premium") {
      const remaining = this.credits ?? params.initialCredits;
      if (remaining <= 0) {
        throw new AppError("quota-exceeded", "bitti", { remaining: 0 });
      }
      this.credits = remaining - 1;
    }
    this.commits++;
    this.lastAnalysis = params.analysis;
    return LATEST_ANALYSIS_ID;
  }
}

class FakeGateway implements AiGateway {
  completions = 0;
  failWith: AppError | null = null;

  async completeAnalysis(): Promise<AnalysisCompletion> {
    if (this.failWith) throw this.failWith;
    this.completions++;
    return {
      output: validOutput,
      usage: { inputTokens: 1500, outputTokens: 600 },
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

class MemoryCounter implements DailyCounterStore {
  counts = new Map<string, number>();
  async reserve(dayKey: string, limit: number): Promise<boolean> {
    const current = this.counts.get(dayKey) ?? 0;
    if (current >= limit) return false;
    this.counts.set(dayKey, current + 1);
    return true;
  }
  get total(): number {
    return [...this.counts.values()].reduce((a, b) => a + b, 0);
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

function make(overrides?: { spendTotal?: number; dailyLimit?: number }) {
  const ports = new FakePorts();
  const gateway = new FakeGateway();
  const rate = new FakeRate();
  const spend = new FakeSpend();
  const counter = new MemoryCounter();
  spend.total = overrides?.spendTotal ?? 0;
  const breaker = new CostCircuitBreaker(spend, 0.35);
  const daily = new DailyAnalysisLimiter(counter, overrides?.dailyLimit ?? 50);
  const service = new AnalyzeService(ports, gateway, rate, breaker, daily);
  return { service, ports, gateway, rate, spend, counter };
}

const request = { decisionId: "d1" };

describe("mutlu yol", () => {
  it("analiz üretir, latest'e commit'ler, kredi 5→4, maliyet kaydedilir", async () => {
    const { service, ports, spend } = make();
    const result = await service.run(ctx, request);

    expect(result.analysisId).toBe(LATEST_ANALYSIS_ID);
    expect(result.analysis.summary).toBe(validOutput.summary);
    expect(result.analysis.recommendation).toContain("iPhone");
    expect(result.analysis.model).toBe("gemini-2.0-flash");
    expect(result.analysis.promptVersion).toBe("mvp-1");
    expect(ports.commits).toBe(1);
    expect(ports.credits).toBe(4); // lazy-init 5 → 4
    expect(spend.total).toBeGreaterThan(0);
    // Maliyet hedefi (6C-1 §7): analiz başına < $0,001
    expect(spend.total).toBeLessThan(0.001);
  });

  it("yeniden analiz aynı kimliğe yazar (üzerine yazma — geçmiş yok)", async () => {
    const { service, ports } = make();
    const first = await service.run(ctx, request);
    const second = await service.run(ctx, request);
    expect(first.analysisId).toBe(second.analysisId);
    expect(ports.commits).toBe(2);
    expect(ports.credits).toBe(3); // her analiz 1 kredi (cache yok — 6B)
  });
});

describe("kredi adaleti (6C-2 invariant'ları)", () => {
  it("kredi 0 → quota-exceeded, Gemini hiç çağrılmaz", async () => {
    const { service, ports, gateway } = make();
    ports.credits = 0;
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("quota-exceeded");
    expect(gateway.completions).toBe(0);
  });

  it("kredi 1→0: geçer; ikincisi reddedilir; negatif imkânsız", async () => {
    const { service, ports, gateway } = make();
    ports.credits = 1;

    await service.run(ctx, request);
    expect(ports.credits).toBe(0);

    const error = await service
      .run(ctx, { decisionId: "d2" })
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("quota-exceeded");
    expect(ports.credits).toBe(0); // değişmedi
    expect(gateway.completions).toBe(1);
  });

  it("Gemini moderasyon bloğu kredi YAKMAZ", async () => {
    const { service, ports, gateway } = make();
    gateway.failWith = new AppError("moderated", SELF_HARM_REDIRECT, {
      selfHarm: true,
    });

    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("moderated");
    expect((error as AppError).message).toBe(SELF_HARM_REDIRECT);
    expect(ports.credits).toBeNull(); // kredi yanmadı
    expect(ports.commits).toBe(0);
  });

  it("Gemini kesintisi (ai-unavailable) kredi YAKMAZ", async () => {
    const { service, ports, gateway } = make();
    gateway.failWith = new AppError("ai-unavailable", "kesinti", {
      retryable: true,
    });
    await service.run(ctx, request).catch(() => undefined);
    expect(ports.credits).toBeNull();
    expect(ports.commits).toBe(0);
  });

  it("premium: kredi sınırı ve kesici bypass", async () => {
    const { service, ports } = make({ spendTotal: 1 }); // kesici eşik üstü
    ports.plan = "premium";
    ports.credits = 0;
    const result = await service.run(ctx, request);
    expect(result.analysisId).toBe(LATEST_ANALYSIS_ID);
  });
});

describe("koruma sırası", () => {
  it("rate reddi Gemini'den önce keser", async () => {
    const { service, ports, gateway, rate } = make();
    rate.shouldReject = true;
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("rate-limited");
    expect(gateway.completions).toBe(0);
    expect(ports.credits).toBeNull();
  });

  it("7B: günlük ADET limiti dolunca doğru mesaj, kredi YANMAZ", async () => {
    const { service, ports, gateway } = make({ dailyLimit: 1 });

    await service.run(ctx, request); // slot 1/1
    const error = await service
      .run(ctx, { decisionId: "d2" })
      .catch((e: unknown) => e);

    expect((error as AppError).code).toBe("daily-limit");
    expect((error as AppError).message).toContain(
      "Bugünkü analiz limiti doldu",
    );
    expect(gateway.completions).toBe(1); // ikinci istek Gemini'ye gitmedi
    expect(ports.credits).toBe(4); // yalnız ilk analiz kredi düşürdü
  });

  it("7B: başarılı analiz global sayacı 1 artırır", async () => {
    const { service, counter } = make();
    await service.run(ctx, request);
    expect(counter.total).toBe(1);
  });

  it("günlük tavan aşımı: free kullanıcı ai-unavailable", async () => {
    const { service } = make({ spendTotal: 0.36 }); // > $0,35
    const error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["circuitBreaker"]).toBe(true);
  });
});

describe("girdi doğrulama", () => {
  it("olmayan karar / bozuk istek / tek seçenek → invalid-argument", async () => {
    const { service, ports } = make();

    ports.content = null;
    let error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");

    ports.content = validContent;
    error = await service.run(ctx, { yanlis: 1 }).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");

    ports.content = { ...validContent, options: [validContent.options[0]] };
    error = await service.run(ctx, request).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("invalid-argument");
  });
});
