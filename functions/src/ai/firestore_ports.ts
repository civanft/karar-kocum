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
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";

import { AppError } from "../core/errors.js";
import { AI_CONSENT_PATH } from "../privacy/ai_consent.js";
import { assertAccountActive } from "../privacy/account_deletion_barrier.js";
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
  type ReservationProvenance,
  type ReserveOutcome,
  type StoredAnalysis,
} from "./analyze_service.js";
import { contentFingerprint } from "./analysis_fingerprint.js";
import type { TokenUsage } from "./openai_gateway.js";
import { computeCostUsd, utcDayKey } from "./cost_control.js";
import type { UsageEstimate } from "./usage_estimate.js";
import {
  evaluateRateLimit,
  type RateLimitState,
} from "../quota/rate_limiter.js";
import {
  ANALYSIS_RESERVATION_STALE_MS,
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

/** Muhasebe şeması sürümü — köken alanlarının varlığını işaretler. */
export const ACCOUNTING_VERSION = 2;

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

  /** AI izin belgesi — hesap silme kaskadına dahil (`users/{uid}` altında). */
  private aiConsentRef() {
    return this.db.doc(`users/${this.uid}/${AI_CONSENT_PATH}`);
  }

  async readAiConsent(): Promise<unknown | null> {
    const snapshot = await this.aiConsentRef().get();
    return snapshot.exists ? (snapshot.data() ?? null) : null;
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
      reservation: FirestoreAnalysisPorts.toProvenance(data),
    };
  }

  /**
   * Rezervasyon kökenini okur. 2C ÖNCESİ kayıtlarda `accountingVersion`
   * yoktur → `undefined` döner ve çağıran taraf sayaçlara DOKUNMAZ.
   * Eksik köken, "kesin bilgi" gibi tamamlanmaz.
   */
  private static toProvenance(
    data: Record<string, unknown>,
  ): ReservationProvenance | undefined {
    const version = data["accountingVersion"];
    const day = data["reservationDay"];
    if (typeof version !== "number" || typeof day !== "string") return undefined;

    const expiresAt = data["reservationExpiresAt"] as Timestamp | undefined;
    return {
      accountingVersion: version,
      day,
      estimate: {
        tokens: nonNegative(data["estimateTokens"]),
        usd: nonNegative(data["estimateUsd"]),
      },
      creditReserved: data["creditReserved"] === true,
      planAtReservation:
        data["planAtReservation"] === "premium" ? "premium" : "free",
      // SÖZLEŞME: alanın VARLIĞI rezervasyonun açık olduğunu gösterir.
      open: expiresAt != null,
      expiresAtMs: expiresAt ? expiresAt.toMillis() : null,
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
      //
      // HESAP SİLME BARİYERİ (İş Paketi 3): bariyer okuması transaction'ın
      // çakışma kümesine girer. Bariyer yazımı araya girerse transaction
      // yeniden çalışır ve bu kez reddeder — "bariyer ile rezervasyon aynı
      // anda commit ederse" yarışı böyle kapanır.
      await assertAccountActive(tx, this.db, this.uid);

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
      // KÖKEN: bu alanlar rezervasyon anının GERÇEĞİDİR ve bir daha
      // değişmez. Kapanış bunları OKUR — yeniden hesaplamaz.
      tx.create(journalRef, {
        state: JournalState.reserved,
        decisionId: params.decisionId,
        contentFingerprint: params.contentFingerprint,
        accountingVersion: ACCOUNTING_VERSION,
        reservationDay: day,
        estimateTokens: params.estimate.tokens,
        estimateUsd: params.estimate.usd,
        creditReserved: plan !== "premium",
        planAtReservation: plan,
        reservedAt: FieldValue.serverTimestamp(),
        // Varlığı = rezervasyon AÇIK. Kapanışta SİLİNİR.
        reservationExpiresAt: Timestamp.fromMillis(
          nowMs + ANALYSIS_RESERVATION_STALE_MS,
        ),
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
   * REZERVASYON KAPANIŞI — finalize, settleFailure ve reconciliation'ın
   * ORTAK yazımı. Miktar ve GÜN journal kökeninden gelir; hiçbir şey
   * yeniden hesaplanmaz.
   *
   * Negatiflik YAZIM tarafında engellenir: sayaçlar transaction içinde
   * okunup `max(0, mevcut - miktar)` olarak MUTLAK değerle yazılır.
   * `increment(-x)` kullanılmaz — okumada kırpmak, diskte negatif değer
   * oluşmasını engellemezdi.
   *
   * `actual` verilirse rezervasyon serbest bırakılıp yerine gerçek tüketim
   * AYNI güne yazılır; verilmezse yalnız serbest bırakılır.
   */
  private releaseReservation(
    tx: FirebaseFirestore.Transaction,
    reads: {
      tokensReserved: FirebaseFirestore.DocumentSnapshot;
      spendReserved: FirebaseFirestore.DocumentSnapshot;
      credits: FirebaseFirestore.DocumentSnapshot;
    },
    params: {
      provenance: ReservationProvenance;
      actual?: { tokens: number; usd: number };
    },
  ): void {
    const { day, estimate, creditReserved } = params.provenance;

    const tokensLeft = Math.max(
      0,
      dayValue(reads.tokensReserved, day) - estimate.tokens,
    );
    const spendLeft = Math.max(
      0,
      dayValue(reads.spendReserved, day) - estimate.usd,
    );
    tx.set(this.ops("dailyTokensReserved"), { [day]: tokensLeft }, { merge: true });
    tx.set(this.ops("dailySpendReserved"), { [day]: spendLeft }, { merge: true });

    if (params.actual) {
      // Gerçek tüketim REZERVASYONUN GÜNÜNE yazılır: bir isteğin rezervasyonu
      // ve gerçekleşmesi aynı günün defterinde kalır.
      tx.set(
        this.ops("dailyTokens"),
        { [day]: FieldValue.increment(params.actual.tokens) },
        { merge: true },
      );
      tx.set(
        this.ops("dailySpend"),
        { [day]: FieldValue.increment(params.actual.usd) },
        { merge: true },
      );
    }

    // Kredi YALNIZ gerçekten rezerve edildiyse düşer — güncel plan değil,
    // rezervasyon anındaki gerçek belirler.
    if (creditReserved) {
      const left = Math.max(0, nonNegative(reads.credits.data()?.["credits"]) - 1);
      tx.set(this.reservationRef, { credits: left }, { merge: true });
    }
  }

  /** Kapanış için gereken üç sayaç belgesini okur (yazımlardan ÖNCE). */
  private async readReservationCounters(tx: FirebaseFirestore.Transaction) {
    return {
      tokensReserved: await tx.get(this.ops("dailyTokensReserved")),
      spendReserved: await tx.get(this.ops("dailySpendReserved")),
      credits: await tx.get(this.reservationRef),
    };
  }

  /** Kapanışta rezervasyonu KAPALI işaretler: alanın yokluğu = kapalı. */
  private static closedMarker() {
    return {
      reservationExpiresAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    };
  }

  /** reserved → provider_call_started; yarışta yalnız biri true alır. */
  async markProviderCallStarted(requestId: string): Promise<boolean> {
    const ref = this.journalRef(requestId);
    return this.db.runTransaction(async (tx) => {
      // SAĞLAYICI ÇAĞRISINDAN ÖNCEKİ SON GÜVENLİ KONTROL: bariyer açıksa
      // ücretli çağrı BAŞLATILMAZ. Rezervasyon `reserved` kalır ve silme
      // drain'i onu maliyetsiz kapatır.
      await assertAccountActive(tx, this.db, this.uid);

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
   * transaction'da. İdempotent: izin verilmeyen geçişte HİÇBİR yazım olmaz
   * ve kapanmış (open=false) bir rezervasyon İKİNCİ kez kapatılmaz.
   *
   * Günlük analiz slotu ve rate hakkı serbest BIRAKILMAZ: her deneme
   * sağlayıcıda maliyet üretebilir, iade etmek maliyet korumasını
   * zayıflatırdı (mevcut ihtiyatlı politika korunuyor).
   */
  async settleFailure(params: {
    requestId: string;
    state: JournalState;
    failureCode?: string;
    billed: boolean;
  }): Promise<void> {
    const ref = this.journalRef(params.requestId);

    await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const data = snap.data()!;
      const from = data["state"] as JournalState;
      if (!canTransition(from, params.state)) return;

      const provenance = FirestoreAnalysisPorts.toProvenance(data);
      const counters =
        provenance?.open === true
          ? await this.readReservationCounters(tx)
          : null;

      tx.update(ref, {
        state: params.state,
        ...(params.failureCode ? { failureCode: params.failureCode } : {}),
        ...FirestoreAnalysisPorts.closedMarker(),
      });

      // Köken YOKSA (2C öncesi kayıt) sayaçlara DOKUNULMAZ: miktar ve gün
      // kesin bilinmediği için tahminle düşmek negatif/yanlış sonuç üretir.
      if (provenance?.open === true && counters) {
        this.releaseReservation(tx, counters, {
          provenance,
          // Sağlayıcıya çağrı yapıldıysa ücretlendirilmiş olabiliriz:
          // rezervasyon tahmin değeriyle GERÇEK sayaca dönüşür.
          actual: params.billed
            ? { tokens: provenance.estimate.tokens, usd: provenance.estimate.usd }
            : undefined,
        });
      }
    });
  }

  /**
   * FIRSATÇI KURTARMA — bu kullanıcının ASILI kalmış rezervasyonlarını kapatır.
   *
   * SORGU: `reservationExpiresAt < now`, limitli. Bu alan yalnız AÇIK
   * rezervasyonlarda bulunur (kapanışta silinir) ve Firestore alanı olmayan
   * belgeleri eşitsizlik sorgusundan zaten dışlar. Tek alanlı eşitsizlik
   * otomatik tek-alan indeksini kullanır: BİLEŞİK İNDEKS GEREKMEZ, bu yüzden
   * Firestore index deploy'u da gerekmez.
   *
   * Tarama SINIRLIDIR ve yalnız `users/{uid}` altındadır — koleksiyon grubu
   * taraması yapılmaz. Her kayıt kendi transaction'ında kapatılır.
   */
  async reconcileStaleReservations(
    nowMs: number,
    limit: number,
  ): Promise<number> {
    const snapshot = await this.db
      .collection(`users/${this.uid}/${ANALYSIS_REQUESTS_COLLECTION}`)
      .where("reservationExpiresAt", "<", Timestamp.fromMillis(nowMs))
      .limit(limit)
      .get();

    let recovered = 0;
    for (const doc of snapshot.docs) {
      if (await this.reconcileOne(doc.id, nowMs)) recovered++;
    }
    return recovered;
  }

  /**
   * HESAP SİLME DRAIN'İ (İş Paketi 3, sayfalama düzeltmesi 3B).
   *
   * Kullanıcının AÇIK rezervasyonlarını SAYFA SAYFA gezer. `settledAfterMs`
   * kadar YAŞLI olanları — yani onları açan analyzeDecision çağrısının
   * fonksiyon timeout'u dolduğu için ARTIK çalışamayacağı kayıtları — zorla
   * kapatır. Daha genç olanlara DOKUNMAZ ve sayarak döndürür.
   *
   * ═══ NEDEN SAYFALAMA ═══
   *
   * 3. Pakette tek bir `limit(50)` sorgusu yapılıyordu ve yalnız o sayfadaki
   * genç kayıtlar sayılıyordu. İlk 50 kayıt eski olup kapatılırsa 51. ve
   * sonraki AÇIK kayıtlar HİÇ GÖRÜLMEDEN `{open: 0}` dönüyordu; kaskat da
   * bunun üzerine recursive delete'e geçiyordu. Artık:
   *
   *  - sayfa doluysa (size == pageSize) ARKASINDA kayıt olabileceği
   *    varsayılır ve bir sonraki tur baştan sorgular;
   *  - sayfa bütçesi dolarsa `exhausted: true` döner — görülmemiş kayıt
   *    olabileceği için ASLA 0 denmez;
   *  - `{open: 0, exhausted: false}` yalnız SON SAYFA görüldüğünde döner,
   *    yani "kalan yok" iddiası gerçek bir sorgu kanıtına dayanır.
   *
   * Bellek taraması yoktur: her tur en fazla `pageSize × maxPages` belge
   * okur ve çağıran (deleteAccount) turları kendi zaman bütçesiyle sınırlar.
   *
   * Kapanış mantığı KOPYALANMAZ: aynı `reconcileOne` primitive'i kullanılır,
   * dolayısıyla 2C/2D muhasebe değişmezleri aynen geçerlidir.
   *
   * Sorgu `orderBy("reservationExpiresAt")`: alanı OLMAYAN belgeler (yani
   * kapanmış rezervasyonlar) sonuçta hiç yer almaz. Tek alanlı sıralama
   * otomatik indeksi kullanır — bileşik indeks GEREKMEZ.
   */
  async drainReservationsForDeletion(params: {
    nowMs: number;
    settledAfterMs: number;
    pageSize: number;
    maxPages: number;
  }): Promise<{ open: number; exhausted: boolean }> {
    const collection = this.db.collection(
      `users/${this.uid}/${ANALYSIS_REQUESTS_COLLECTION}`,
    );

    for (let page = 0; page < params.maxPages; page++) {
      // İMLEÇ YOK — bilinçli. Kapatılan kayıt `reservationExpiresAt`
      // alanını kaybettiği için sorgudan DÜŞER; her turda baştan sorgulamak
      // ilerlemeyi garanti eder. Değer tabanlı `startAfter` güvensizdi:
      // aynı zaman damgasını paylaşan kayıtların TAMAMI atlanabiliyordu.
      const snapshot = await collection
        .orderBy("reservationExpiresAt")
        .limit(params.pageSize)
        .get();
      if (snapshot.empty) return { open: 0, exhausted: false };

      let closed = 0;
      let young = 0;
      for (const doc of snapshot.docs) {
        const reservedAt = doc.data()["reservedAt"] as Timestamp | undefined;
        const ageMs = reservedAt
          ? params.nowMs - reservedAt.toMillis()
          : Number.POSITIVE_INFINITY;
        if (ageMs >= params.settledAfterMs) {
          await this.reconcileOne(doc.id, params.nowMs, { force: true });
          closed++;
        } else {
          young++;
        }
      }

      // Hiçbiri kapanmadıysa sayfadaki her kayıt GENÇ: ilerleme olmaz.
      // Sayfa doluysa arkasında daha fazlası olabilir.
      if (closed === 0) {
        return { open: young, exhausted: snapshot.size >= params.pageSize };
      }
      // Sayfa dolmadıysa arkasında kayıt yoktu; kapananlar düştü, geriye
      // yalnız bu sayfadaki genç kayıtlar kaldı.
      if (snapshot.size < params.pageSize) {
        return { open: young, exhausted: false };
      }
    }

    // Sayfa bütçesi doldu: GÖRÜLMEMİŞ kayıt olabilir → 0 DENMEZ.
    return { open: 0, exhausted: true };
  }

  /**
   * Tek kaydı kurtarır. Durum kapısı + süre kapısı transaction İÇİNDEDİR:
   * paralel çağrılardan yalnız biri muhasebeyi uygular.
   *
   * Durumlar AYNI ŞEKİLDE ele alınmaz:
   *  - `reserved`: sağlayıcı hiç BAŞLAMADI (provider_call_started geçişi
   *    yapılmamış). Para harcanmadı → rezervasyon serbest, GERÇEK sayaç
   *    ARTIRILMAZ. Kayıt `terminal_failed` olur.
   *  - `provider_call_started`: sonuç BİLİNMİYOR ve ücretlendirilmiş
   *    olabiliriz → tahmin bir kez gerçek tüketime çevrilir. Kayıt
   *    `uncertain` olur. Sağlayıcı ASLA yeniden çağrılmaz.
   *  - `provider_succeeded`: elde ÖDENMİŞ bir analiz var; kaydı terminal
   *    yapmak onu çöpe atardı. Bunun yerine YALNIZ rezervasyon kapatılır
   *    (kredi iade + tahmin→gerçek) ve durum korunur; kullanıcı aynı
   *    requestId ile dönerse analiz hâlâ finalize edilebilir.
   */
  private async reconcileOne(
    requestId: string,
    nowMs: number,
    opts: { force?: boolean } = {},
  ): Promise<boolean> {
    const ref = this.journalRef(requestId);
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const data = snap.data()!;
      const state = data["state"] as JournalState;
      const provenance = FirestoreAnalysisPorts.toProvenance(data);

      // KAPANIŞ KAPISI: alanın yokluğu rezervasyonun zaten kapandığını
      // gösterir — `force` bunu ASLA atlamaz (çift kapanış imkânsız kalır).
      const expiresAt = data["reservationExpiresAt"] as Timestamp | undefined;
      if (!expiresAt) return false;
      // SÜRE KAPISI: hâlâ çalışıyor olabilecek bir isteğe DOKUNMA.
      // Hesap silme drain'i bu kapıyı AÇIKÇA atlar (`force`), çünkü çağıran
      // tarafın yaşını kendisi doğrulamıştır.
      if (!opts.force && expiresAt.toMillis() > nowMs) return false;

      const analysis = data["analysis"] as StoredAnalysis | undefined;

      /**
       * `provider_succeeded` + SAKLANAN SONUÇ → ATOMİK FİNALİZASYON.
       *
       * 2C burada yalnız rezervasyonu kapatıyor, kaydı `provider_succeeded`
       * bırakıyordu. Bu, kredi rezervasyonunu havuza geri verirken kaydı
       * hâlâ finalize edilebilir bırakıyor ve AYNI son kredinin ikinci bir
       * sağlayıcı isteğine dayanak olmasına pencere açıyordu. Artık kayıt
       * aynı transaction'da terminal duruma (completed/superseded) geçer:
       * `provider_succeeded && rezervasyon kapalı` ÜRETİLEMEZ.
       */
      if (state === JournalState.providerSucceeded && analysis) {
        const decisionId = String(data["decisionId"] ?? "");
        const decisionRef = this.decisionRef(decisionId);
        const analysisRef = decisionRef
          .collection("aiAnalyses")
          .doc(LATEST_ANALYSIS_ID);
        const userRef = this.db.doc(`users/${this.uid}`);

        const decision = await tx.get(decisionRef);
        const user = await tx.get(userRef);
        const counters =
          provenance?.open === true
            ? await this.readReservationCounters(tx)
            : null;

        // Gerçek kullanım journal'dan; yoksa rezervasyon tahmini (ihtiyatlı).
        const usage = data["usage"] as TokenUsage | undefined;
        const actual = usage
          ? {
              tokens: usage.inputTokens + usage.outputTokens,
              usd: computeCostUsd(analysis.model, usage),
            }
          : {
              tokens: provenance?.estimate.tokens ?? 0,
              usd: provenance?.estimate.usd ?? 0,
            };

        this.applyFinalization(
          tx,
          { journalRef: ref, decisionRef, analysisRef, userRef },
          { journalData: data, decision, user, counters },
          { analysis, actual, initialCredits: INITIAL_FREE_CREDITS },
        );
        return true;
      }

      const target =
        state === JournalState.reserved
          ? JournalState.terminalFailed
          : state === JournalState.providerCallStarted
            ? JournalState.uncertain
            : // `provider_succeeded` fakat SAKLANAN SONUÇ yok: sonuç
              // doğrulanamaz, analiz uygulanamaz. Kredi TÜKETİLMEZ.
              state === JournalState.providerSucceeded
              ? JournalState.uncertain
              : null;

      if (target === null) return false;

      const counters =
        provenance?.open === true
          ? await this.readReservationCounters(tx)
          : null;

      tx.update(ref, {
        state: target,
        failureCode: "reservation-stale",
        ...FirestoreAnalysisPorts.closedMarker(),
      });

      // Köken yoksa (2C öncesi kayıt) sayaçlara DOKUNULMAZ; kayıt yine de
      // terminal yapılır ki sonsuza kadar taranmasın.
      if (provenance?.open === true && counters) {
        // `reserved`: sağlayıcı başlamadı → gerçek tüketim YOK.
        const billed = state !== JournalState.reserved;
        this.releaseReservation(tx, counters, {
          provenance,
          actual: billed
            ? { tokens: provenance.estimate.tokens, usd: provenance.estimate.usd }
            : undefined,
        });
      }
      return true;
    });
  }

  /**
   * ORTAK ATOMİK FİNALİZASYON (İş Paketi 2D).
   *
   * Hem normal `finalize()` hem de asılı `provider_succeeded` kurtarması
   * BU primitive'i kullanır — transaction mantığı iki yerde KOPYALANMAZ.
   * Tüm okumalar çağıran tarafından yapılıp buraya verilir (Firestore:
   * okumalar yazımlardan önce).
   *
   * Beklenen fingerprint JOURNAL'dan gelir (2C köken ilkesi): kapanış
   * anındaki hesaplamaya değil, rezervasyon anının gerçeğine dayanır.
   */
  private applyFinalization(
    tx: FirebaseFirestore.Transaction,
    refs: {
      journalRef: FirebaseFirestore.DocumentReference;
      decisionRef: FirebaseFirestore.DocumentReference;
      analysisRef: FirebaseFirestore.DocumentReference;
      userRef: FirebaseFirestore.DocumentReference;
    },
    reads: {
      journalData: Record<string, unknown>;
      decision: FirebaseFirestore.DocumentSnapshot;
      user: FirebaseFirestore.DocumentSnapshot;
      counters: {
        tokensReserved: FirebaseFirestore.DocumentSnapshot;
        spendReserved: FirebaseFirestore.DocumentSnapshot;
        credits: FirebaseFirestore.DocumentSnapshot;
      } | null;
    },
    params: {
      analysis: StoredAnalysis;
      actual: { tokens: number; usd: number };
      initialCredits: number;
    },
  ): { outcome: "completed" | "superseded"; creditCharged: boolean } {
    const provenance = FirestoreAnalysisPorts.toProvenance(reads.journalData);
    const data = reads.user.data() ?? {};
    const plan = data["plan"] === "premium" ? "premium" : "free";

    /**
     * Rezervasyon KAPANIR ve GERÇEK tüketim rezervasyonun gününe yazılır.
     * Köken yoksa (2C öncesi) veya rezervasyon zaten kapatılmışsa
     * DOKUNULMAZ — çift kapanış imkânsızdır.
     */
    const settleUsage = () => {
      if (provenance?.open === true && reads.counters) {
        this.releaseReservation(tx, reads.counters, {
          provenance,
          actual: params.actual,
        });
      }
    };

    // Karar analiz sürerken DEĞİŞTİ mi (ya da silindi mi)? Beklenen değer
    // journal'ın rezervasyon anında yazdığı fingerprint'tir.
    const expected = String(reads.journalData["contentFingerprint"] ?? "");
    const currentFingerprint = reads.decision.exists
      ? contentFingerprint({
          content: {
            title: reads.decision.data()!["title"],
            options: reads.decision.data()!["options"],
            criteria: reads.decision.data()!["criteria"],
          } as never,
          model: params.analysis.model,
          promptVersion: params.analysis.promptVersion,
        })
      : null;

    if (currentFingerprint !== expected) {
      // ESKİ içerik için üretilen analiz YENİ karara BAĞLANMAZ ve kullanıcı
      // kredisi YANMAZ — ama gerçek maliyet kaydedilir.
      tx.update(refs.journalRef, {
        state: JournalState.superseded,
        ...FirestoreAnalysisPorts.closedMarker(),
      });
      settleUsage();
      return { outcome: "superseded", creditCharged: false };
    }

    let creditCharged = false;
    if (plan !== "premium") {
      const pools = readPools(data, params.initialCredits);
      // Düşüm sırası (7A): önce ücretsiz, sonra ödül; her iki havuz da
      // > 0 şartıyla düşer → NEGATİF DEĞER İMKÂNSIZ.
      if (pools.free > 0) {
        tx.set(refs.userRef, { freeAnalysisCredits: pools.free - 1 }, { merge: true });
        creditCharged = true;
      } else if (pools.reward > 0) {
        tx.set(refs.userRef, { rewardCredits: pools.reward - 1 }, { merge: true });
        creditCharged = true;
      } else if (provenance?.open === true) {
        // Rezervasyon AÇIKKEN kredi bulunamıyorsa veri tutarsızdır: rezerve
        // edilmiş bir kredi havuzda olmalıydı. Muhasebeyi zorlamak yerine
        // transaction iptal edilir.
        throw new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
          remaining: 0,
          initial: params.initialCredits,
        });
      }
      // provenance.open === false (2C artığı anormal kayıt): rezervasyon
      // BİZİM hatamızla zaten serbest bırakılmış ve o sırada başka bir istek
      // krediyi almış olabilir. Ödenmiş analizi çöpe atmak yerine ücretsiz
      // uygulanır; çağıran taraf bunu LOGLAR. Bu yol yalnız eski kayıtlar
      // için erişilebilirdir — yeni kod bu durumu ÜRETEMEZ.
    }

    tx.set(refs.analysisRef, {
      ...params.analysis,
      generatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(refs.decisionRef, { status: "analyzed" });
    tx.update(refs.journalRef, {
      state: JournalState.completed,
      ...FirestoreAnalysisPorts.closedMarker(),
    });
    settleUsage();
    return { outcome: "completed", creditCharged };
  }

  /**
   * TEK transaction: journal→completed + karar fingerprint doğrulaması +
   * aiAnalyses/latest + status + kredi düşümü + rezervasyon kapanışı.
   * Retry edilse bile kredi ve sayaçlar İKİ KEZ uygulanmaz.
   */
  async finalize(params: {
    requestId: string;
    decisionId: string;
    analysis: StoredAnalysis;
    initialCredits: number;
    usage: TokenUsage;
    costUsd: number;
  }): Promise<{
    outcome: "completed" | "superseded";
    analysisId: string;
    creditCharged: boolean;
  }> {
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
      const journalData = journal.data()!;
      const state = journalData["state"] as JournalState;

      // Zaten uygulanmış: kredi ve muhasebe TEKRAR uygulanmaz. Buradan
      // hiçbir yazım yapılmadan çıkılır — tekrarlanan finalize etkisizdir.
      if (state === JournalState.completed) {
        return {
          outcome: "completed" as const,
          analysisId: LATEST_ANALYSIS_ID,
          creditCharged: false,
        };
      }
      if (state === JournalState.superseded) {
        return {
          outcome: "superseded" as const,
          analysisId: LATEST_ANALYSIS_ID,
          creditCharged: false,
        };
      }
      if (!canTransition(state, JournalState.completed)) {
        throw new AppError("internal", "Analiz üretilemedi, lütfen tekrar dene.");
      }

      const decision = await tx.get(decisionRef);
      const user = await tx.get(userRef);
      const provenance = FirestoreAnalysisPorts.toProvenance(journalData);
      const counters =
        provenance?.open === true
          ? await this.readReservationCounters(tx)
          : null;

      const result = this.applyFinalization(
        tx,
        { journalRef, decisionRef, analysisRef, userRef },
        { journalData, decision, user, counters },
        {
          analysis: params.analysis,
          actual,
          initialCredits: params.initialCredits,
        },
      );
      return { ...result, analysisId: LATEST_ANALYSIS_ID };
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
