/**
 * OpenAI ağ geçidi — AI-ANALIZ-TASARIMI.md §8 retry politikası:
 *   429            → 2 yeniden deneme (1s, 4s + jitter), kota YANMAZ
 *   5xx / timeout  → 1 yeniden deneme
 *   4xx (diğer)    → deneme yok → ai-unavailable(retryable değil)
 *   şema hatası    → 1 onarım denemesi (hata mesajıyla) → internal
 * SDK retry'ı kapalı (maxRetries: 0) — politika TEK yerde, burada.
 */
import OpenAI, { APIError } from "openai";

import { AppError } from "../core/errors.js";
import {
  analysisJsonSchema,
  analysisOutputSchema,
  type AnalysisOutput,
} from "./schema.js";

export interface CompletionUsage {
  inputTokens: number;
  outputTokens: number;
}

export interface AnalysisCompletion {
  output: AnalysisOutput;
  usage: CompletionUsage;
  repaired: boolean;
}

export interface ModerationResult {
  flagged: boolean;
  selfHarm: boolean;
  categories: string[];
}

/** Test edilebilirlik sınırı: orkestratör yalnız bu arayüzü bilir. */
export interface AiGateway {
  moderate(text: string): Promise<ModerationResult>;
  completeAnalysis(params: {
    model: string;
    system: string;
    user: string;
    maxOutputTokens: number;
  }): Promise<AnalysisCompletion>;
}

type Sleep = (ms: number) => Promise<void>;
const defaultSleep: Sleep = (ms) => new Promise((r) => setTimeout(r, ms));

type ErrorClass = "rate" | "server" | "client";

export function classifyOpenAiError(error: unknown): ErrorClass {
  if (error instanceof APIError) {
    const status = error.status ?? 0;
    if (status === 429) return "rate";
    if (status >= 500) return "server";
    if (status >= 400) return "client";
  }
  // Ağ hatası / timeout — APIConnectionError dahil
  return "server";
}

export async function withRetries<T>(
  fn: () => Promise<T>,
  sleep: Sleep = defaultSleep,
  jitter: () => number = Math.random,
): Promise<T> {
  const rateBackoffMs = [1000, 4000];
  let rateAttempts = 0;
  let serverAttempts = 0;

  for (;;) {
    try {
      return await fn();
    } catch (error) {
      const kind = classifyOpenAiError(error);
      if (kind === "rate" && rateAttempts < rateBackoffMs.length) {
        await sleep(rateBackoffMs[rateAttempts]! + jitter() * 500);
        rateAttempts++;
        continue;
      }
      if (kind === "server" && serverAttempts < 1) {
        await sleep(500 + jitter() * 500);
        serverAttempts++;
        continue;
      }
      throw new AppError(
        "ai-unavailable",
        "Analiz servisi şu an yanıt veremiyor, birazdan tekrar dene.",
        { retryable: kind !== "client" },
      );
    }
  }
}

export class OpenAiGateway implements AiGateway {
  constructor(
    apiKey: string,
    private readonly sleep: Sleep = defaultSleep,
    client?: OpenAI,
  ) {
    this.client =
      client ?? new OpenAI({ apiKey, maxRetries: 0, timeout: 60_000 });
  }

  private readonly client: OpenAI;

  async moderate(text: string): Promise<ModerationResult> {
    const response = await withRetries(
      () =>
        this.client.moderations.create({
          model: "omni-moderation-latest",
          input: text,
        }),
      this.sleep,
    );
    const result = response.results[0];
    if (!result) return { flagged: false, selfHarm: false, categories: [] };
    const categories = Object.entries(result.categories)
      .filter(([, v]) => v === true)
      .map(([k]) => k);
    return {
      flagged: result.flagged,
      selfHarm: categories.some((c) => c.startsWith("self-harm")),
      categories,
    };
  }

  async completeAnalysis(params: {
    model: string;
    system: string;
    user: string;
    maxOutputTokens: number;
  }): Promise<AnalysisCompletion> {
    const request = (extraUser?: string) =>
      withRetries(
        () =>
          this.client.chat.completions.create({
            model: params.model,
            max_tokens: params.maxOutputTokens,
            temperature: 0.4,
            messages: [
              { role: "system", content: params.system },
              { role: "user", content: params.user },
              ...(extraUser
                ? [{ role: "user" as const, content: extraUser }]
                : []),
            ],
            response_format: {
              type: "json_schema",
              json_schema: analysisJsonSchema,
            },
          }),
        this.sleep,
      );

    const first = await request();
    const firstParsed = this.tryParse(first);
    const firstUsage = usageOf(first);
    if (firstParsed.ok) {
      return { output: firstParsed.value, usage: firstUsage, repaired: false };
    }

    // Tek onarım denemesi (§8): modele şema hatasını söyleyip yeniden iste.
    const second = await request(
      `Önceki yanıtın şema doğrulamasından geçmedi: ${firstParsed.error}. ` +
        "Yalnızca şemaya birebir uyan geçerli JSON döndür.",
    );
    const secondParsed = this.tryParse(second);
    const totalUsage = addUsage(firstUsage, usageOf(second));
    if (secondParsed.ok) {
      return { output: secondParsed.value, usage: totalUsage, repaired: true };
    }
    throw new AppError(
      "internal",
      "Analiz üretilemedi, lütfen tekrar dene.",
      { schemaFailure: true },
    );
  }

  private tryParse(
    completion: OpenAI.Chat.ChatCompletion,
  ): { ok: true; value: AnalysisOutput } | { ok: false; error: string } {
    const raw = completion.choices[0]?.message.content;
    if (!raw) return { ok: false, error: "boş yanıt" };
    try {
      const parsed = analysisOutputSchema.safeParse(JSON.parse(raw));
      if (parsed.success) return { ok: true, value: parsed.data };
      return { ok: false, error: parsed.error.issues[0]?.message ?? "şema" };
    } catch {
      return { ok: false, error: "geçersiz JSON" };
    }
  }
}

function usageOf(completion: OpenAI.Chat.ChatCompletion): CompletionUsage {
  return {
    inputTokens: completion.usage?.prompt_tokens ?? 0,
    outputTokens: completion.usage?.completion_tokens ?? 0,
  };
}

function addUsage(a: CompletionUsage, b: CompletionUsage): CompletionUsage {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
  };
}
