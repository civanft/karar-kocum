/**
 * İŞ PAKETİ 2 / DİLİM C-2 — gateway retry sözleşmesi.
 *
 * Provider tarafında BELGELENMİŞ bir idempotency garantisi YOKTUR. Bu yüzden
 * aynı application requestId içinde, isteğin sağlayıcıya ULAŞMIŞ OLABİLECEĞİ
 * hiçbir hata otomatik olarak yeniden denenmez (ikinci ÜCRETLİ çağrı riski).
 * Yalnız 429 — sağlayıcının isteği İŞLEMEDEN reddettiği durum — yeniden
 * denenebilir.
 */
import {
  APIConnectionTimeoutError,
  ContentFilterFinishReasonError,
  InternalServerError,
  LengthFinishReasonError,
  RateLimitError,
} from "openai/core/error";
import { describe, expect, it, vi } from "vitest";

import { AppError } from "../src/core/errors";
import { OpenAIGateway, type OpenAIClientLike } from "../src/ai/openai_gateway";

const params = { system: "s", user: "u", model: "m", maxOutputTokens: 100 };

function gatewayWith(complete: OpenAIClientLike["complete"]) {
  return new OpenAIGateway({ complete }, async () => {});
}

describe("gateway retry sözleşmesi", () => {
  it("content filter TEK denemede moderated döner", async () => {
    const spy = vi.fn(async () => {
      throw new ContentFilterFinishReasonError();
    });
    const gw = gatewayWith(spy);
    await expect(gw.completeAnalysis(params)).rejects.toMatchObject({
      code: "moderated",
    });
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("length TEK denemede non-retryable üretim hatası döner", async () => {
    const spy = vi.fn(async () => {
      throw new LengthFinishReasonError();
    });
    const gw = gatewayWith(spy);
    await expect(gw.completeAnalysis(params)).rejects.toBeInstanceOf(AppError);
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("timeout/transport OTOMATİK yeniden DENENMEZ (belirsiz pencere)", async () => {
    const spy = vi.fn(async () => {
      throw new APIConnectionTimeoutError({ message: "t" });
    });
    const gw = gatewayWith(spy);
    await expect(gw.completeAnalysis(params)).rejects.toMatchObject({
      code: "ai-uncertain",
    });
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("5xx OTOMATİK yeniden DENENMEZ (belirsiz pencere)", async () => {
    const spy = vi.fn(async () => {
      throw new InternalServerError(503, { message: "x" }, "x", undefined);
    });
    const gw = gatewayWith(spy);
    await expect(gw.completeAnalysis(params)).rejects.toMatchObject({
      code: "ai-uncertain",
    });
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("429 yeniden denenebilir: sağlayıcı isteği İŞLEMEDEN reddetti", async () => {
    let n = 0;
    const spy = vi.fn(async () => {
      if (++n === 1) throw new RateLimitError(429, { message: "x" }, "x", undefined);
      return {
        parsed: {
          summary: "s", strengths: [], weaknesses: [], risks: [],
          recommendation: "r", confidence: "low" as const,
        },
        finishReason: "stop",
        usage: { inputTokens: 1, outputTokens: 1 },
      };
    });
    const gw = gatewayWith(spy);
    const res = await gw.completeAnalysis(params);
    expect(res.output.summary).toBe("s");
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it("bilinmeyen programlama hatası retry EDİLMEZ", async () => {
    const spy = vi.fn(async () => {
      throw new TypeError("x.y is not a function");
    });
    const gw = gatewayWith(spy);
    await expect(gw.completeAnalysis(params)).rejects.toBeInstanceOf(AppError);
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("refusal açık hata verir, retry EDİLMEZ", async () => {
    const spy = vi.fn(async () => ({
      parsed: null,
      refusal: "I can't help with that",
      finishReason: "stop",
      usage: { inputTokens: 1, outputTokens: 1 },
    }));
    const gw = gatewayWith(spy as unknown as OpenAIClientLike["complete"]);
    await expect(gw.completeAnalysis(params)).rejects.toBeInstanceOf(AppError);
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it("hata detayları ham sağlayıcı mesajı/secret taşımaz", async () => {
    const gw = gatewayWith(async () => {
      throw new InternalServerError(
        500, { message: "sk-LEAKED" }, "sk-LEAKED", undefined,
      );
    });
    try {
      await gw.completeAnalysis(params);
    } catch (e) {
      expect(JSON.stringify(e)).not.toContain("LEAKED");
    }
  });
});
