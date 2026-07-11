/**
 * Günlük global analiz limiti testleri (PR #7B).
 */
import { describe, expect, it } from "vitest";

import {
  DailyAnalysisLimiter,
  dailyAnalysisLimit,
  type DailyCounterStore,
} from "../src/ai/daily_limit";
import { AppError } from "../src/core/errors";

/** Firestore transaction'ının bellek içi eşleniği (atomik reserve). */
class MemoryCounterStore implements DailyCounterStore {
  counts = new Map<string, number>();

  async reserve(dayKey: string, limit: number): Promise<boolean> {
    const current = this.counts.get(dayKey) ?? 0;
    if (current >= limit) return false;
    this.counts.set(dayKey, current + 1);
    return true;
  }
}

const DAY1 = Date.UTC(2026, 6, 10, 12); // 2026-07-10
const DAY2 = Date.UTC(2026, 6, 11, 12); // 2026-07-11

describe("DailyAnalysisLimiter", () => {
  it("varsayılan limit 20 (hotfix)", () => {
    expect(dailyAnalysisLimit()).toBe(20);
  });

  it("limit altında slot ayrılır ve sayaç artar", async () => {
    const store = new MemoryCounterStore();
    const limiter = new DailyAnalysisLimiter(store, 50, () => DAY1);

    await limiter.ensureSlot();
    await limiter.ensureSlot();
    expect(store.counts.get("2026-07-10")).toBe(2);
  });

  it("limit dolunca 'Bugünkü analiz limiti doldu' hatası", async () => {
    const store = new MemoryCounterStore();
    const limiter = new DailyAnalysisLimiter(store, 3, () => DAY1);

    for (let i = 0; i < 3; i++) await limiter.ensureSlot();

    const error = await limiter.ensureSlot().catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AppError);
    expect((error as AppError).code).toBe("daily-limit");
    expect((error as AppError).message).toContain(
      "Bugünkü analiz limiti doldu",
    );
    // Red, sayacı BOZMAZ (reserve false dönerken dokunmadı):
    expect(store.counts.get("2026-07-10")).toBe(3);
  });

  it("gün devri: yeni günün sayacı sıfırdan başlar", async () => {
    const store = new MemoryCounterStore();
    let nowMs = DAY1;
    const limiter = new DailyAnalysisLimiter(store, 2, () => nowMs);

    await limiter.ensureSlot();
    await limiter.ensureSlot();
    await expect(limiter.ensureSlot()).rejects.toMatchObject({
      code: "daily-limit",
    });

    nowMs = DAY2; // ertesi gün
    await limiter.ensureSlot(); // yeni anahtar → geçer
    expect(store.counts.get("2026-07-11")).toBe(1);
    expect(store.counts.get("2026-07-10")).toBe(2); // eski gün korunur
  });

  it("yarış: eşzamanlı istekler limit AŞAMAZ (atomik reserve)", async () => {
    const store = new MemoryCounterStore();
    const limiter = new DailyAnalysisLimiter(store, 5, () => DAY1);

    const results = await Promise.allSettled(
      Array.from({ length: 20 }, () => limiter.ensureSlot()),
    );
    const granted = results.filter((r) => r.status === "fulfilled").length;
    expect(granted).toBe(5);
    expect(store.counts.get("2026-07-10")).toBe(5); // tam limit, fazlası yok
  });
});
