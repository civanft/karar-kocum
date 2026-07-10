/**
 * Günlük GLOBAL analiz limiti — PR #7B maliyet koruması.
 *
 * $0,35'lik USD kesicisinden (cost_control) BAĞIMSIZ ikinci koruma:
 * deterministik adet sayacı. Varsayılan 50 analiz/gün:
 *   50 × ~$0,0004 ≈ $0,02/gün ≈ $0,6/ay — 10 USD bütçesinin %6'sı.
 *
 * Slot, Gemini çağrısından ÖNCE transaction ile ayrılır
 * (increment-if-below): yarışta bile limit AŞILAMAZ. Başarısız analiz
 * slotu iade etmez (muhafazakâr: her deneme Gemini'de para harcar).
 * Kullanıcı KREDİSİ ise yanmaz — limit, commit'ten önce fırlar.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import { utcDayKey } from "./cost_control.js";

/** Günlük global analiz limiti (env ile ezilebilir, deploy'suz değil). */
export function dailyAnalysisLimit(): number {
  const raw = Number(process.env["DAILY_ANALYSIS_LIMIT"]);
  return Number.isFinite(raw) && raw > 0 ? Math.trunc(raw) : 50;
}

export interface DailyCounterStore {
  /**
   * Atomik increment-if-below: limit altındaysa sayacı artırıp true,
   * doluysa DOKUNMADAN false döner.
   */
  reserve(dayKey: string, limit: number): Promise<boolean>;
}

export class DailyAnalysisLimiter {
  constructor(
    private readonly store: DailyCounterStore,
    private readonly limit: number = dailyAnalysisLimit(),
    private readonly now: () => number = Date.now,
  ) {}

  /** Slot ayırır; limit doluysa kullanıcı-dostu hatayla keser. */
  async ensureSlot(): Promise<void> {
    const reserved = await this.store.reserve(
      utcDayKey(this.now),
      this.limit,
    );
    if (!reserved) {
      throw new AppError(
        "daily-limit",
        "Bugünkü analiz limiti doldu — yarın tekrar deneyebilirsin.",
        { dailyLimit: this.limit },
      );
    }
  }
}

/** Üretim deposu: ops/dailyAnalysisCount belgesi {gün: adet} haritası. */
export class FirestoreDailyCounterStore implements DailyCounterStore {
  private ref() {
    return getFirestore().collection("ops").doc("dailyAnalysisCount");
  }

  async reserve(dayKey: string, limit: number): Promise<boolean> {
    return getFirestore().runTransaction(async (tx) => {
      const snapshot = await tx.get(this.ref());
      const current = snapshot.exists
        ? Number(snapshot.data()?.[dayKey] ?? 0)
        : 0;
      if (current >= limit) return false;
      tx.set(this.ref(), { [dayKey]: FieldValue.increment(1) }, { merge: true });
      return true;
    });
  }
}
