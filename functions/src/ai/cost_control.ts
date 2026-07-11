/**
 * Maliyet kontrolü — AI-ANALIZ-TASARIMI.md §6 + §4.3 devre kesici.
 * Fiyat tablosu 1M token başına USD; model eklenince buraya satır eklenir
 * (bilinmeyen model: muhafazakâr varsayılan — maliyeti ASLA 0 sayma).
 */
import { getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import { DAILY_SPEND_LIMIT_USD } from "../config.js";
import type { TokenUsage } from "./gemini_gateway.js";

interface ModelPrice {
  inputPer1M: number;
  outputPer1M: number;
}

const PRICES: Record<string, ModelPrice> = {
  "gemini-2.0-flash": { inputPer1M: 0.1, outputPer1M: 0.4 },
  "gemini-2.0-flash-lite": { inputPer1M: 0.075, outputPer1M: 0.3 },
};

const FALLBACK_PRICE: ModelPrice = { inputPer1M: 5, outputPer1M: 15 };

export function computeCostUsd(model: string, usage: TokenUsage): number {
  const price = PRICES[model] ?? FALLBACK_PRICE;
  return (
    (usage.inputTokens / 1_000_000) * price.inputPer1M +
    (usage.outputTokens / 1_000_000) * price.outputPer1M
  );
}

export interface SpendStore {
  /** Günün toplamını döndürür (UTC gün anahtarı). */
  todayTotal(dayKey: string): Promise<number>;
  /** Harcamayı atomik ekler. */
  add(dayKey: string, usd: number): Promise<void>;
}

export function utcDayKey(now: () => number = Date.now): string {
  return new Date(now()).toISOString().slice(0, 10);
}

/**
 * Devre kesici: günlük global harcama eşiği aşıldıysa FREE tier durur,
 * premium sürer (§4.3). Kontrol ucuz tutulur; kesin sayaç değil koruma.
 */
export class CostCircuitBreaker {
  constructor(
    private readonly store: SpendStore,
    private readonly limitUsd: number = DAILY_SPEND_LIMIT_USD,
    private readonly now: () => number = Date.now,
  ) {}

  async ensureAllowed(plan: "free" | "premium"): Promise<void> {
    if (plan === "premium") return; // premium kesiciden etkilenmez
    const total = await this.store.todayTotal(utcDayKey(this.now));
    if (total >= this.limitUsd) {
      throw new AppError(
        "ai-unavailable",
        "AI analizi geçici olarak yoğunlukta — lütfen daha sonra dene.",
        { circuitBreaker: true, retryable: true },
      );
    }
  }

  async record(usd: number): Promise<void> {
    await this.store.add(utcDayKey(this.now), usd);
  }
}

/** Üretim deposu: ops/dailySpend belgesi {gün: toplamUsd} haritası. */
export class FirestoreSpendStore implements SpendStore {
  private ref() {
    return getFirestore().collection("ops").doc("dailySpend");
  }

  async todayTotal(dayKey: string): Promise<number> {
    const snapshot = await this.ref().get();
    const value = snapshot.exists ? snapshot.data()?.[dayKey] : 0;
    return typeof value === "number" ? value : 0;
  }

  async add(dayKey: string, usd: number): Promise<void> {
    const { FieldValue } = await import("firebase-admin/firestore");
    await this.ref().set(
      { [dayKey]: FieldValue.increment(usd) },
      { merge: true },
    );
  }
}
