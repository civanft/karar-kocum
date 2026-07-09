/**
 * Gemini ağ geçidi — GEMINI-MVP-MIMARI.md §2, §5.
 * Moderasyon AYRI ÇAĞRI DEĞİL: safetySettings üretim çağrısına gömülü;
 * girdi bloğu (promptFeedback.blockReason) ve çıktı bloğu
 * (finishReason: SAFETY) 'moderated' hatasına eşlenir.
 * Retry (6B tek kural): 429 / 5xx / ağ / RECITATION → 1 yeniden deneme.
 */
import {
  GoogleGenerativeAI,
  HarmBlockThreshold,
  HarmCategory,
  type GenerateContentResult,
} from "@google/generative-ai";

import { AppError } from "../core/errors.js";
import {
  analysisOutputSchema,
  geminiResponseSchema,
  type AnalysisOutput,
} from "./schema.js";

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

/** Testlerde sahtelenen asgari SDK yüzeyi. */
export interface GeminiClientLike {
  generateContent(params: {
    system: string;
    user: string;
    model: string;
    maxOutputTokens: number;
  }): Promise<GenerateContentResult>;
}

const SAFETY_SETTINGS = [
  HarmCategory.HARM_CATEGORY_HARASSMENT,
  HarmCategory.HARM_CATEGORY_HATE_SPEECH,
  HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
  HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
].map((category) => ({
  category,
  threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
}));

/** Kendine zarar içeriği için güvenli yönlendirme (PRD R1). */
export const SELF_HARM_REDIRECT =
  "Bu konu bir karar analizinden daha önemli. Zor bir dönemden geçiyorsan " +
  "yalnız değilsin — 182'yi arayabilir ya da güvendiğin birine ulaşabilirsin.";

type Sleep = (ms: number) => Promise<void>;
const defaultSleep: Sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Üretim SDK adaptörü. */
export function createGeminiClient(apiKey: string): GeminiClientLike {
  const genAI = new GoogleGenerativeAI(apiKey);
  return {
    generateContent: (params) =>
      genAI
        .getGenerativeModel({
          model: params.model,
          systemInstruction: params.system,
          safetySettings: SAFETY_SETTINGS,
          generationConfig: {
            temperature: 0.4,
            maxOutputTokens: params.maxOutputTokens,
            responseMimeType: "application/json",
            responseSchema: geminiResponseSchema,
          },
        })
        .generateContent(params.user),
  };
}

export class GeminiGateway implements AiGateway {
  constructor(
    private readonly client: GeminiClientLike,
    private readonly sleep: Sleep = defaultSleep,
  ) {}

  async completeAnalysis(params: {
    system: string;
    user: string;
    model: string;
    maxOutputTokens: number;
  }): Promise<AnalysisCompletion> {
    let retried = false;

    for (;;) {
      let result: GenerateContentResult;
      try {
        result = await this.client.generateContent(params);
      } catch (error) {
        // 429 / 5xx / ağ hatası — tek yeniden deneme (6B kuralı).
        if (!retried && isRetryableTransport(error)) {
          retried = true;
          await this.sleep(1000);
          continue;
        }
        throw new AppError(
          "ai-unavailable",
          "Analiz servisi şu an yanıt veremiyor, birazdan tekrar dene.",
          { retryable: true },
        );
      }

      const response = result.response;

      // Girdi güvenlik bloğu (üretim hiç başlamadı) → moderated.
      const blockReason = response.promptFeedback?.blockReason;
      if (blockReason) {
        throw moderatedError(
          response.promptFeedback?.safetyRatings?.some(
            (r) => r.category === "HARM_CATEGORY_DANGEROUS_CONTENT",
          ) ?? false,
        );
      }

      const candidate = response.candidates?.[0];
      const finishReason = candidate?.finishReason;

      if (finishReason === "SAFETY") {
        throw moderatedError(
          candidate?.safetyRatings?.some(
            (r) => r.category === "HARM_CATEGORY_DANGEROUS_CONTENT",
          ) ?? false,
        );
      }
      if (finishReason === "RECITATION") {
        if (!retried) {
          retried = true;
          await this.sleep(1000);
          continue;
        }
        throw new AppError(
          "ai-unavailable",
          "Analiz üretilemedi, lütfen tekrar dene.",
          { retryable: true },
        );
      }
      if (finishReason === "MAX_TOKENS") {
        throw new AppError(
          "internal",
          "Analiz üretilemedi, lütfen tekrar dene.",
          { schemaFailure: true, finishReason },
        );
      }

      const text = candidate?.content?.parts?.[0]?.text;
      const parsed = tryParse(text);
      if (!parsed) {
        throw new AppError(
          "internal",
          "Analiz üretilemedi, lütfen tekrar dene.",
          { schemaFailure: true },
        );
      }

      return {
        output: parsed,
        usage: {
          inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
          outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0,
        },
      };
    }
  }
}

function moderatedError(dangerous: boolean): AppError {
  return new AppError(
    "moderated",
    dangerous ? SELF_HARM_REDIRECT : "Bu içerik analiz edilemiyor.",
    { selfHarm: dangerous },
  );
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

function tryParse(text: string | undefined): AnalysisOutput | null {
  if (!text) return null;
  try {
    const parsed = analysisOutputSchema.safeParse(JSON.parse(text));
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}
