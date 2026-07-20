/**
 * OpenAI gateway testleri — hata eşleme tablosunun kanıtı (Gemini'den
 * migrasyon). SDK sahtelenir (OpenAIClientLike); ağ yok.
 */
import { describe, expect, it } from "vitest";

import {
  OpenAIGateway,
  type OpenAIClientLike,
} from "../src/ai/openai_gateway";
import type { AnalysisOutput } from "../src/ai/schema";
import { AppError } from "../src/core/errors";

const noSleep = async () => {};

const validOutput: AnalysisOutput = {
  summary: "Özet",
  strengths: ["a"],
  weaknesses: [],
  risks: [],
  recommendation: "Veriler A'yı gösteriyor.",
  confidence: "low",
};

type Completion = Awaited<ReturnType<OpenAIClientLike["complete"]>>;

function completion(spec: Partial<Completion>): Completion {
  return {
    parsed: spec.parsed !== undefined ? spec.parsed : validOutput,
    finishReason: spec.finishReason ?? "stop",
    usage: spec.usage ?? { inputTokens: 1500, outputTokens: 600 },
  };
}

/** Sırayla yanıt/istisna döndüren sahte istemci. */
function client(
  outcomes: Array<Completion | Error>,
): OpenAIClientLike & { calls: number } {
  let i = 0;
  const fake = {
    calls: 0,
    async complete() {
      fake.calls++;
      const outcome = outcomes[Math.min(i++, outcomes.length - 1)]!;
      if (outcome instanceof Error) throw outcome;
      return outcome;
    },
  };
  return fake;
}

function httpError(status: number): Error {
  const error = new Error(`hata ${status}`);
  (error as unknown as { status: number }).status = status;
  return error;
}

const params = {
  system: "sys",
  user: "veri",
  model: "gpt-4.1-mini",
  maxOutputTokens: 800,
};

describe("başarı yolu", () => {
  it("yapılandırılmış çıktı + token kullanımı döner", async () => {
    const c = client([completion({})]);
    const result = await new OpenAIGateway(c, noSleep).completeAnalysis(params);
    expect(result.output.summary).toBe("Özet");
    expect(result.output.confidence).toBe("low");
    expect(result.usage).toEqual({ inputTokens: 1500, outputTokens: 600 });
    expect(c.calls).toBe(1);
  });
});

describe("retry (tek deneme)", () => {
  it("429 → 1 yeniden deneme sonrası başarı", async () => {
    const c = client([httpError(429), completion({})]);
    const result = await new OpenAIGateway(c, noSleep).completeAnalysis(params);
    expect(result.output.summary).toBe("Özet");
    expect(c.calls).toBe(2);
  });

  it("iki kez 503 → ai-unavailable (retryable), 2 çağrıda durur", async () => {
    const c = client([httpError(503), httpError(503), httpError(503)]);
    const error = await new OpenAIGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["retryable"]).toBe(true);
    expect(c.calls).toBe(2);
  });

  it("timeout (status'suz hata) → retryable, tek deneme sonrası durur", async () => {
    const c = client([new Error("timeout"), new Error("timeout")]);
    const error = await new OpenAIGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["retryable"]).toBe(true);
    expect(c.calls).toBe(2); // OPENAI_MAX_RETRIES = 1
  });
});

describe("moderasyon eşlemesi", () => {
  it("finish_reason content_filter → moderated", async () => {
    const c = client([
      completion({ finishReason: "content_filter", parsed: null }),
    ]);
    const error = await new OpenAIGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("moderated");
    expect((error as AppError).details?.["selfHarm"]).toBe(false);
  });
});

describe("bozuk yanıtlar", () => {
  it("finish_reason length (token kesmesi) → internal + schemaFailure", async () => {
    const c = client([completion({ finishReason: "length", parsed: null })]);
    const error = await new OpenAIGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("internal");
    expect((error as AppError).details?.["schemaFailure"]).toBe(true);
  });

  it("parse edilemeyen (parsed null) → internal + schemaFailure", async () => {
    const c = client([completion({ parsed: null })]);
    const error = await new OpenAIGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("internal");
    expect((error as AppError).details?.["schemaFailure"]).toBe(true);
  });
});
