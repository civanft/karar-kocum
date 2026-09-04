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
import type { CostCircuitBreaker } from "./cost_control.js";
import { computeCostUsd } from "./cost_control.js";
import type { DailyAnalysisLimiter } from "./daily_limit.js";
import type { AiGateway, TokenUsage } from "./openai_gateway.js";
import type { DailyTokenGuard } from "./token_counter.js";
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
}

export interface AnalysisPorts {
  /** Kararı SUNUCUDAN oku — istemci payload'ına güven yok. */
  readDecisionContent(decisionId: string): Promise<unknown | null>;
  peekCredits(): Promise<CreditsSnapshot>;

  /** requestId ile journal kaydını oku (yoksa null). */
  readJournal(requestId: string): Promise<JournalRecord | null>;

  /**
   * ATOMİK REZERVASYON: journal(reserved) kaydını OLUŞTUR. Kayıt zaten
   * varsa mevcut kaydı döndürür (çift oluşturma imkânsız) — paralel
   * duplicate çağrılarda yalnız BİRİ sağlayıcıyı çağırabilir.
   */
  reserve(params: {
    requestId: string;
    decisionId: string;
    contentFingerprint: string;
  }): Promise<{ created: boolean; record: JournalRecord }>;

  /** reserved → provider_call_started (yalnız bu geçiş kazanır). */
  markProviderCallStarted(requestId: string): Promise<boolean>;

  /** Sağlayıcı sonucunu DAYANIKLI yaz (provider_succeeded). */
  recordProviderSuccess(params: {
    requestId: string;
    analysis: StoredAnalysis;
    usage: TokenUsage;
  }): Promise<void>;

  /** Terminal/uncertain durum işaretle; rezervasyonlar serbest bırakılır. */
  markOutcome(params: {
    requestId: string;
    state: JournalState;
    failureCode?: string;
  }): Promise<void>;

  /**
   * ATOMİK FİNALİZE — TEK transaction'da:
   *  - journal provider_succeeded → completed (yalnız bir kez)
   *  - karar fingerprint'i DEĞİŞMEDİYSE aiAnalyses/latest + status
   *  - kredi bir kez düşer (remaining > 0 şartıyla → negatif imkânsız)
   * Fingerprint değiştiyse `superseded` döner; kredi DÜŞMEZ.
   */
  finalize(params: {
    requestId: string;
    decisionId: string;
    expectedFingerprint: string;
    analysis: StoredAnalysis;
    initialCredits: number;
  }): Promise<{ outcome: "completed" | "superseded"; analysisId: string }>;
}

export interface RateGuard {
  check(uid: string): Promise<void>;
}

export class AnalyzeService {
  constructor(
    private readonly ports: AnalysisPorts,
    private readonly gateway: AiGateway,
    private readonly rateGuard: RateGuard,
    private readonly breaker: CostCircuitBreaker,
    private readonly dailyLimiter: DailyAnalysisLimiter,
    private readonly tokenGuard: DailyTokenGuard,
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

    // [3] JOURNAL — aynı requestId daha önce görülmüş mü?
    const existing = await this.ports.readJournal(requestId);
    if (existing) {
      this.assertSameRequest(existing, decisionId, fingerprint);

      // Zaten uygulanmış: sağlayıcı ÇAĞRILMAZ, sayaçlar ARTMAZ.
      if (isAlreadyApplied(existing.state) && existing.analysis) {
        return { analysisId: LATEST_ANALYSIS_ID, analysis: existing.analysis };
      }
      // Sağlayıcı sonucu var ama finalize edilmemiş → SAĞLAYICISIZ finalize.
      if (canFinalizeWithoutProvider(existing.state) && existing.analysis) {
        return this.finalizeStored(ctx, {
          requestId,
          decisionId,
          fingerprint,
          analysis: existing.analysis,
          usage: existing.usage,
          startedMs,
        });
      }
      if (existing.state === JournalState.superseded) {
        throw new AppError(
          "invalid-argument",
          "Karar bu analiz üretilirken değişti — lütfen yeniden analiz et.",
        );
      }
      if (existing.state === JournalState.terminalFailed) {
        throw new AppError(
          "internal",
          "Analiz üretilemedi, lütfen tekrar dene.",
        );
      }
      if (!mayCallProvider(existing.state)) {
        // provider_call_started / uncertain: sonuç BİLİNMİYOR.
        throw new AppError(
          "ai-uncertain",
          "Analiz sonucu doğrulanamadı, birazdan tekrar dene.",
          { retryable: true },
        );
      }
    }

    // [4] REZERVASYON — journal + kotalar. Paralel duplicate'te yalnız biri
    // `created` alır; diğeri mevcut kaydı görüp sağlayıcıyı ÇAĞIRMAZ.
    const reserved = await this.ports.reserve({
      requestId,
      decisionId,
      contentFingerprint: fingerprint,
    });
    if (!reserved.created) {
      this.assertSameRequest(reserved.record, decisionId, fingerprint);
      if (isAlreadyApplied(reserved.record.state) && reserved.record.analysis) {
        return {
          analysisId: LATEST_ANALYSIS_ID,
          analysis: reserved.record.analysis,
        };
      }
      if (
        canFinalizeWithoutProvider(reserved.record.state) &&
        reserved.record.analysis
      ) {
        return this.finalizeStored(ctx, {
          requestId,
          decisionId,
          fingerprint,
          analysis: reserved.record.analysis,
          usage: reserved.record.usage,
          startedMs,
        });
      }
      throw new AppError(
        "ai-uncertain",
        "Analiz sonucu doğrulanamadı, birazdan tekrar dene.",
        { retryable: true },
      );
    }

    // [5] Kotalar — rezervasyon SONRASI, sağlayıcıdan ÖNCE.
    try {
      await this.rateGuard.check(ctx.uid);
      const credits = await this.ports.peekCredits();
      if (credits.plan === "free" && credits.remaining <= 0) {
        throw new AppError("quota-exceeded", "Ücretsiz analiz hakkın bitti.", {
          remaining: 0,
          initial: INITIAL_FREE_CREDITS,
        });
      }
      await this.breaker.ensureAllowed(credits.plan);
      await this.tokenGuard.ensureUnderLimit();
      await this.dailyLimiter.ensureSlot();
    } catch (error) {
      await this.safeMark(requestId, JournalState.terminalFailed);
      throw error;
    }

    // [6] Sağlayıcı çağrısı — geçişi ÖNCE dayanıklı olarak işaretle.
    const started = await this.ports.markProviderCallStarted(requestId);
    if (!started) {
      // Yarışı başka bir çağrı kazandı: sağlayıcıyı ÇAĞIRMA.
      throw new AppError(
        "ai-uncertain",
        "Analiz sonucu doğrulanamadı, birazdan tekrar dene.",
        { retryable: true },
      );
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
      await this.safeMark(
        requestId,
        uncertain ? JournalState.uncertain : JournalState.terminalFailed,
        error instanceof AppError ? error.code : undefined,
      );
      throw error;
    }

    const analysis: StoredAnalysis = {
      ...completion.output,
      model: OPENAI_MODEL,
      promptVersion: PROMPT_VERSION,
    };

    // [7] Sonucu DAYANIKLI yaz: buradan sonra retry sağlayıcıyı ÇAĞIRMAZ.
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

  private async safeMark(
    requestId: string,
    state: JournalState,
    failureCode?: string,
  ): Promise<void> {
    try {
      await this.ports.markOutcome({ requestId, state, failureCode });
    } catch {
      // İşaretleme başarısızlığı kullanıcıya dönen hatayı DEĞİŞTİRMEZ.
    }
  }

  /**
   * Finalize: karar + kredi + gerçek kullanım muhasebesi. Sağlayıcı
   * ÇAĞRILMAZ. Karar değiştiyse `superseded` → kredi YANMAZ.
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
    const result = await this.ports.finalize({
      requestId: params.requestId,
      decisionId: params.decisionId,
      expectedFingerprint: params.fingerprint,
      analysis: params.analysis,
      initialCredits: INITIAL_FREE_CREDITS,
    });

    if (result.outcome === "superseded") {
      // GERÇEK sağlayıcı maliyeti yine de bir kez muhasebeleşir; kullanıcı
      // kredisi düşmez (stale sonuç kullanıcının hakkını yakmaz).
      await this.recordUsageOnce(ctx, params.usage, params.startedMs, true);
      throw new AppError(
        "invalid-argument",
        "Karar bu analiz üretilirken değişti — lütfen yeniden analiz et.",
      );
    }

    await this.recordUsageOnce(ctx, params.usage, params.startedMs, false);
    return { analysisId: result.analysisId, analysis: params.analysis };
  }

  /** Gerçek kullanım/maliyet — finalize'ın kazandığı çağrıda BİR kez. */
  private async recordUsageOnce(
    ctx: RequestContext,
    usage: TokenUsage | undefined,
    startedMs: number,
    superseded: boolean,
  ): Promise<void> {
    if (!usage) return;
    const costUsd = computeCostUsd(OPENAI_MODEL, usage);
    await this.breaker.record(costUsd);
    await this.tokenGuard.record(usage.inputTokens, usage.outputTokens);
    log("info", superseded ? "analysis_superseded" : "analysis_completed", ctx, {
      model: OPENAI_MODEL,
      promptVersion: PROMPT_VERSION,
      tokensIn: usage.inputTokens,
      tokensOut: usage.outputTokens,
      costUsd,
      durationMs: this.now() - startedMs,
    });
  }
}
