import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { afterEach, describe, expect, it, vi } from "vitest";

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

afterEach(() => {
  vi.restoreAllMocks();
});

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

  it("bilinmeyen hata: ham mesaj ve stack sunucu loguna SIZMAZ", () => {
    const sentinel = "private-user-id-at-users-secret-path";
    const written: unknown[] = [];
    vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      written.push(args);
    });

    const cause = Object.assign(
      new Error(`Firestore failed at users/${sentinel}/decisions/private`),
      { code: "permission-denied" },
    );
    toHttpsError(cause, ctx);

    const serialized = JSON.stringify(written);
    expect(serialized).not.toContain(sentinel);
    expect(serialized).not.toContain("Firestore failed");
    expect(serialized).not.toContain("stack");
    expect(written).toHaveLength(1);
    expect(written[0]).toEqual([
      "request_failed_unexpected",
      expect.objectContaining({
        errorCode: "permission-denied",
        errorType: "Error",
      }),
    ]);
  });

  it("güvensiz errorCode 'unknown'a düşer, teşhis alanları sızdırmaz", () => {
    const written: unknown[][] = [];
    vi.spyOn(logger, "error").mockImplementation((...args: unknown[]) => {
      written.push(args);
    });

    // Kod alanına yol / nesne / aşırı uzun değer düşerse ASLA geçmemeli.
    const unsafeCodes: unknown[] = [
      "users/gizli-uid/decisions/private", // '/' izinli değil
      { nested: "obj" }, // string değil
      "x".repeat(65), // 64 karakterden uzun
      undefined, // kod alanı yok
    ];

    for (const code of unsafeCodes) {
      toHttpsError(Object.assign(new Error("upstream detay"), { code }), ctx);
    }

    expect(written).toHaveLength(unsafeCodes.length);
    for (const [event, payload] of written) {
      expect(event).toBe("request_failed_unexpected");
      expect(payload).toMatchObject({ errorCode: "unknown" });
    }
    const serialized = JSON.stringify(written);
    expect(serialized).not.toContain("gizli-uid");
    expect(serialized).not.toContain("upstream detay");
  });

  it("güvenli errorCode korunur ve uidHash log'da kalır", () => {
    const written: Record<string, unknown>[] = [];
    vi.spyOn(logger, "error").mockImplementation(
      (_event: unknown, payload?: unknown) => {
        written.push(payload as Record<string, unknown>);
      },
    );

    toHttpsError(
      Object.assign(new Error("upstream"), { code: "deadline-exceeded" }),
      ctx,
    );

    expect(written[0]).toMatchObject({
      errorCode: "deadline-exceeded",
      errorType: "Error",
    });
    // Güvenli tanımlayıcı korunur, ham uid ASLA görünmez.
    expect(written[0]).toHaveProperty("uidHash");
    expect(JSON.stringify(written[0])).not.toContain(ctx.uid);
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
