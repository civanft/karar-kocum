/**
 * Rate limit altyapısı — AI-ANALIZ-TASARIMI.md §3 (Redis'siz, Firestore
 * transaction sayaçlı "sliding-window-lite").
 *
 * Mantık saf ve enjekte edilebilir: [RateLimitStore] + [Clock] ile birim
 * test edilir; üretimde FirestoreRateLimitStore kullanılır.
 * Limit değerleri Remote Config'ten okunacak (PR #4); şimdilik sabit varsayılan.
 */
import { getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";

export interface WindowState {
  startMs: number;
  count: number;
}

export interface RateLimitState {
  minute: WindowState;
  hour: WindowState;
}

export interface RateLimitStore {
  /** Atomik oku-değiştir-yaz; Firestore'da transaction'a eşlenir. */
  update(
    key: string,
    mutate: (current: RateLimitState | null) => RateLimitState,
  ): Promise<RateLimitState>;
}

export interface RateLimits {
  perMinute: number;
  perHour: number;
}

export const DEFAULT_ANALYZE_LIMITS: RateLimits = { perMinute: 3, perHour: 10 };
export const DEFAULT_SUGGEST_LIMITS: RateLimits = { perMinute: 10, perHour: 40 };

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;

export class RateLimiter {
  constructor(
    private readonly store: RateLimitStore,
    private readonly limits: RateLimits,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * Limit içindeyse sayaçları artırır; aşımda [AppError]("rate-limited")
   * fırlatır — details.retryAfterSeconds istemcide geri sayım için.
   * Sayaç artışı atomik: yarış durumunda limit delinemez.
   */
  async check(key: string): Promise<void> {
    const nowMs = this.now();
    let rejectedRetryAfterSec: number | null = null;

    await this.store.update(key, (current) => {
      const minute = roll(current?.minute, nowMs, MINUTE_MS);
      const hour = roll(current?.hour, nowMs, HOUR_MS);

      if (minute.count >= this.limits.perMinute) {
        rejectedRetryAfterSec = remainingSec(minute, nowMs, MINUTE_MS);
        return { minute, hour }; // sayaç ARTMAZ — red yazımı state'i bozmaz
      }
      if (hour.count >= this.limits.perHour) {
        rejectedRetryAfterSec = remainingSec(hour, nowMs, HOUR_MS);
        return { minute, hour };
      }
      return {
        minute: { ...minute, count: minute.count + 1 },
        hour: { ...hour, count: hour.count + 1 },
      };
    });

    if (rejectedRetryAfterSec != null) {
      throw new AppError(
        "rate-limited",
        "Çok sık istek — lütfen biraz bekle.",
        { retryAfterSeconds: rejectedRetryAfterSec },
      );
    }
  }
}

function roll(
  window: WindowState | undefined,
  nowMs: number,
  sizeMs: number,
): WindowState {
  if (!window || nowMs - window.startMs >= sizeMs) {
    return { startMs: nowMs, count: 0 };
  }
  return window;
}

function remainingSec(
  window: WindowState,
  nowMs: number,
  sizeMs: number,
): number {
  return Math.max(1, Math.ceil((window.startMs + sizeMs - nowMs) / 1000));
}

/** Üretim deposu: rateLimits/{uid} belgesi, Firestore transaction ile. */
export class FirestoreRateLimitStore implements RateLimitStore {
  async update(
    key: string,
    mutate: (current: RateLimitState | null) => RateLimitState,
  ): Promise<RateLimitState> {
    const ref = getFirestore().collection("rateLimits").doc(key);
    return getFirestore().runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const next = mutate(
        snapshot.exists ? (snapshot.data() as RateLimitState) : null,
      );
      tx.set(ref, next);
      return next;
    });
  }
}
