/**
 * Analiz orkestratörü — İDEMPOTENT ve KURTARILABİLİR akış (İş Paketi 2).
 *
 * Akış: doğrula → boyut → journal bak → rezerve et → sağlayıcı → dayanıklı
 * sonuç → finalize (karar + kredi + gerçek kullanım) → yanıt.
 *
 * GÜVENCE SINIRI: OpenAI için belgelenmiş provider-side idempotency YOKTUR
 * ve Firestore ile sağlayıcı arasında tek dağıtık transaction kurulamaz.
 * Bu yüzden "exactly once external side effect" İDDİA EDİLMEZ. Sağlayıcı
 * çağrısının sonucu çözülemezse kayıt `uncertain` olur; aynı requestId ile
 * OTOMATİK ikinci çağrı YAPILMAZ.
 *
 * Kota adaleti: kredi yalnız GEÇERLİ ve GÜNCEL karara bağlanan başarılı
 * analiz için bir kez düşer. Karar analiz sürerken değiştiyse sonuç
 * `superseded` olur ve kullanıcı kredisi YANMAZ.
 */
import { AppError } from "../core/errors.js";
import { log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";
import {
  ANALYSIS_RECONCILE_LIMIT,
  INITIAL_FREE_CREDITS,
  MAX_INPUT_CHARS,
  MAX_OUTPUT_TOKENS,
  OPENAI_MODEL,
} from "../config.js";
import {
  canFinalizeWithoutProvider,
  isAlreadyApplied,
  JournalState,
  mayCallProvider,
} from "./analysis_journal.js";
import { contentFingerprint } from "./analysis_fingerprint.js";
import { computeCostUsd } from "./cost_control.js";
import type { AiGateway, TokenUsage } from "./openai_gateway.js";
import { estimateUsage, type UsageEstimate } from "./usage_estimate.js";
import { buildUserMessage, PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt.js";
import {
  analyzeRequestSchema,
  decisionContentSchema,
  type AnalysisOutput,
} from "./schema.js";

/** aiAnalyses altında SABİT belge kimliği — geçmiş yok, üzerine yazılır. */
export const LATEST_ANALYSIS_ID = "latest";

export interface StoredAnalysis extends AnalysisOutput {
  model: string;
  promptVersion: string;
}

export interface CreditsSnapshot {
  plan: "free" | "premium";
  /** Kalan kredi; alan hiç yazılmamışsa BAŞLANGIÇ (5) kabul edilir. */
  remaining: number;
}

/**
 * REZERVASYON KÖKENİ (İş Paketi 2C) — journal'a rezervasyon anında yazılan
 * ve BİR DAHA DEĞİŞMEYEN gerçekler.
 *
 * Neden gerekli: 2B'de gün anahtarı, kullanıcı planı ve tahmin miktarı
 * kapanış anında YENİDEN türetiliyordu. Gün dönümü, plan değişimi ve yeniden
 * deploy bu türetmeleri yanlışlar; sonuç negatif sayaç veya sızmış
 * rezervasyondur. Artık kapanış bu kaydı OKUR, yeniden hesaplamaz.
 */
export interface ReservationProvenance {
  accountingVersion: number;
  /** Rezervasyonun açıldığı UTC gün anahtarı — kapanış AYNI günü kullanır. */
  day: string;
  estimate: UsageEstimate;
  /** Rezervasyon anında kredi GERÇEKTEN artırıldı mı. */
  creditReserved: boolean;
  planAtReservation: "free" | "premium";
  /**
   * Rezervasyon hâlâ AÇIK mı. Sözleşme: `reservationExpiresAt` alanının
   * VARLIĞI rezervasyonun açık olduğu anlamına gelir; kapanışta silinir.
   * Böylece bir kaydın muhasebesinin kapanıp kapanmadığı tek bakışta bellidir.
   */
  open: boolean;
  expiresAtMs: number | null;
}

/** Journal kaydının servise görünen kesiti. */
export interface JournalRecord {
  state: JournalState;
  decisionId: string;
  contentFingerprint: string;
  /** provider_succeeded/completed durumunda dolu. */
  analysis?: StoredAnalysis;
  usage?: TokenUsage;
  /** terminal_failed durumunda kullanıcıya dönecek sabit hata kodu. */
  failureCode?: string;
  /**
   * Rezervasyon kökeni. 2C ÖNCESİ kayıtlarda YOKTUR (undefined): o kayıtlar
   * için kesin bilgi olmadığından sayaçlara DOKUNULMAZ.
   */
  reservation?: ReservationProvenance;
}

/**
 * REZERVASYON SONUCU (İş Paketi 2B).
 *
 * `rejected`, kabul kontrolünün transaction İÇİNDE reddettiği durumdur:
 * hiçbir sayaç artmamıştır, journal oluşturulmamıştır. Bu yüzden aynı
 * requestId hâlâ temizdir — yönergeyi hata kodu belirler.
 */
export type ReserveOutcome =
  | { status: "created"; record: JournalRecord }
  | { status: "existing"; record: JournalRecord }
  | { status: "rejected"; error: AppError };

export interface AnalysisPorts {
  /** Kararı SUNUCUDAN oku — istemci payload'ına güven yok. */
  readDecisionContent(decisionId: string): Promise<unknown | null>;

  /** requestId ile journal kaydını oku (yoksa null). */
  readJournal(requestId: string): Promise<JournalRecord | null>;

  /**
   * ATOMİK KABUL + REZERVASYON — TEK transaction'da:
   *  - journal(reserved) create-if-absent (idempotency kapısı)
   *  - kullanıcı rate-limit hakkı
   *  - kredi uygunluğu ve kredi rezervasyonu
   *  - günlük analiz slotu
   *  - konservatif token rezervasyonu
   *  - konservatif USD rezervasyonu
   *
   * Kayıt zaten varsa `existing` döner ve HİÇBİR sayaç artmaz: aynı
   * requestId ile tekrarlanan çağrı rezervasyonları İKİNCİ kez tüketemez.
   * Kabul kontrolü reddederse transaction iptal olur; hiçbir yazım kalmaz.
   */
  reserve(params: {
    requestId: string;
    decisionId: string;
    contentFingerprint: string;
    estimate: UsageEstimate;
  }): Promise<ReserveOutcome>;

  /** reserved → provider_call_started (yalnız bu geçiş kazanır). */
  markProviderCallStarted(requestId: string): Promise<boolean>;

  /** Sağlayıcı sonucunu DAYANIKLI yaz (provider_succeeded). */
  recordProviderSuccess(params: {
    requestId: string;
    analysis: StoredAnalysis;
    usage: TokenUsage;
  }): Promise<void>;

  /**
   * TERMİNAL BAŞARISIZLIK — TEK transaction'da journal durumunu yazar ve
   * rezervasyonu kapatır.
   *
   * `billed: true` ise sağlayıcıya çağrı YAPILMIŞTIR ve büyük olasılıkla
   * ücretlendirilmişizdir: token/USD rezervasyonu serbest BIRAKILMAZ,
   * tahmin değeriyle GERÇEK sayaca dönüştürülür. Kredi rezervasyonu her
   * durumda serbest bırakılır — kullanıcı üretilemeyen analiz için ödemez.
   */
  settleFailure(params: {
    requestId: string;
    state: JournalState;
    failureCode?: string;
    billed: boolean;
  }): Promise<void>;

  /**
   * FIRSATÇI KURTARMA — yalnız BU kullanıcının asılı kalmış rezervasyonları.
   *
   * Sınırlıdır (limit) ve sınırsız koleksiyon taraması YAPMAZ. Her kayıt
   * kendi transaction'ında, durum kapısıyla idempotent olarak kapatılır.
   * Yeni bir callable/scheduled function GEREKTİRMEZ: kullanıcı yeni bir
   * analiz başlattığında çalışır.
   */
  reconcileStaleReservations(nowMs: number, limit: number): Promise<number>;

  /**
   * ATOMİK FİNALİZE — TEK transaction'da:
   *  - journal provider_succeeded → completed (yalnız bir kez)
   *  - karar fingerprint'i DEĞİŞMEDİYSE aiAnalyses/latest + status
   *  - kredi bir kez düşer (remaining > 0 şartıyla → negatif imkânsız)
   *  - token ve USD rezervasyonu kapatılıp GERÇEK tüketim yazılır
   * Fingerprint değiştiyse `superseded` döner; kredi DÜŞMEZ ama gerçek
   * sağlayıcı maliyeti yine bir kez kaydedilir.
   *
   * `completed` journal'ı ancak bu muhasebenin TAMAMI başarılıysa yazılır:
   * transaction çökerse journal `provider_succeeded` kalır ve aynı
   * requestId ile retry eksik muhasebeyi tamamlar.
   */
  finalize(params: {
    requestId: string;
    decisionId: string;
    expectedFingerprint: string;
    analysis: StoredAnalysis;
    initialCredits: number;
    usage: TokenUsage;
    costUsd: number;
  }): Promise<{ outcome: "completed" | "superseded"; analysisId: string }>;
}

export class AnalyzeService {
  /**
   * Kabul kontrolü (rate/kredi/günlük slot/token/USD) ARTIK ayrı guard
   * nesnelerinde değil, [AnalysisPorts.reserve] transaction'ının içindedir.
   * Nedeni: ayrı kontroller yalnız OKUMA yapıyordu; eşzamanlı istekler
   * hepsini aynı anda geçip limiti delebiliyordu.
   */
  constructor(
    private readonly ports: AnalysisPorts,
    private readonly gateway: AiGateway,
    private readonly now: () => number = Date.now,
  ) {}

  async run(
    ctx: RequestContext,
    rawRequest: unknown,
  ): Promise<{ analysisId: string; analysis: StoredAnalysis }> {
    const startedMs = this.now();

    // [1] STRICT payload: decisionId + requestId (idempotency anahtarı).
    const request = analyzeRequestSchema.safeParse(rawRequest);
    if (!request.success) {
      throw new AppError("invalid-argument", "Geçersiz istek.");
    }
    const { decisionId, requestId } = request.data;

    // [2] Kararı SUNUCUDAN oku ve doğrula.
    const rawContent = await this.ports.readDecisionContent(decisionId);
    if (rawContent == null) {
      throw new AppError("invalid-argument", "Karar bulunamadı.");
    }
    const content = decisionContentSchema.safeParse(rawContent);
    if (!content.success) {
      throw new AppError(
        "invalid-argument",
        "Karar içeriği analiz için uygun değil.",
      );
    }

    // [2c] GİRİŞ BOYUTU — HİÇBİR sayaç tüketilmeden ÖNCE (İş Paketi 2).
    const userMessage = buildUserMessage(content.data);
    if (userMessage.length > MAX_INPUT_CHARS) {
      throw new AppError(
        "invalid-argument",
        "Karar analiz için fazla büyük — bazı maddeleri kısaltıp tekrar dene.",
        { maxInputChars: MAX_INPUT_CHARS },
      );
    }

    const fingerprint = contentFingerprint({
      content: content.data,
      model: OPENAI_MODEL,
      promptVersion: PROMPT_VERSION,
    });

    // Konservatif kullanım tahmini — rezervasyonun temeli (usage_estimate.ts).
    const estimate = estimateUsage({
      promptChars: userMessage.length + SYSTEM_PROMPT.length,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      model: OPENAI_MODEL,
    });

    // [2d] FIRSATÇI KURTARMA — kullanıcı yeni bir analiz başlatıyor; bu,
    // kendi asılı kalmış rezervasyonlarını kapatmak için doğal ve maliyetsiz
    // andır. Sınırlıdır ve BAŞARISIZ OLURSA analizi engellemez.
    await this.reconcileQuietly(ctx);

    // [3] JOURNAL — aynı requestId daha önce görülmüş mü?
    const existing = await this.ports.readJournal(requestId);
    if (existing) {
      this.assertSameRequest(existing, decisionId, fingerprint);
      const resolved = await this.resolveExisting(ctx, existing, {
        requestId,
        decisionId,
        fingerprint,
        startedMs,
      });
      if (resolved) return resolved;
    }

    // [4] ATOMİK KABUL + REZERVASYON — tek transaction.
    const reserved = await this.ports.reserve({
      requestId,
      decisionId,
      contentFingerprint: fingerprint,
      estimate,
    });
    if (reserved.status === "rejected") {
      // Transaction iptal oldu: hiçbir sayaç artmadı, journal oluşmadı.
      throw reserved.error;
    }
    if (reserved.status === "existing") {
      this.assertSameRequest(reserved.record, decisionId, fingerprint);
      const resolved = await this.resolveExisting(ctx, reserved.record, {
        requestId,
        decisionId,
        fingerprint,
        startedMs,
      });
      if (resolved) return resolved;
      // `reserved` durumundaki kayıt sağlayıcıya ilerleyebilir: yarışın
      // gerçek hakemi markProviderCallStarted'dır.
    }

    // [5] Sağlayıcı çağrısı — geçişi ÖNCE dayanıklı olarak işaretle.
    const started = await this.ports.markProviderCallStarted(requestId);
    if (!started) {
      // Yarışı başka bir çağrı kazandı: sağlayıcıyı ÇAĞIRMA. Rezervasyon
      // kazananın elindedir; burada serbest BIRAKILMAZ.
      throw this.uncertain();
    }

    let completion;
    try {
      completion = await this.gateway.completeAnalysis({
        system: SYSTEM_PROMPT,
        user: userMessage,
        model: OPENAI_MODEL,
        maxOutputTokens: MAX_OUTPUT_TOKENS,
      });
    } catch (error) {
      const uncertain =
        error instanceof AppError && error.code === "ai-uncertain";
      // Sağlayıcıya çağrı YAPILDI: ücretlendirilmiş olabiliriz, bu yüzden
      // token/USD rezervasyonu tahmin değeriyle GERÇEK sayaca yazılır.
      await this.settle(ctx, requestId, {
        state: uncertain ? JournalState.uncertain : JournalState.terminalFailed,
        failureCode: error instanceof AppError ? error.code : undefined,
        billed: true,
      });
      throw this.terminalProviderError(error);
    }

    const analysis: StoredAnalysis = {
      ...completion.output,
      model: OPENAI_MODEL,
      promptVersion: PROMPT_VERSION,
    };

    // [6] Sonucu DAYANIKLI yaz: buradan sonra retry sağlayıcıyı ÇAĞIRMAZ.
    await this.ports.recordProviderSuccess({
      requestId,
      analysis,
      usage: completion.usage,
    });

    return this.finalizeStored(ctx, {
      requestId,
      decisionId,
      fingerprint,
      analysis,
      usage: completion.usage,
      startedMs,
    });
  }

  /**
   * Var olan journal kaydını çözer. Sonuç döndürürse akış BİTMİŞTİR;
   * `null` dönerse kayıt sağlayıcıya ilerlemeye uygundur.
   */
  private async resolveExisting(
    ctx: RequestContext,
    record: JournalRecord,
    params: {
      requestId: string;
      decisionId: string;
      fingerprint: string;
      startedMs: number;
    },
  ): Promise<{ analysisId: string; analysis: StoredAnalysis } | null> {
    // Zaten uygulanmış: sağlayıcı ÇAĞRILMAZ, muhasebe TEKRAR uygulanmaz.
    if (isAlreadyApplied(record.state) && record.analysis) {
      return { analysisId: LATEST_ANALYSIS_ID, analysis: record.analysis };
    }
    // Sağlayıcı sonucu var ama finalize edilmemiş → SAĞLAYICISIZ finalize.
    // Eksik kalan muhasebe burada TAMAMLANIR.
    if (canFinalizeWithoutProvider(record.state) && record.analysis) {
      return this.finalizeStored(ctx, {
        requestId: params.requestId,
        decisionId: params.decisionId,
        fingerprint: params.fingerprint,
        analysis: record.analysis,
        usage: record.usage,
        // TAHMİN BURADA YENİDEN HESAPLANMAZ: rezervasyonun miktarı ve günü
        // journal'da yazılıdır ve kapanış onu okur (2C).
        startedMs: params.startedMs,
      });
    }
    if (record.state === JournalState.superseded) {
      throw new AppError(
        "superseded",
        "Karar bu analiz üretilirken değişti — yeni bir analiz başlatabilirsin.",
      );
    }
    if (record.state === JournalState.terminalFailed) {
      // Bu requestId TÜKENDİ: aynı anahtarla tekrar denemek aynı sonucu verir.
      throw new AppError(
        "ai-failed",
        "Analiz üretilemedi — yeni bir analiz başlatabilirsin.",
      );
    }
    if (!mayCallProvider(record.state)) {
      // provider_call_started / uncertain: sonuç BİLİNMİYOR.
      throw this.uncertain();
    }
    return null;
  }

  /**
   * Sonucu bilinmeyen pencere. AYNI requestId ile OTOMATİK tekrar YAPILMAZ:
   * kayıt sağlayıcıya ilerlemişse aynı anahtar sonsuza kadar aynı hatayı
   * verirdi. İstemciye "yeni istek" yönergesi gider.
   */
  private uncertain(): AppError {
    return new AppError(
      "ai-uncertain",
      "Analiz sonucu doğrulanamadı — yeni bir analiz başlatabilirsin.",
    );
  }

  /** Sağlayıcı hatasını istemci sözleşmesine çevirir. */
  private terminalProviderError(error: unknown): unknown {
    if (error instanceof AppError && error.code === "ai-uncertain") {
      return this.uncertain();
    }
    return error;
  }

  /**
   * Terminal işaretleme + rezervasyon kapanışı.
   *
   * Başarısızlığı kullanıcıya dönen SAĞLAYICI hatasının yerine geçmez —
   * kullanıcı asıl sorunu görmeli. Ama SESSİZCE de yutulmaz: loglanır ve
   * journal kurtarılabilir durumda (rezervasyon AÇIK) bırakılır, böylece
   * kullanıcının bir sonraki analizinde fırsatçı kurtarma onu kapatır.
   */
  private async settle(
    ctx: RequestContext,
    requestId: string,
    params: {
      state: JournalState;
      failureCode?: string;
      billed: boolean;
    },
  ): Promise<void> {
    try {
      await this.ports.settleFailure({ requestId, ...params });
    } catch (error) {
      // Ham UID/prompt/sağlayıcı metni YOK — yalnız biçim denetimli teşhis.
      log("error", "reservation_settlement_failed", ctx, {
        targetState: params.state,
        billed: params.billed,
        errorType: error instanceof Error ? error.name : "unknown",
      });
    }
  }

  /**
   * Fırsatçı kurtarma — asla kullanıcının analizini engellemez. Kurtarma
   * bir "en iyi çaba" bakımıdır; başarısız olursa bir sonraki istek dener.
   */
  private async reconcileQuietly(ctx: RequestContext): Promise<void> {
    try {
      const recovered = await this.ports.reconcileStaleReservations(
        this.now(),
        ANALYSIS_RECONCILE_LIMIT,
      );
      if (recovered > 0) {
        log("info", "reservations_reconciled", ctx, { recovered });
      }
    } catch (error) {
      log("warn", "reservation_reconcile_failed", ctx, {
        errorType: error instanceof Error ? error.name : "unknown",
      });
    }
  }

  /** Aynı requestId farklı karar/içerikle kullanılamaz. */
  private assertSameRequest(
    record: JournalRecord,
    decisionId: string,
    fingerprint: string,
  ): void {
    if (
      record.decisionId !== decisionId ||
      record.contentFingerprint !== fingerprint
    ) {
      throw new AppError(
        "invalid-argument",
        "Bu istek başka bir karar için başlatılmış — lütfen yeniden dene.",
      );
    }
  }

  /**
   * Finalize — karar + kredi + GERÇEK kullanım muhasebesi TEK transaction'da
   * (ports.finalize). Sağlayıcı ÇAĞRILMAZ.
   *
   * Muhasebe artık burada AYRI bir side effect DEĞİLDİR: `completed` journal
   * ancak kredi, spend ve token yazımının tamamı başarılıysa oluşur. Bu
   * fonksiyon transaction'dan sonra yalnız LOG üretir.
   */
  private async finalizeStored(
    ctx: RequestContext,
    params: {
      requestId: string;
      decisionId: string;
      fingerprint: string;
      analysis: StoredAnalysis;
      usage?: TokenUsage;
      startedMs: number;
    },
  ): Promise<{ analysisId: string; analysis: StoredAnalysis }> {
    // Usage yalnız çok eski/eksik journal kayıtlarında boş olabilir. 0 saymak
    // maliyeti gizlerdi; sıfır olmayan ihtiyatlı bir taban kullanılır. Gerçek
    // rezervasyon miktarı journal'dadır ve kapanışı port yapar.
    const usage: TokenUsage = params.usage ?? {
      inputTokens: 0,
      outputTokens: MAX_OUTPUT_TOKENS,
    };
    const costUsd = computeCostUsd(OPENAI_MODEL, usage);

    const result = await this.ports.finalize({
      requestId: params.requestId,
      decisionId: params.decisionId,
      expectedFingerprint: params.fingerprint,
      analysis: params.analysis,
      initialCredits: INITIAL_FREE_CREDITS,
      usage,
      costUsd,
    });

    this.logOutcome(ctx, {
      superseded: result.outcome === "superseded",
      usage,
      costUsd,
      startedMs: params.startedMs,
    });

    if (result.outcome === "superseded") {
      throw new AppError(
        "superseded",
        "Karar bu analiz üretilirken değişti — yeni bir analiz başlatabilirsin.",
      );
    }
    return { analysisId: result.analysisId, analysis: params.analysis };
  }

  private logOutcome(
    ctx: RequestContext,
    params: {
      superseded: boolean;
      usage: TokenUsage;
      costUsd: number;
      startedMs: number;
    },
  ): void {
    log(
      "info",
      params.superseded ? "analysis_superseded" : "analysis_completed",
      ctx,
      {
        model: OPENAI_MODEL,
        promptVersion: PROMPT_VERSION,
        tokensIn: params.usage.inputTokens,
        tokensOut: params.usage.outputTokens,
        costUsd: params.costUsd,
        durationMs: this.now() - params.startedMs,
      },
    );
  }
}
