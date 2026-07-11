/**
 * Günlük GLOBAL token tüketim sayacı — Gemini cost guard.
 *
 * $0,15/gün USD kesici ve 20/gün adet limitine EK üçüncü emniyet:
 * gerçekleşen giriş+çıkış token toplamını gün bazında biriktirir ve
 * DAILY_TOKEN_LIMIT aşılırsa yeni analizleri durdurur.
 *
 * Kayıt, analiz TAMAMLANDIKTAN sonra yapılır (gerçek token sayısıyla);
 * ön kontrol (ensureUnderLimit) analizden ÖNCE, en son okunan toplamla —
 * yani tek bir "taşkın" analiz limiti bir miktar aşabilir ama sonraki
 * istekler kesilir (best-effort tavan; USD kesici sert sınırı korur).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import { DAILY_TOKEN_LIMIT } from "../config.js";
import { utcDayKey } from "./cost_control.js";

export interface TokenCounterStore {
  /** Bugünkü toplam token (yoksa 0). */
  todayTotal(dayKey: string): Promise<number>;
  /** Token toplamını atomik ekler. */
  add(dayKey: string, tokens: number): Promise<void>;
}

export class DailyTokenGuard {
  constructor(
    private readonly store: TokenCounterStore,
    private readonly limit: number = DAILY_TOKEN_LIMIT,
    private readonly now: () => number = Date.now,
  ) {}

  /** Günlük token tavanı aşıldıysa analizi durdurur. */
  async ensureUnderLimit(): Promise<void> {
    const total = await this.store.todayTotal(utcDayKey(this.now));
    if (total >= this.limit) {
      throw new AppError(
        "daily-limit",
        "Bugünkü analiz limiti doldu — yarın tekrar deneyebilirsin.",
        { dailyTokenLimit: this.limit },
      );
    }
  }

  /** Gerçekleşen token tüketimini kaydeder (best-effort). */
  async record(inputTokens: number, outputTokens: number): Promise<void> {
    await this.store.add(utcDayKey(this.now), inputTokens + outputTokens);
  }
}

/** Üretim deposu: ops/dailyTokens belgesi {gün: toplamToken} haritası. */
export class FirestoreTokenCounterStore implements TokenCounterStore {
  private ref() {
    return getFirestore().collection("ops").doc("dailyTokens");
  }

  async todayTotal(dayKey: string): Promise<number> {
    const snapshot = await this.ref().get();
    const value = snapshot.exists ? snapshot.data()?.[dayKey] : 0;
    return typeof value === "number" ? value : 0;
  }

  async add(dayKey: string, tokens: number): Promise<void> {
    await this.ref().set(
      { [dayKey]: FieldValue.increment(tokens) },
      { merge: true },
    );
  }
}
