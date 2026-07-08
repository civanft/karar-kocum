import OpenAI, { APIError } from "openai";
import { describe, expect, it } from "vitest";

import {
  classifyOpenAiError,
  OpenAiGateway,
  withRetries,
} from "../src/ai/openai_gateway";
import { AppError } from "../src/core/errors";

const noSleep = async () => {};
const noJitter = () => 0;

function apiError(status: number): APIError {
  return new APIError(status, undefined, `hata ${status}`, undefined);
}

describe("classifyOpenAiError", () => {
  it("429 → rate, 5xx → server, 4xx → client, ağ → server", () => {
    expect(classifyOpenAiError(apiError(429))).toBe("rate");
    expect(classifyOpenAiError(apiError(500))).toBe("server");
    expect(classifyOpenAiError(apiError(400))).toBe("client");
    expect(classifyOpenAiError(new Error("timeout"))).toBe("server");
  });
});

describe("withRetries (§8 politikası)", () => {
  it("429: 2 yeniden deneme sonrası başarı", async () => {
    let calls = 0;
    const result = await withRetries(
      async () => {
        calls++;
        if (calls <= 2) throw apiError(429);
        return "ok";
      },
      noSleep,
      noJitter,
    );
    expect(result).toBe("ok");
    expect(calls).toBe(3);
  });

  it("429: 3. denemede de hata → ai-unavailable(retryable)", async () => {
    let calls = 0;
    const error = await withRetries(
      async () => {
        calls++;
        throw apiError(429);
      },
      noSleep,
      noJitter,
    ).catch((e: unknown) => e);
    expect(calls).toBe(3); // 1 asıl + 2 retry
    expect((error as AppError).code).toBe("ai-unavailable");
    expect((error as AppError).details?.["retryable"]).toBe(true);
  });

  it("5xx: yalnız 1 yeniden deneme", async () => {
    let calls = 0;
    await withRetries(
      async () => {
        calls++;
        throw apiError(503);
      },
      noSleep,
      noJitter,
    ).catch(() => undefined);
    expect(calls).toBe(2);
  });

  it("4xx (client): deneme YOK, retryable=false", async () => {
    let calls = 0;
    const error = await withRetries(
      async () => {
        calls++;
        throw apiError(400);
      },
      noSleep,
      noJitter,
    ).catch((e: unknown) => e);
    expect(calls).toBe(1);
    expect((error as AppError).details?.["retryable"]).toBe(false);
  });
});

// ---- Structured output + onarım denemesi ----

const validJson = JSON.stringify({
  summary: "Özet",
  risks: [],
  perOption: [{ optionId: "a", strengths: [], weaknesses: [] }],
  suggestedCriteria: [],
  confidence: "low",
  confidenceReason: "Az veri",
});

function fakeClient(responses: Array<string | null>): OpenAI {
  let i = 0;
  return {
    chat: {
      completions: {
        create: async () => {
          const content = responses[i++];
          return {
            choices: [{ message: { content } }],
            usage: { prompt_tokens: 100, completion_tokens: 50 },
          };
        },
      },
    },
    moderations: {
      create: async () => ({ results: [{ flagged: false, categories: {} }] }),
    },
  } as unknown as OpenAI;
}

const params = {
  model: "gpt-4o-mini",
  system: "sys",
  user: "veri",
  maxOutputTokens: 900,
};

describe("OpenAiGateway.completeAnalysis", () => {
  it("geçerli yanıt ilk denemede döner", async () => {
    const gw = new OpenAiGateway("test-key", noSleep, fakeClient([validJson]));
    const result = await gw.completeAnalysis(params);
    expect(result.repaired).toBe(false);
    expect(result.output.summary).toBe("Özet");
    expect(result.usage).toEqual({ inputTokens: 100, outputTokens: 50 });
  });

  it("bozuk yanıt → 1 onarım denemesi, token'lar toplanır", async () => {
    const gw = new OpenAiGateway(
      "test-key",
      noSleep,
      fakeClient(["{bozuk json", validJson]),
    );
    const result = await gw.completeAnalysis(params);
    expect(result.repaired).toBe(true);
    expect(result.usage).toEqual({ inputTokens: 200, outputTokens: 100 });
  });

  it("onarım da bozuksa → internal + schemaFailure", async () => {
    const gw = new OpenAiGateway(
      "test-key",
      noSleep,
      fakeClient(["{bozuk", '{"summary": 42}']),
    );
    const error = await gw.completeAnalysis(params).catch((e: unknown) => e);
    expect((error as AppError).code).toBe("internal");
    expect((error as AppError).details?.["schemaFailure"]).toBe(true);
  });
});
