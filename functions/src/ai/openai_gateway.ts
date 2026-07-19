/**
 * OpenAI ağ geçidi — Gemini'den migrasyon (gemini_gateway.ts'in yerine).
 * AiGateway ARAYÜZÜ DEĞİŞMEDİ: AnalyzeService yalnız bunu bilir.
 *
 * Yapılandırılmış çıktı: chat.completions.parse + zodResponseFormat
 * (mevcut analysisOutputSchema yeniden kullanılır). Moderasyon: OpenAI
 * yanıtı finish_reason === "content_filter" → 'moderated' hatası.
 * Retry: 429 / 5xx / ağ/timeout → OPENAI_MAX_RETRIES kez.
 */
import OpenAI from "openai";
import { zodResponseFormat } from "openai/helpers/zod";

import { AppError } from "../core/errors.js";
import { OPENAI_MAX_RETRIES, OPENAI_TIMEOUT_MS } from "../config.js";
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
    let retries = 0;
    const canRetry = () => retries < OPENAI_MAX_RETRIES;

    for (;;) {
      let result: Awaited<ReturnType<OpenAIClientLike["complete"]>>;
      try {
        result = await this.client.complete(params);
      } catch (error) {
        if (canRetry() && isRetryableTransport(error)) {
          retries++;
          await this.sleep(1000);
          continue;
        }
        throw new AppError(
          "ai-unavailable",
          "Analiz servisi şu an yanıt veremiyor, birazdan tekrar dene.",
          { retryable: true },
        );
      }

      // Çıktı güvenlik bloğu → moderated.
      if (result.finishReason === "content_filter") {
        throw moderatedError();
      }
      // Token bütçesi dolduysa yapılandırılmış çıktı tamamlanmamış olur.
      if (result.finishReason === "length") {
        throw new AppError(
          "internal",
          "Analiz üretilemedi, lütfen tekrar dene.",
          { schemaFailure: true, finishReason: "length" },
        );
      }
      if (!result.parsed) {
        throw new AppError(
          "internal",
          "Analiz üretilemedi, lütfen tekrar dene.",
          { schemaFailure: true },
        );
      }

      return { output: result.parsed, usage: result.usage };
    }
  }
}

function moderatedError(): AppError {
  // OpenAI content_filter alt-kategori vermez → nötr güvenli mesaj;
  // kendine-zarar yönlendirmesi ayrı moderasyon geçişinde (takip işi).
  return new AppError("moderated", "Bu içerik analiz edilemiyor.", {
    selfHarm: false,
  });
}

function isRetryableTransport(error: unknown): boolean {
  const status =
    typeof error === "object" && error !== null && "status" in error
      ? Number((error as { status: unknown }).status)
      : undefined;
  if (status === 429 || (status !== undefined && status >= 500)) return true;
  // status'suz hata = ağ/timeout varsayımı → yeniden denenebilir
  return status === undefined;
}
