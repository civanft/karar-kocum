/**
 * İŞ PAKETİ 2 / DİLİM C — OpenAI SDK hata taksonomisi.
 *
 * Resmî SDK davranışı (openai 6.49.0):
 *  - README §Retries: SDK yalnız connection hatası, 408, 409, 429 ve >=500
 *    durumlarını retry eder.
 *  - lib/parser.js: `.parse()` finish_reason 'length' → LengthFinishReasonError,
 *    'content_filter' → ContentFilterFinishReasonError FIRLATIR; bu sınıflar
 *    OpenAIError'dan türer, APIError DEĞİLDİR ve `status` TAŞIMAZ.
 *
 * Eski sınıflandırıcı "status yoksa ağ hatasıdır" varsaydığı için moderasyon
 * ve length hatalarını yeniden deniyordu: ikinci bir ücretli provider çağrısı
 * ve yanlış kullanıcı hatası.
 */
import {
  APIConnectionError,
  APIConnectionTimeoutError,
  APIError,
  ContentFilterFinishReasonError,
  InternalServerError,
  LengthFinishReasonError,
  RateLimitError,
} from "openai/core/error";
import { describe, expect, it } from "vitest";

import { classifyProviderError, ProviderErrorKind } from "../src/ai/openai_errors";

function apiError(status: number): APIError {
  return new APIError(status, { message: "x" }, "x", undefined);
}

describe("provider hata sınıflandırması", () => {
  it("content filter → moderated, retry EDİLMEZ", () => {
    const c = classifyProviderError(new ContentFilterFinishReasonError());
    expect(c.kind).toBe(ProviderErrorKind.moderated);
    expect(c.retryable).toBe(false);
  });

  it("length → çıktı üretim hatası, retry EDİLMEZ", () => {
    const c = classifyProviderError(new LengthFinishReasonError());
    expect(c.kind).toBe(ProviderErrorKind.outputTruncated);
    expect(c.retryable).toBe(false);
  });

  it("status'suz olmaları retryable saymaya YETMEZ (eski hata)", () => {
    for (const e of [
      new ContentFilterFinishReasonError(),
      new LengthFinishReasonError(),
    ]) {
      expect((e as { status?: unknown }).status).toBeUndefined();
      expect(classifyProviderError(e).retryable).toBe(false);
    }
  });

  it("429 → retryable", () => {
    const c = classifyProviderError(
      new RateLimitError(429, { message: "x" }, "x", undefined),
    );
    expect(c.kind).toBe(ProviderErrorKind.rateLimited);
    expect(c.retryable).toBe(true);
  });

  it("5xx → retryable", () => {
    const c = classifyProviderError(
      new InternalServerError(503, { message: "x" }, "x", undefined),
    );
    expect(c.kind).toBe(ProviderErrorKind.serverError);
    expect(c.retryable).toBe(true);
  });

  it("408/409 resmî SDK retry kümesinde → retryable", () => {
    for (const s of [408, 409]) {
      expect(classifyProviderError(apiError(s)).retryable).toBe(true);
    }
  });

  it("bağlantı ve timeout hataları → transport, retryable", () => {
    for (const e of [
      new APIConnectionError({ message: "net" }),
      new APIConnectionTimeoutError({ message: "timeout" }),
    ]) {
      const c = classifyProviderError(e);
      expect(c.kind).toBe(ProviderErrorKind.transport);
      expect(c.retryable).toBe(true);
    }
  });

  it("400/401/403/422 → kalıcı istek hatası, retry EDİLMEZ", () => {
    for (const s of [400, 401, 403, 422]) {
      expect(classifyProviderError(apiError(s)).retryable).toBe(false);
    }
  });

  it("BİLİNMEYEN programlama hatası transport SAYILMAZ", () => {
    const c = classifyProviderError(new TypeError("x.y is not a function"));
    expect(c.kind).toBe(ProviderErrorKind.unknown);
    expect(c.retryable).toBe(false);
  });

  it("refusal → açık eşleme, retry EDİLMEZ", () => {
    const c = classifyProviderError({ __refusal: "I can't help with that" });
    expect(c.kind).toBe(ProviderErrorKind.refused);
    expect(c.retryable).toBe(false);
  });

  it("schema/parse hatası → açık eşleme, retry EDİLMEZ", () => {
    const c = classifyProviderError({ __schemaFailure: true });
    expect(c.kind).toBe(ProviderErrorKind.schemaFailure);
    expect(c.retryable).toBe(false);
  });

  it("sınıflandırma ham mesaj/secret taşımaz", () => {
    const c = classifyProviderError(
      new APIError(400, { message: "sk-SECRET-LEAK" }, "sk-SECRET-LEAK", undefined),
    );
    expect(JSON.stringify(c)).not.toContain("SECRET");
  });
});
