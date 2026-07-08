import { HttpsError } from "firebase-functions/v2/https";
import { describe, expect, it } from "vitest";

import { AppError, toHttpsError } from "../src/core/errors";
import { hashUid, sanitizeFields } from "../src/core/logger";
import type { RequestContext } from "../src/core/types";

const ctx: RequestContext = {
  fn: "test",
  jobId: "job-1",
  uid: "user-123",
  uidHash: hashUid("user-123"),
  startedAtMs: Date.now(),
};

describe("toHttpsError", () => {
  it("AppError kodları doğru HttpsError kodlarına eşlenir", () => {
    const cases: Array<[AppError, string]> = [
      [new AppError("rate-limited", "x"), "resource-exhausted"],
      [new AppError("quota-exceeded", "x"), "resource-exhausted"],
      [new AppError("moderated", "x"), "failed-precondition"],
      [new AppError("ai-unavailable", "x"), "unavailable"],
      [new AppError("unimplemented", "x"), "unimplemented"],
      [new AppError("unauthenticated", "x"), "unauthenticated"],
    ];
    for (const [error, expected] of cases) {
      expect(toHttpsError(error, ctx).code).toBe(expected);
    }
  });

  it("details istemciye taşınır (retryAfterSeconds)", () => {
    const e = toHttpsError(
      new AppError("rate-limited", "bekle", { retryAfterSeconds: 42 }),
      ctx,
    );
    expect(e.details).toMatchObject({
      appCode: "rate-limited",
      retryAfterSeconds: 42,
    });
  });

  it("bilinmeyen hata: iç mesaj istemciye SIZMAZ", () => {
    const e = toHttpsError(
      new Error("OPENAI_API_KEY sk-abc123 ile bağlantı hatası"),
      ctx,
    );
    expect(e.code).toBe("internal");
    expect(e.message).not.toContain("sk-abc123");
    expect(e.message).toBe("Beklenmeyen bir hata oluştu.");
  });

  it("zaten HttpsError ise dokunulmaz", () => {
    const original = new HttpsError("not-found", "yok");
    expect(toHttpsError(original, ctx)).toBe(original);
  });
});

describe("logger hijyeni", () => {
  it("hashUid: deterministik, 12 karakter, ham uid içermez", () => {
    const h = hashUid("cok-gizli-uid");
    expect(h).toHaveLength(12);
    expect(h).toBe(hashUid("cok-gizli-uid"));
    expect(h).not.toContain("gizli");
  });

  it("sanitizeFields: içerik ve ham uid alanlarını ayıklar", () => {
    const clean = sanitizeFields({
      uid: "ham-uid",
      title: "Karar başlığı",
      prompt: "gizli prompt",
      tokensIn: 1500,
      tier: "basic",
    });
    expect(clean).toEqual({ tokensIn: 1500, tier: "basic" });
  });
});
