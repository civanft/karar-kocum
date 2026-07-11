import { describe, expect, it } from "vitest";

import { AppError } from "../src/core/errors";
import {
  RateLimiter,
  type RateLimitState,
  type RateLimitStore,
} from "../src/quota/rate_limiter";

/** Bellek içi atomik depo — Firestore transaction'ının test eşleniği. */
class MemoryStore implements RateLimitStore {
  state = new Map<string, RateLimitState>();

  async update(
    key: string,
    mutate: (current: RateLimitState | null) => RateLimitState,
  ): Promise<RateLimitState> {
    const next = mutate(this.state.get(key) ?? null);
    this.state.set(key, next);
    return next;
  }
}

const limits = { perMinute: 3, perHour: 5 };
const HOUR = 3_600_000;

function make(startMs = 1_000_000) {
  let nowMs = startMs;
  const store = new MemoryStore();
  const limiter = new RateLimiter(store, limits, () => nowMs);
  return {
    store,
    limiter,
    advance: (ms: number) => {
      nowMs += ms;
    },
  };
}

describe("RateLimiter", () => {
  it("limit içinde istekler geçer ve sayaç artar", async () => {
    const { limiter, store } = make();
    await limiter.check("u1");
    await limiter.check("u1");
    expect(store.state.get("u1")!.minute.count).toBe(2);
    expect(store.state.get("u1")!.hour.count).toBe(2);
  });

  it("dakika limiti aşımı: rate-limited + retryAfterSeconds", async () => {
    const { limiter } = make();
    for (let i = 0; i < 3; i++) await limiter.check("u1");

    const error = await limiter.check("u1").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AppError);
    const appError = error as AppError;
    expect(appError.code).toBe("rate-limited");
    const retryAfter = appError.details?.retryAfterSeconds as number;
    expect(retryAfter).toBeGreaterThan(0);
    expect(retryAfter).toBeLessThanOrEqual(60);
  });

  it("red, sayaç durumunu BOZMAZ (artırmaz)", async () => {
    const { limiter, store } = make();
    for (let i = 0; i < 3; i++) await limiter.check("u1");
    await limiter.check("u1").catch(() => undefined);
    await limiter.check("u1").catch(() => undefined);
    expect(store.state.get("u1")!.minute.count).toBe(3);
  });

  it("dakika penceresi dolunca sıfırlanır, saat penceresi sürer", async () => {
    const { limiter, advance, store } = make();
    for (let i = 0; i < 3; i++) await limiter.check("u1");

    advance(61_000); // 1 dk geçti
    await limiter.check("u1"); // yeni dakika penceresi

    const state = store.state.get("u1")!;
    expect(state.minute.count).toBe(1);
    expect(state.hour.count).toBe(4); // saatlik birikim sürüyor
  });

  it("saat limiti dakika sıfırlansa da uygulanır", async () => {
    const { limiter, advance } = make();
    // 5 istek = saat limiti (3+2, dakika pencereleri arasında)
    for (let i = 0; i < 3; i++) await limiter.check("u1");
    advance(61_000);
    for (let i = 0; i < 2; i++) await limiter.check("u1");

    advance(61_000); // dakika yine sıfır ama saat dolu
    const error = await limiter.check("u1").catch((e: unknown) => e);
    expect((error as AppError).code).toBe("rate-limited");
    const retryAfter = (error as AppError).details
      ?.retryAfterSeconds as number;
    expect(retryAfter).toBeGreaterThan(60); // saat penceresi kaldı
  });

  it("kullanıcılar birbirinin limitini etkilemez", async () => {
    const { limiter } = make();
    for (let i = 0; i < 3; i++) await limiter.check("u1");
    await expect(limiter.check("u2")).resolves.toBeUndefined();
  });

  it("hotfix madde 3: perDay limiti (3/gün) saat dolsa da uygulanır", async () => {
    let nowMs = 1_000_000;
    const store = new MemoryStore();
    const limiter = new RateLimiter(
      store,
      { perMinute: 3, perHour: 10, perDay: 3 },
      () => nowMs,
    );

    await limiter.check("u1");
    nowMs += HOUR; // dakika+saat penceresi tazelensin
    await limiter.check("u1");
    nowMs += HOUR;
    await limiter.check("u1"); // günlük 3. istek

    nowMs += HOUR; // hâlâ aynı gün
    const error = await limiter.check("u1").catch((e: unknown) => e);
    expect((error as AppError).code).toBe("rate-limited");
    // Ertesi gün sıfırlanır:
    nowMs += 24 * HOUR;
    await expect(limiter.check("u1")).resolves.toBeUndefined();
  });

  it("perDay tanımsızsa gün limiti uygulanmaz (geriye uyumlu)", async () => {
    let nowMs = 1_000_000;
    const store = new MemoryStore();
    const limiter = new RateLimiter(
      store,
      { perMinute: 3, perHour: 100 },
      () => nowMs,
    );
    for (let i = 0; i < 20; i++) {
      await limiter.check("u1");
      nowMs += 61_000; // dakika penceresini aş
    }
    // 20 istek geçti — gün penceresi yok
    expect(store.state.get("u1")!.hour.count).toBeGreaterThan(3);
  });
});
