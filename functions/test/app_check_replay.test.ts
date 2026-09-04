/**
 * İŞ PAKETİ 2 / DİLİM A — tüketilmiş App Check token'ı (replay) reddi.
 *
 * `consumeAppCheckToken: true` limited-use token'ı TÜKETİR ama isteği
 * ENGELLEMEZ: tekrar kullanılan token'da `request.app.alreadyConsumed`
 * true gelir ve handler yine çalışır. Bu, bir saldırganın yakaladığı
 * token'ı tekrar oynatarak yan etki üretmesine izin verirdi.
 */
import { describe, expect, it, vi } from "vitest";

import { AppError } from "../src/core/errors";
import { buildContext } from "../src/middleware/context";

type Req = Parameters<typeof buildContext>[1];

function req(overrides: Record<string, unknown> = {}): Req {
  return {
    auth: { uid: "u1", token: { firebase: { sign_in_provider: "anonymous" } } },
    app: { appId: "app", token: {}, alreadyConsumed: false },
    data: {},
    rawRequest: {},
    ...overrides,
  } as unknown as Req;
}

describe("App Check replay reddi", () => {
  it("alreadyConsumed=true → AppError ile reddedilir", () => {
    expect(() =>
      buildContext("analyzeDecision", req({
        app: { appId: "app", token: {}, alreadyConsumed: true },
      })),
    ).toThrow(AppError);
  });

  it("reddedilen replay kararlı bir appCode taşır", () => {
    try {
      buildContext("analyzeDecision", req({
        app: { appId: "app", token: {}, alreadyConsumed: true },
      }));
      expect.unreachable("reddedilmeliydi");
    } catch (error) {
      expect(error).toBeInstanceOf(AppError);
      const e = error as AppError;
      expect(e.code).toBe("app-check-replay");
      // Kullanıcıya teknik ayrıntı/secret sızmaz.
      expect(e.message).not.toMatch(/token|App Check|consumed/i);
    }
  });

  it("red HİÇBİR yan etki oluşmadan, bağlam kurulmadan gerçekleşir", () => {
    const logged: unknown[] = [];
    // request_started logu bile atılmamalı: red her şeyden ÖNCE.
    const spy = vi.spyOn(console, "log").mockImplementation((...a) => {
      logged.push(a);
    });
    try {
      buildContext("analyzeDecision", req({
        app: { appId: "app", token: {}, alreadyConsumed: true },
      }));
    } catch {
      // beklenen
    }
    spy.mockRestore();
    expect(logged).toHaveLength(0);
  });

  it("tüketilmemiş token mevcut davranışı korur", () => {
    const ctx = buildContext("analyzeDecision", req());
    expect(ctx.uid).toBe("u1");
    expect(ctx.fn).toBe("analyzeDecision");
    expect(ctx.uidHash).not.toBe("u1");
  });

  it("App Check bloğu olmayan istek (emulator/debug) mevcut gibi çalışır", () => {
    const ctx = buildContext("analyzeDecision", req({ app: undefined }));
    expect(ctx.uid).toBe("u1");
  });

  it("replay reddi auth kontrolünden ÖNCE gelmez: oturumsuz istek yine unauthenticated", () => {
    try {
      buildContext("analyzeDecision", req({ auth: undefined }));
      expect.unreachable("reddedilmeliydi");
    } catch (error) {
      expect((error as AppError).code).toBe("unauthenticated");
    }
  });

  it.each([
    "analyzeDecision",
    "deleteAccount",
    "exportData",
    "createRewardTicket",
  ])("%s ortak sınırı kullandığı için aynı korumayı alır", (fn) => {
    expect(() =>
      buildContext(fn, req({
        app: { appId: "app", token: {}, alreadyConsumed: true },
      })),
    ).toThrow(AppError);
  });
});
