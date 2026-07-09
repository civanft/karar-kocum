/**
 * Gemini gateway testleri — 6C-1 §5 hata eşleme tablosunun kanıtı.
 * SDK sahtelenir (GeminiClientLike); ağ yok.
 */
import type { GenerateContentResult } from "@google/generative-ai";
import { describe, expect, it } from "vitest";

import {
  GeminiGateway,
  SELF_HARM_REDIRECT,
  type GeminiClientLike,
} from "../src/ai/gemini_gateway";
import { AppError } from "../src/core/errors";

const noSleep = async () => {};

const validJson = JSON.stringify({
  summary: "Özet",
  strengths: ["a"],
  weaknesses: [],
  risks: [],
  recommendation: "Veriler A'yı gösteriyor.",
  confidence: "low",
});

type FakeResponse = Partial<{
  text: string | null;
  finishReason: string;
  blockReason: string;
  dangerous: boolean;
  usage: { promptTokenCount: number; candidatesTokenCount: number };
}>;

function response(spec: FakeResponse): GenerateContentResult {
  const safetyRatings = spec.dangerous
    ? [{ category: "HARM_CATEGORY_DANGEROUS_CONTENT", probability: "HIGH" }]
    : [{ category: "HARM_CATEGORY_HARASSMENT", probability: "HIGH" }];
  return {
    response: {
      promptFeedback: spec.blockReason
        ? { blockReason: spec.blockReason, safetyRatings }
        : undefined,
      candidates: spec.blockReason
        ? undefined
        : [
            {
              finishReason: spec.finishReason ?? "STOP",
              safetyRatings,
              content:
                spec.text === null
                  ? undefined
                  : { parts: [{ text: spec.text ?? validJson }] },
            },
          ],
      usageMetadata: spec.usage ?? {
        promptTokenCount: 1500,
        candidatesTokenCount: 600,
      },
    },
  } as unknown as GenerateContentResult;
}

/** Sırayla yanıt/istisna döndüren sahte istemci. */
function client(
  outcomes: Array<GenerateContentResult | Error>,
): GeminiClientLike & { calls: number } {
  let i = 0;
  const fake = {
    calls: 0,
    async generateContent() {
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
  model: "gemini-2.0-flash",
  maxOutputTokens: 800,
};

describe("başarı yolu", () => {
  it("geçerli JSON + token kullanımı döner", async () => {
    const c = client([response({})]);
    const result = await new GeminiGateway(c, noSleep).completeAnalysis(
      params,
    );
    expect(result.output.summary).toBe("Özet");
    expect(result.output.confidence).toBe("low");
    expect(result.usage).toEqual({ inputTokens: 1500, outputTokens: 600 });
    expect(c.calls).toBe(1);
  });
});

describe("retry (6B tek kural: 1 deneme)", () => {
  it("429 → 1 yeniden deneme sonrası başarı", async () => {
    const c = client([httpError(429), response({})]);
    const result = await new GeminiGateway(c, noSleep).completeAnalysis(
      params,
    );
    expect(result.output.summary).toBe("Özet");
    expect(c.calls).toBe(2);
  });

  it("iki kez 503 → ai-unavailable (retryable), 2 çağrıda durur", async () => {
    const c = client([httpError(503), httpError(503), httpError(503)]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["retryable"]).toBe(true);
    expect(c.calls).toBe(2);
  });

  it("RECITATION → 1 yeniden deneme; tekrarında ai-unavailable", async () => {
    const c = client([
      response({ finishReason: "RECITATION", text: null }),
      response({ finishReason: "RECITATION", text: null }),
    ]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("ai-unavailable");
    expect(c.calls).toBe(2);
  });
});

describe("moderasyon eşlemesi (6C-1 §5)", () => {
  it("girdi bloğu (promptFeedback) → moderated", async () => {
    const c = client([response({ blockReason: "SAFETY" })]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("moderated");
    expect((error as AppError).details?.["selfHarm"]).toBe(false);
  });

  it("DANGEROUS_CONTENT bloğu → güvenli yönlendirme mesajı (182)", async () => {
    const c = client([response({ blockReason: "SAFETY", dangerous: true })]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).message).toBe(SELF_HARM_REDIRECT);
    expect((error as AppError).details?.["selfHarm"]).toBe(true);
  });

  it("çıktı bloğu (finishReason SAFETY) → moderated", async () => {
    const c = client([response({ finishReason: "SAFETY", text: null })]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("moderated");
  });
});

describe("bozuk yanıtlar", () => {
  it("MAX_TOKENS kesmesi → internal + schemaFailure", async () => {
    const c = client([
      response({ finishReason: "MAX_TOKENS", text: '{"summary": "yarım' }),
    ]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("internal");
    expect((error as AppError).details?.["schemaFailure"]).toBe(true);
  });

  it("şemaya uymayan JSON → internal + schemaFailure", async () => {
    const c = client([response({ text: '{"summary": 42}' })]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("internal");
    expect((error as AppError).details?.["schemaFailure"]).toBe(true);
  });

  it("boş candidates → internal", async () => {
    const c = client([response({ text: null })]);
    const error = await new GeminiGateway(c, noSleep)
      .completeAnalysis(params)
      .catch((e: unknown) => e);
    expect((error as AppError).code).toBe("internal");
  });
});
