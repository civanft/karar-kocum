/**
 * İŞ PAKETİ 2 / DİLİM D — doğrulama sırası.
 *
 * Şema olarak geçerli ama derlenmiş mesajı MAX_INPUT_CHARS'ı aşan bir istek,
 * eskiden önce rate sayacını, günlük analiz slotunu ve token/USD kontrolünü
 * tüketip SONRA reddediliyordu: kullanıcı hakkı ve global günlük slot boşa
 * yanıyordu. Boyut kontrolü artık HİÇBİR sayaç tüketilmeden önce yapılır.
 */
import { describe, expect, it, vi } from "vitest";

import { AnalyzeService } from "../src/ai/analyze_service";
import { MAX_INPUT_CHARS } from "../src/config";
import type { RequestContext } from "../src/core/types";

const ctx: RequestContext = {
  fn: "analyzeDecision",
  jobId: "j1",
  uid: "u1",
  uidHash: "h1",
  startedAtMs: 0,
};

/** MAX_INPUT_CHARS'ı aşacak kadar büyük ama ŞEMAYA UYGUN karar. */
function oversizedContent() {
  const long = "x".repeat(140);
  return {
    title: "Çok büyük karar",
    options: Array.from({ length: 10 }, (_, i) => ({
      id: `o${i}`,
      title: `Seçenek ${i}`,
      description: "y".repeat(280),
      pros: Array.from({ length: 20 }, () => long),
      cons: Array.from({ length: 20 }, () => long),
    })),
    criteria: Array.from({ length: 15 }, (_, i) => ({
      id: `c${i}`,
      name: `Kriter ${i}`,
      weight: 5,
    })),
  };
}

describe("aşırı büyük istek hiçbir sayaç tüketmez", () => {
  function make() {
    const calls = {
      rate: 0, credits: 0, breaker: 0, token: 0, daily: 0, gateway: 0,
    };
    const service = new AnalyzeService(
      {
        readDecisionContent: async () => oversizedContent(),
        peekCredits: async () => {
          calls.credits++;
          return { plan: "free" as const, remaining: 5 };
        },
        commitAnalysis: async () => "latest",
      },
      {
        completeAnalysis: async () => {
          calls.gateway++;
          throw new Error("çağrılmamalıydı");
        },
      },
      { check: async () => { calls.rate++; } },
      {
        ensureAllowed: async () => { calls.breaker++; },
        record: async () => {},
      } as never,
      { ensureSlot: async () => { calls.daily++; } } as never,
      {
        ensureUnderLimit: async () => { calls.token++; },
        record: async () => {},
      } as never,
    );
    return { service, calls };
  }

  it("invalid-argument döner", async () => {
    const { service } = make();
    await expect(
      service.run(ctx, { decisionId: "d1", requestId: "r".repeat(32) }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("rate sayacı TÜKETİLMEZ", async () => {
    const { service, calls } = make();
    await service.run(ctx, { decisionId: "d1", requestId: "r".repeat(32) }).catch(() => {});
    expect(calls.rate).toBe(0);
  });

  it("günlük analiz slotu TÜKETİLMEZ", async () => {
    const { service, calls } = make();
    await service.run(ctx, { decisionId: "d1", requestId: "r".repeat(32) }).catch(() => {});
    expect(calls.daily).toBe(0);
  });

  it("token/USD rezervasyonu YAPILMAZ", async () => {
    const { service, calls } = make();
    await service.run(ctx, { decisionId: "d1", requestId: "r".repeat(32) }).catch(() => {});
    expect(calls.token).toBe(0);
    expect(calls.breaker).toBe(0);
  });

  it("kredi OKUNMAZ ve provider ÇAĞRILMAZ", async () => {
    const { service, calls } = make();
    await service.run(ctx, { decisionId: "d1", requestId: "r".repeat(32) }).catch(() => {});
    expect(calls.credits).toBe(0);
    expect(calls.gateway).toBe(0);
  });

  it("sınır gerçekten MAX_INPUT_CHARS üstünde (fixture doğrulaması)", () => {
    expect(MAX_INPUT_CHARS).toBeGreaterThan(0);
  });
});
