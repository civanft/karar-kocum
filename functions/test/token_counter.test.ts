/**
 * Günlük token sayacı testleri (OpenAI cost guard).
 */
import { describe, expect, it } from "vitest";

import {
  DailyTokenGuard,
  type TokenCounterStore,
} from "../src/ai/token_counter";
import { AppError } from "../src/core/errors";

class MemoryTokenStore implements TokenCounterStore {
  totals = new Map<string, number>();
  async todayTotal(dayKey: string): Promise<number> {
    return this.totals.get(dayKey) ?? 0;
  }
  async add(dayKey: string, tokens: number): Promise<void> {
    this.totals.set(dayKey, (this.totals.get(dayKey) ?? 0) + tokens);
  }
}

const DAY1 = Date.UTC(2026, 6, 10, 12);
const DAY2 = Date.UTC(2026, 6, 11, 12);

describe("DailyTokenGuard", () => {
  it("limit altında geçer; record giriş+çıkış toplar", async () => {
    const store = new MemoryTokenStore();
    const guard = new DailyTokenGuard(store, 10_000, () => DAY1);

    await guard.ensureUnderLimit(); // 0 < 10000
    await guard.record(1500, 600);
    expect(store.totals.get("2026-07-10")).toBe(2100);
  });

  it("tavan dolunca daily-limit hatası (detayda dailyTokenLimit)", async () => {
    const store = new MemoryTokenStore();
    store.totals.set("2026-07-10", 10_000);
    const guard = new DailyTokenGuard(store, 10_000, () => DAY1);

    const error = await guard.ensureUnderLimit().catch((e: unknown) => e);
    expect((error as AppError).code).toBe("daily-limit");
    expect((error as AppError).details?.["dailyTokenLimit"]).toBe(10_000);
  });

  it("gün devri: ertesi gün sayaç sıfırdan başlar", async () => {
    const store = new MemoryTokenStore();
    let nowMs = DAY1;
    const guard = new DailyTokenGuard(store, 4_000, () => nowMs);

    await guard.record(4_000, 0); // tam tavana ulaş
    await expect(guard.ensureUnderLimit()).rejects.toMatchObject({
      code: "daily-limit",
    });

    nowMs = DAY2;
    await expect(guard.ensureUnderLimit()).resolves.toBeUndefined();
    expect(store.totals.get("2026-07-10")).toBe(4_000); // eski gün korunur
  });
});
