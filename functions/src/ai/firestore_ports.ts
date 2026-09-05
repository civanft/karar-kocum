/**
 * AnalysisPorts üretim implementasyonu — İKİ transaction sözleşmesi
 * (İş Paketi 2B).
 *
 *  1) reserve():  kabul kontrolü + TÜM rezervasyonlar tek transaction'da.
 *     Journal create-if-absent idempotency kapısıdır: aynı requestId
 *     rezervasyonları İKİNCİ kez tüketemez. Kontrol reddederse transaction
 *     iptal olur, hiçbir sayaç artmaz.
 *
 *  2) finalize(): journal + karar + analiz + kredi + GERÇEK spend/token
 *     muhasebesi tek transaction'da. `completed` ancak hepsi başarılıysa
 *     yazılır; çökerse journal `provider_succeeded` kalır ve retry
 *     tamamlar.
 *
 * VERİ UYUMLULUĞU: mevcut `ops/dailySpend`, `ops/dailyTokens`,
 * `ops/dailyAnalysisCount` ve `rateLimits/{uid}` belgelerinin şeması ve
 * anlamı DEĞİŞMEDİ — bunlar GERÇEKLEŞEN tüketimi tutmaya devam eder.
 * Rezervasyonlar AYRI belgelerde tutulur:
 *   - ops/dailySpendReserved       {gün: rezerve USD}
 *   - ops/dailyTokensReserved      {gün: rezerve token}
 *   - users/{uid}/analysisReservations/state  {credits: n}
 * Üçü de istemciye KAPALIDIR (`match /ops/{id}` deny + users alt
 * koleksiyonlarında cascade yok) — rules DEĞİŞTİRİLMEDİ. Alan yoksa 0
 * kabul edilir; eski revizyon bunları yok sayar, rollback zararsızdır.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import {
  ANALYSIS_REQUESTS_COLLECTION,
  canTransition,
  JournalState,
} from "./analysis_journal.js";
import {
  LATEST_ANALYSIS_ID,
  type AnalysisPorts,
  type CreditsSnapshot,
  type JournalRecord,
  type ReserveOutcome,
  type StoredAnalysis,
} from "./analyze_service.js";
import { contentFingerprint } from "./analysis_fingerprint.js";
import type { TokenUsage } from "./openai_gateway.js";
import { utcDayKey } from "./cost_control.js";
import type { UsageEstimate } from "./usage_estimate.js";
import {
  evaluateRateLimit,
  type RateLimitState,
} from "../quota/rate_limiter.js";
import {
  DAILY_GLOBAL_ANALYSIS_LIMIT,
  DAILY_SPEND_LIMIT_USD,
  DAILY_TOKEN_LIMIT,
  INITIAL_FREE_CREDITS,
  PER_USER_ANALYZE_LIMITS,
} from "../config.js";

/** Sayısal olmayan/negatif veri 0'a kırpılır — bozuk belge limiti delemez. */
function nonNegative(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, value)
    : 0;
}

/** ops belgeleri {gün: değer} haritasıdır; gün yoksa 0. */
function dayValue(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  day: string,
): number {
  return snapshot.exists ? nonNegative(snapshot.data()?.[day]) : 0;
}

function rejected(error: AppError): ReserveOutcome {
  return { status: "rejected", error };
}

export class FirestoreAnalysisPorts implements AnalysisPorts {
  constructor(private readonly uid: string) {}

  private get db() {
    return getFirestore();
  }

  private decisionRef(decisionId: string) {
    return this.db.doc(`users/${this.uid}/decisions/${decisionId}`);
  }

  async readDecisionContent(decisionId: string): Promise<unknown | null> {
    const snapshot = await this.decisionRef(decisionId).get();
    if (!snapshot.exists) return null;
    const data = snapshot.data()!;
    return {
      title: data["title"],
      options: data["options"],
      criteria: data["criteria"],
    };
  }

  /** Alan hiç yazılmamışsa BAŞLANGIÇ kabul edilir (sunucu lazy-init). */
  async peekCredits(): Promise<CreditsSnapshot> {
    const user = await this.db.doc(`users/${this.uid}`).get();
    const data = user.data() ?? {};
    const plan = data["plan"] === "premium" ? "premium" : "free";
    const pools = readPools(data);
    return { plan, remaining: pools.free + pools.reward };
  }

  private journalRef(requestId: string) {
    return this.db.doc(
      `users/${this.uid}/${ANALYSIS_REQUESTS_COLLECTION}/${requestId}`,
    );
  }

  private static toRecord(data: Record<string, unknown>): JournalRecord {
    return {
      state: data["state"] as JournalState,
      decisionId: String(data["decisionId"] ?? ""),
      contentFingerprint: String(data["contentFingerprint"] ?? ""),
      analysis: data["analysis"] as StoredAnalysis | undefined,
      usage: data["usage"] as TokenUsage | undefined,
      failureCode: data["failureCode"] as string | undefined,
    };
  }

  async readJournal(requestId: string): Promise<JournalRecord | null> {
    const snap = await this.journalRef(requestId).get();
    if (!snap.exists) return null;
    return FirestoreAnalysisPorts.toRecord(snap.data()!);
  }

  private get reservationRef() {
    return this.db.doc(`users/${this.uid}/analysisReservations/state`);
  }
  private get rateRef() {
    return this.db.doc(`rateLimits/${this.uid}`);
  }
  private ops(
    id:
      | "dailyAnalysisCount"
      | "dailySpend"
      | "dailySpendReserved"
      | "dailyTokens"
      | "dailyTokensReserved",
  ) {
    return this.db.doc(`ops/${id}`);
  }

  /**
   * ATOMİK KABUL + REZERVASYON — tek transaction.
   *
   * Journal create-if-absent idempotency kapısıdır: kayıt varsa HİÇBİR
   * sayaç artmaz. Yoksa rate/kredi/günlük slot/token/USD kontrolleri
   * yapılır ve hepsi geçerse rezervasyonlar AYNI transaction'da yazılır.
   * Böylece farklı requestId'lerle gelen eşzamanlı çağrılar kontrolü aynı
   * anda geçemez.
   */
  async reserve(params: {
    requestId: string;
    decisionId: string;
    contentFingerprint: string;
    estimate: UsageEstimate;
  }): Promise<ReserveOutcome> {
    const journalRef = this.journalRef(params.requestId);
    const userRef = this.db.doc(`users/${this.uid}`);
    const day = utcDayKey();
    const nowMs = Date.now();

    return this.db.runTransaction<ReserveOutcome>(async (tx) => {
      // ---- OKUMALAR (Firestore: tüm okumalar yazımlardan ÖNCE) ----
      const journal = await tx.get(journalRef);
      if (journal.exists) {
        return {
          status: "existing",
          record: FirestoreAnalysisPorts.toRecord(journal.data()!),
        };
      }

      const [user, rate, reservations] = await Promise.all([
        tx.get(userRef),
        tx.get(this.rateRef),
        tx.get(this.reservationRef),
      ]);
      const count = await tx.get(this.ops("dailyAnalysisCount"));
      const spend = await tx.get(this.ops("dailySpend"));
      const spendRes = await tx.get(this.ops("dailySpendReserved"));
      const tokens = await tx.get(this.ops("dailyTokens"));
      const tokensRes = await tx.get(this.ops("dailyTokensReserved"));

      const data = user.data() ?? {};
      const plan = data["plan"] === "premium" ? "premium" : "free";
      const pools = readPools(data);
      const reservedCredits = nonNegative(reservations.data()?.["credits"]);

      // ---- KABUL KONTROLLERİ ----
      const rateDecision = evaluateRateLimit(
        rate.exists ? (rate.data() as RateLimitState) : null,
        nowMs,
        PER_USER_ANALYZE_LIMITS,
      );
      if (!rateDecision.allowed) {
        return rejected(
          new AppError("rate-limited", "Çok sık istek — lütfen biraz bekle.", {
            retryAfterSeconds: rateDecision.retryAfterSeconds,
          }),
        );
      }

      // Rezerve edilmiş krediler kullanılabilir sayılmaz: eşzamanlı iki
      // istek son krediyi PAYLAŞAMAZ.
      if (plan !== "premium" && pools.free + pools.reward - reservedCredits <= 0) {
        return rejected(
          new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
            remaining: 0,
            initial: INITIAL_FREE_CREDITS,
          }),
        );
      }

      if (dayValue(count, day) >= DAILY_GLOBAL_ANALYSIS_LIMIT) {
        return rejected(
          new AppError(
            "daily-limit",
            "Bugünkü analiz limiti doldu — yarın tekrar deneyebilirsin.",
            { dailyLimit: DAILY_GLOBAL_ANALYSIS_LIMIT },
          ),
        );
      }

      const tokensCommitted =
        dayValue(tokens, day) + dayValue(tokensRes, day) + params.estimate.tokens;
      if (tokensCommitted > DAILY_TOKEN_LIMIT) {
        return rejected(
          new AppError(
            "daily-limit",
            "Bugünkü analiz limiti doldu — yarın tekrar deneyebilirsin.",
            { dailyTokenLimit: DAILY_TOKEN_LIMIT },
          ),
        );
      }

      // USD kesici premium'u etkilemez (mevcut §4.3 davranışı korunur).
      const spendCommitted =
        dayValue(spend, day) + dayValue(spendRes, day) + params.estimate.usd;
      if (plan !== "premium" && spendCommitted > DAILY_SPEND_LIMIT_USD) {
        return rejected(
          new AppError(
            "ai-unavailable",
            "AI analizi geçici olarak yoğunlukta — lütfen daha sonra dene.",
            { circuitBreaker: true },
          ),
        );
      }

      // ---- YAZIMLAR (hepsi ya da hiçbiri) ----
      const record: JournalRecord = {
        state: JournalState.reserved,
        decisionId: params.decisionId,
        contentFingerprint: params.contentFingerprint,
      };
      tx.create(journalRef, {
        state: JournalState.reserved,
        decisionId: params.decisionId,
        contentFingerprint: params.contentFingerprint,
        estimateTokens: params.estimate.tokens,
        estimateUsd: params.estimate.usd,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(this.rateRef, rateDecision.next);
      tx.set(this.ops("dailyAnalysisCount"), { [day]: FieldValue.increment(1) }, { merge: true });
      tx.set(
        this.ops("dailyTokensReserved"),
        { [day]: FieldValue.increment(params.estimate.tokens) },
        { merge: true },
      );
      tx.set(
        this.ops("dailySpendReserved"),
        { [day]: FieldValue.increment(params.estimate.usd) },
        { merge: true },
      );
      if (plan !== "premium") {
        tx.set(
          this.reservationRef,
          { credits: FieldValue.increment(1) },
          { merge: true },
        );
      }
      return { status: "created", record };
    });
  }

  /**
   * Rezervasyon kapanışı — finalize ve settleFailure'ın ORTAK yazımı.
   *
   * `actual` verilirse rezervasyon serbest bırakılıp yerine gerçek tüketim
   * yazılır; verilmezse yalnız serbest bırakılır. Kredi rezervasyonu her
   * durumda düşer (premium'da hiç artırılmamıştır → aşağıda 0'a kırpılır).
   */
  private releaseReservation(
    tx: FirebaseFirestore.Transaction,
    params: {
      day: string;
      estimate: UsageEstimate;
      actual?: { tokens: number; usd: number };
      creditReserved: boolean;
    },
  ): void {
    tx.set(
      this.ops("dailyTokensReserved"),
      { [params.day]: FieldValue.increment(-params.estimate.tokens) },
      { merge: true },
    );
    tx.set(
      this.ops("dailySpendReserved"),
      { [params.day]: FieldValue.increment(-params.estimate.usd) },
      { merge: true },
    );
    if (params.actual) {
      tx.set(
        this.ops("dailyTokens"),
        { [params.day]: FieldValue.increment(params.actual.tokens) },
        { merge: true },
      );
      tx.set(
        this.ops("dailySpend"),
        { [params.day]: FieldValue.increment(params.actual.usd) },
        { merge: true },
      );
    }
    if (params.creditReserved) {
      tx.set(
        this.reservationRef,
        { credits: FieldValue.increment(-1) },
        { merge: true },
      );
    }
  }

  /** reserved → provider_call_started; yarışta yalnız biri true alır. */
  async markProviderCallStarted(requestId: string): Promise<boolean> {
    const ref = this.journalRef(requestId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const from = snap.data()!["state"] as JournalState;
      if (!canTransition(from, JournalState.providerCallStarted)) return false;
      tx.update(ref, {
        state: JournalState.providerCallStarted,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  async recordProviderSuccess(params: {
    requestId: string;
    analysis: StoredAnalysis;
    usage: TokenUsage;
  }): Promise<void> {
    const ref = this.journalRef(params.requestId);
    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const from = snap.data()!["state"] as JournalState;
      if (!canTransition(from, JournalState.providerSucceeded)) return;
      tx.update(ref, {
        state: JournalState.providerSucceeded,
        analysis: params.analysis,
        usage: params.usage,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  /**
   * TERMİNAL BAŞARISIZLIK — journal geçişi + rezervasyon kapanışı TEK
   * transaction'da. İdempotent: izin verilmeyen geçişte HİÇBİR yazım olmaz,
   * dolayısıyla rezervasyon iki kez serbest bırakılamaz.
   *
   * Günlük analiz slotu ve rate hakkı serbest BIRAKILMAZ: her deneme
   * sağlayıcıda maliyet üretebilir, iade etmek maliyet korumasını
   * zayıflatırdı (mevcut ihtiyatlı politika korunuyor).
   */
  async settleFailure(params: {
    requestId: string;
    state: JournalState;
    failureCode?: string;
    estimate: UsageEstimate;
    billed: boolean;
  }): Promise<void> {
    const ref = this.journalRef(params.requestId);
    const userRef = this.db.doc(`users/${this.uid}`);
    const day = utcDayKey();

    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const from = snap.data()!["state"] as JournalState;
      if (!canTransition(from, params.state)) return;
      const user = await tx.get(userRef);
      const premium = user.data()?.["plan"] === "premium";

      tx.update(ref, {
        state: params.state,
        ...(params.failureCode ? { failureCode: params.failureCode } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
      this.releaseReservation(tx, {
        day,
        estimate: params.estimate,
        // Sağlayıcıya çağrı yapıldıysa ücretlendirilmiş olabiliriz:
        // rezervasyon tahmin değeriyle GERÇEK sayaca dönüşür.
        actual: params.billed
          ? { tokens: params.estimate.tokens, usd: params.estimate.usd }
          : undefined,
        creditReserved: !premium,
      });
    });
  }

  /**
   * TEK transaction: journal→completed + karar fingerprint doğrulaması +
   * aiAnalyses/latest + status + kredi düşümü. Retry edilse bile kredi ve
   * sayaçlar İKİ KEZ uygulanmaz (journal durumu geçiş kapısıdır).
   */
  async finalize(params: {
    requestId: string;
    decisionId: string;
    expectedFingerprint: string;
    analysis: StoredAnalysis;
    initialCredits: number;
    usage: TokenUsage;
    costUsd: number;
    estimate: UsageEstimate;
  }): Promise<{ outcome: "completed" | "superseded"; analysisId: string }> {
    const day = utcDayKey();
    const actual = {
      tokens: params.usage.inputTokens + params.usage.outputTokens,
      usd: params.costUsd,
    };
    const userRef = this.db.doc(`users/${this.uid}`);
    const decisionRef = this.decisionRef(params.decisionId);
    const analysisRef = decisionRef
      .collection("aiAnalyses")
      .doc(LATEST_ANALYSIS_ID);
    const journalRef = this.journalRef(params.requestId);

    return this.db.runTransaction(async (tx) => {
      // ---- OKUMALAR (tümü yazımlardan ÖNCE) ----
      const journal = await tx.get(journalRef);
      if (!journal.exists) {
        throw new AppError("internal", "Analiz üretilemedi, lütfen tekrar dene.");
      }
      const state = journal.data()!["state"] as JournalState;

      // Zaten uygulanmış: kredi ve muhasebe TEKRAR uygulanmaz. Buradan
      // hiçbir yazım yapılmadan çıkılır — tekrarlanan finalize etkisizdir.
      if (state === JournalState.completed) {
        return { outcome: "completed" as const, analysisId: LATEST_ANALYSIS_ID };
      }
      if (state === JournalState.superseded) {
        return { outcome: "superseded" as const, analysisId: LATEST_ANALYSIS_ID };
      }
      if (!canTransition(state, JournalState.completed)) {
        throw new AppError("internal", "Analiz üretilemedi, lütfen tekrar dene.");
      }

      const decision = await tx.get(decisionRef);
      const user = await tx.get(userRef);
      const data = user.data() ?? {};
      const plan = data["plan"] === "premium" ? "premium" : "free";

      /**
       * Her iki dalda da rezervasyon KAPANIR ve GERÇEK tüketim yazılır:
       * sağlayıcı çağrısı yapıldı, para harcandı. Kullanıcı kredisi ise
       * yalnız `completed` dalında düşer.
       */
      const settleUsage = () =>
        this.releaseReservation(tx, {
          day,
          estimate: params.estimate,
          actual,
          creditReserved: plan !== "premium",
        });

      // Karar analiz sürerken DEĞİŞTİ mi (ya da silindi mi)?
      const currentFingerprint = decision.exists
        ? contentFingerprint({
            content: {
              title: decision.data()!["title"],
              options: decision.data()!["options"],
              criteria: decision.data()!["criteria"],
            } as never,
            model: params.analysis.model,
            promptVersion: params.analysis.promptVersion,
          })
        : null;

      if (currentFingerprint !== params.expectedFingerprint) {
        // ESKİ içerik için üretilen analiz YENİ karara BAĞLANMAZ ve
        // kullanıcı kredisi YANMAZ — ama gerçek maliyet kaydedilir.
        tx.update(journalRef, {
          state: JournalState.superseded,
          updatedAt: FieldValue.serverTimestamp(),
        });
        settleUsage();
        return { outcome: "superseded" as const, analysisId: LATEST_ANALYSIS_ID };
      }

      if (plan !== "premium") {
        const pools = readPools(data, params.initialCredits);
        // Düşüm sırası (7A): önce ücretsiz, sonra ödül; her iki havuz da
        // > 0 şartıyla düşer → NEGATİF DEĞER İMKÂNSIZ.
        if (pools.free > 0) {
          tx.set(userRef, { freeAnalysisCredits: pools.free - 1 }, { merge: true });
        } else if (pools.reward > 0) {
          tx.set(userRef, { rewardCredits: pools.reward - 1 }, { merge: true });
        } else {
          throw new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
            remaining: 0,
            initial: params.initialCredits,
          });
        }
      }

      tx.set(analysisRef, {
        ...params.analysis,
        generatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(decisionRef, { status: "analyzed" });
      tx.update(journalRef, {
        state: JournalState.completed,
        updatedAt: FieldValue.serverTimestamp(),
      });
      settleUsage();
      return { outcome: "completed" as const, analysisId: LATEST_ANALYSIS_ID };
    });
  }

}

/**
 * Kredi havuzları (7A): freeAnalysisCredits lazy-init'li (yazılmamışsa
 * BAŞLANGIÇ), rewardCredits yazılmamışsa 0; bozuk/negatif veri 0'a kırpılır.
 * Saf fonksiyon — birim testli.
 */
export function readPools(
  data: Record<string, unknown>,
  initialFree: number = INITIAL_FREE_CREDITS,
): { free: number; reward: number } {
  const clamp = (value: unknown, fallback: number) =>
    typeof value === "number" ? Math.max(0, Math.trunc(value)) : fallback;
  return {
    free: clamp(data["freeAnalysisCredits"], initialFree),
    reward: clamp(data["rewardCredits"], 0),
  };
}
