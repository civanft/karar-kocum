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
import {
  accountDeletingError,
  barrierRef,
} from "../privacy/account_deletion_barrier.js";

export interface WindowState {
  startMs: number;
  count: number;
}

export interface RateLimitState {
  minute: WindowState;
  hour: WindowState;
  /** Opsiyonel gün penceresi (perDay limiti tanımlıysa kullanılır). */
  day?: WindowState;
}

/**
 * Rate-limit yazımının bağlı olduğu HESAP (İş Paketi 3B).
 *
 * Anahtarın `${uid}:reward` biçiminden UID AYRIŞTIRILMAZ — anahtar biçimi
 * bir gün değişirse sessizce yanlış UID okunurdu. UID typed parametre
 * olarak geçirilir.
 */
export interface RateLimitOptions {
  /** Verilirse yazım, bu hesabın silme bariyeriyle AYNI transaction'da
   *  kontrol edilir; bariyer varsa hiçbir yazım yapılmaz. */
  accountUid?: string;
}

export interface RateLimitStore {
  /** Atomik oku-değiştir-yaz; Firestore'da transaction'a eşlenir. */
  update(
    key: string,
    mutate: (current: RateLimitState | null) => RateLimitState,
    options?: RateLimitOptions,
  ): Promise<RateLimitState>;
}

export interface RateLimits {
  perMinute: number;
  perHour: number;
  /** Opsiyonel günlük limit (hotfix madde 3: analiz 3/gün). */
  perDay?: number;
}

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

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
  async check(key: string, options?: RateLimitOptions): Promise<void> {
    const nowMs = this.now();
    let decision: RateLimitDecision | null = null;

    await this.store.update(
      key,
      (current) => {
        decision = evaluateRateLimit(current, nowMs, this.limits);
        return decision.next;
      },
      options,
    );

    if (decision != null && !(decision as RateLimitDecision).allowed) {
      throw new AppError(
        "rate-limited",
        "Çok sık istek — lütfen biraz bekle.",
        {
          retryAfterSeconds: (decision as RateLimitDecision).retryAfterSeconds,
        },
      );
    }
  }
}

export interface RateLimitDecision {
  allowed: boolean;
  /** Kabulde artırılmış, redde DEĞİŞMEMİŞ pencere durumu. */
  next: RateLimitState;
  /** Yalnız redde anlamlı. */
  retryAfterSeconds: number;
}

/**
 * Pencere değerlendirmesi — SAF fonksiyon.
 *
 * Hem [RateLimiter] hem de analiz rezervasyon transaction'ı bunu kullanır:
 * rate hakkı, kredi/kota rezervasyonuyla AYNI transaction içinde tüketilsin
 * diye mantık tek yerde tutulur (kopyalanmaz).
 *
 * Red durumunda hiçbir sayaç artmaz — state bozulmaz.
 */
export function evaluateRateLimit(
  current: RateLimitState | null,
  nowMs: number,
  limits: RateLimits,
): RateLimitDecision {
  const minute = roll(current?.minute, nowMs, MINUTE_MS);
  const hour = roll(current?.hour, nowMs, HOUR_MS);
  const day = roll(current?.day, nowMs, DAY_MS);
  const unchanged = { minute, hour, day };

  if (minute.count >= limits.perMinute) {
    return {
      allowed: false,
      next: unchanged,
      retryAfterSeconds: remainingSec(minute, nowMs, MINUTE_MS),
    };
  }
  if (hour.count >= limits.perHour) {
    return {
      allowed: false,
      next: unchanged,
      retryAfterSeconds: remainingSec(hour, nowMs, HOUR_MS),
    };
  }
  if (limits.perDay != null && day.count >= limits.perDay) {
    return {
      allowed: false,
      next: unchanged,
      retryAfterSeconds: remainingSec(day, nowMs, DAY_MS),
    };
  }
  return {
    allowed: true,
    next: {
      minute: { ...minute, count: minute.count + 1 },
      hour: { ...hour, count: hour.count + 1 },
      day: { ...day, count: day.count + 1 },
    },
    retryAfterSeconds: 0,
  };
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
    options?: RateLimitOptions,
  ): Promise<RateLimitState> {
    const db = getFirestore();
    const ref = db.collection("rateLimits").doc(key);
    const uid = options?.accountUid;
    return db.runTransaction(async (tx) => {
      // HESAP SİLME BARİYERİ (İş Paketi 3B): rate-limit belgesi de UID'ye
      // bağlı bir kullanıcı kaydıdır. Bariyer okunmazsa, silme sırasında
      // gelen eski bir istek `rateLimits/{uid}:reward` belgesini YETİM
      // olarak yeniden yaratırdı. Okuma transaction'ın çakışma kümesine
      // girer: bariyer aynı anda commit ederse transaction yeniden çalışır.
      if (uid !== undefined) {
        if ((await tx.get(barrierRef(db, uid))).exists) {
          throw accountDeletingError();
        }
      }
      const snapshot = await tx.get(ref);
      const next = mutate(
        snapshot.exists ? (snapshot.data() as RateLimitState) : null,
      );
      tx.set(ref, next);
      return next;
    });
  }
}
