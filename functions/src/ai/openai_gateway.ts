/**
 * OpenAI ağ geçidi.
 *
 * RETRY SÖZLEŞMESİ (İş Paketi 2): OpenAI Chat Completions için BELGELENMİŞ
 * bir provider-side idempotency garantisi YOKTUR. Bu yüzden isteğin
 * sağlayıcıya ULAŞMIŞ OLABİLECEĞİ hiçbir hata aynı application requestId
 * içinde otomatik yeniden DENENMEZ — ikinci ÜCRETLİ çağrı ve çift muhasebe
 * riski. Böyle durumlar `ai-uncertain` olarak yüzeye çıkar ve journal
 * `uncertain` durumuna geçer; yeni bir provider çağrısı ancak YENİ bir
 * kullanıcı eylemi ve YENİ requestId ile başlar.
 *
 * Tek istisna 429: sağlayıcı isteği İŞLEMEDEN reddeder (yan etki yok),
 * bu yüzden sınırlı sayıda yeniden denenir.
 *
 * Hata sınıflandırması `classifyProviderError` içindedir; "status yoksa ağ
 * hatasıdır" varsayımı KALDIRILDI (bkz. openai_errors.ts).
 */
import OpenAI from "openai";
import {
  ContentFilterFinishReasonError,
  LengthFinishReasonError,
} from "openai/core/error";
import { zodResponseFormat } from "openai/helpers/zod";

import { AppError } from "../core/errors.js";
import { OPENAI_MAX_RETRIES, OPENAI_TIMEOUT_MS } from "../config.js";
import {
  classifyProviderError,
  ProviderErrorKind,
} from "./openai_errors.js";
import { analysisOutputSchema, type AnalysisOutput } from "./schema.js";

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
}

export interface AnalysisCompletion {
  output: AnalysisOutput;
  usage: TokenUsage;
}

/** Test edilebilirlik sınırı: orkestratör yalnız bu arayüzü bilir. */
export interface AiGateway {
  completeAnalysis(params: {
    system: string;
    user: string;
    model: string;
    maxOutputTokens: number;
  }): Promise<AnalysisCompletion>;
}

/** Testlerde sahtelenen asgari SDK yüzeyi (gerçek SDK tipleri sızmaz). */
export interface OpenAIClientLike {
  complete(params: {
    system: string;
    user: string;
    model: string;
    maxOutputTokens: number;
  }): Promise<{
    parsed: AnalysisOutput | null;
    /** Model açıkça reddettiyse dolu gelir (message.refusal). */
    refusal?: string | null;
    finishReason: string | null;
    usage: TokenUsage;
  }>;
}

/** Kendine zarar içeriği için güvenli yönlendirme (PRD R1). */
export const SELF_HARM_REDIRECT =
  "Bu konu bir karar analizinden daha önemli. Zor bir dönemden geçiyorsan " +
  "yalnız değilsin — 182'yi arayabilir ya da güvendiğin birine ulaşabilirsin.";

type Sleep = (ms: number) => Promise<void>;
const defaultSleep: Sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Üretim SDK adaptörü — sert zaman aşımı (OPENAI_TIMEOUT_MS) ile;
 *  SDK'nın kendi retry'ı kapalı (kendi döngümüz mevcut davranışı korur). */
export function createOpenAIClient(apiKey: string): OpenAIClientLike {
  const client = new OpenAI({
    apiKey,
    timeout: OPENAI_TIMEOUT_MS,
    maxRetries: 0,
  });
  return {
    complete: async (params) => {
      const res = await client.chat.completions.parse({
        model: params.model,
        max_completion_tokens: params.maxOutputTokens,
        temperature: 0.4,
        response_format: zodResponseFormat(analysisOutputSchema, "analysis"),
        messages: [
          { role: "system", content: params.system },
          { role: "user", content: params.user },
        ],
      });
      const choice = res.choices[0];
      return {
        parsed: choice?.message.parsed ?? null,
        refusal: choice?.message.refusal ?? null,
        finishReason: choice?.finish_reason ?? null,
        usage: {
          inputTokens: res.usage?.prompt_tokens ?? 0,
          outputTokens: res.usage?.completion_tokens ?? 0,
        },
      };
    },
  };
}

export class OpenAIGateway implements AiGateway {
  constructor(
    private readonly client: OpenAIClientLike,
    private readonly sleep: Sleep = defaultSleep,
  ) {}

  async completeAnalysis(params: {
    system: string;
    user: string;
    model: string;
    maxOutputTokens: number;
  }): Promise<AnalysisCompletion> {
    // YALNIZ 429 için deneme sayacı: diğer hiçbir hata yeniden denenmez.
    let rateLimitRetries = 0;

    for (;;) {
      let result: Awaited<ReturnType<OpenAIClientLike["complete"]>>;
      try {
        result = await this.client.complete(params);
      } catch (error) {
        const c = classifyProviderError(error);

        if (
          c.kind === ProviderErrorKind.rateLimited &&
          rateLimitRetries < OPENAI_MAX_RETRIES
        ) {
          rateLimitRetries++;
          await this.sleep(1000);
          continue;
        }
        throw toAppError(c);
      }

      // SDK .parse() length/content_filter'ı FIRLATIR; yine de yanıt
      // gövdesinden gelen finish_reason'a karşı ikinci savunma bırakılır.
      if (result.finishReason === "content_filter") {
        throw toAppError(classifyProviderError(
          new ContentFilterFinishReasonError(),
        ));
      }
      if (result.finishReason === "length") {
        throw toAppError(classifyProviderError(new LengthFinishReasonError()));
      }
      if (result.refusal) {
        // Ham refusal metni kullanıcıya/loga taşınmaz; yalnız sınıf.
        throw toAppError(classifyProviderError({ __refusal: true }));
      }
      if (!result.parsed) {
        throw toAppError(classifyProviderError({ __schemaFailure: true }));
      }

      return { output: result.parsed, usage: result.usage };
    }
  }
}

/**
 * Sınıf → kullanıcıya dönecek AppError. Ham sağlayıcı mesajı, prompt veya
 * secret ASLA taşınmaz; yalnız sabit ürün metni ve sınıf adı.
 */
function toAppError(c: ReturnType<typeof classifyProviderError>): AppError {
  switch (c.kind) {
    case ProviderErrorKind.moderated:
      return moderatedError();
    case ProviderErrorKind.refused:
      return new AppError("moderated", "Bu içerik analiz edilemiyor.", {
        selfHarm: false,
        providerKind: c.kind,
      });
    case ProviderErrorKind.outputTruncated:
    case ProviderErrorKind.schemaFailure:
      return new AppError(
        "internal",
        "Analiz üretilemedi, lütfen tekrar dene.",
        { schemaFailure: true, providerKind: c.kind },
      );
    case ProviderErrorKind.rateLimited:
      return new AppError(
        "ai-unavailable",
        "Analiz servisi şu an yoğun, birazdan tekrar dene.",
        { retryable: true, providerKind: c.kind },
      );
    case ProviderErrorKind.transport:
    case ProviderErrorKind.serverError:
      // BELİRSİZ: istek sağlayıcıya ulaşmış olabilir. Otomatik ikinci çağrı
      // YAPILMAZ; çağıran katman journal'ı `uncertain` yapar.
      return new AppError(
        "ai-uncertain",
        "Analiz sonucu doğrulanamadı, birazdan tekrar dene.",
        { retryable: true, providerKind: c.kind },
      );
    case ProviderErrorKind.permanentRequest:
    case ProviderErrorKind.unknown:
    default:
      return new AppError(
        "internal",
        "Analiz üretilemedi, lütfen tekrar dene.",
        { providerKind: c.kind },
      );
  }
}

function moderatedError(): AppError {
  // OpenAI content_filter alt-kategori vermez → nötr güvenli mesaj;
  // kendine-zarar yönlendirmesi ayrı moderasyon geçişinde (takip işi).
  return new AppError("moderated", "Bu içerik analiz edilemiyor.", {
    selfHarm: false,
  });
}
