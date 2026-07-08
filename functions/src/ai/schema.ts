/**
 * AI analiz şemaları — AI-ANALIZ-TASARIMI.md §1.2 [4] girdi ve [9] çıktı.
 * Girdi limitleri Flutter Limits + firestore.rules ile senkron (üç katman).
 */
import { z } from "zod";

// ---- Girdi: istemci payload'ı yalnız kimlik taşır (§1.2 [3]) ----

export const analyzeRequestSchema = z.object({
  decisionId: z.string().min(1).max(64),
  tier: z.enum(["basic", "advanced"]).default("basic"),
});

// ---- Girdi: Firestore'dan okunan karar içeriği (Y-3 limitleri) ----

export const decisionContentSchema = z.object({
  title: z.string().min(3).max(100),
  options: z
    .array(
      z.object({
        id: z.string().min(1),
        title: z.string().min(1).max(60),
        description: z.string().max(280).nullish(),
        pros: z.array(z.string().max(140)).max(20).default([]),
        cons: z.array(z.string().max(140)).max(20).default([]),
      }),
    )
    .min(2)
    .max(10),
  criteria: z
    .array(
      z.object({
        id: z.string().min(1),
        name: z.string().min(1).max(40),
        weight: z.number().int().min(1).max(10),
      }),
    )
    .max(15),
});

export type DecisionContent = z.infer<typeof decisionContentSchema>;

// ---- Çıktı: LLM structured output (strict json_schema) ----
// NOT: strict modda dinamik anahtar (record) yok → perOption DİZİ olarak
// istenir, depoya map olarak yazılır (FIRESTORE-VERI-MODELI.md §5 şekli).

export const analysisOutputSchema = z.object({
  summary: z.string().min(1).max(4000),
  risks: z.array(z.string().min(1).max(500)).max(10),
  perOption: z
    .array(
      z.object({
        optionId: z.string().min(1),
        strengths: z.array(z.string().min(1).max(300)).max(5),
        weaknesses: z.array(z.string().min(1).max(300)).max(5),
      }),
    )
    .min(1),
  suggestedCriteria: z
    .array(
      z.object({
        name: z.string().min(1).max(40),
        defaultWeight: z.number().int().min(1).max(10),
      }),
    )
    .max(5),
  confidence: z.enum(["low", "medium", "high"]),
  confidenceReason: z.string().min(1).max(500),
});

export type AnalysisOutput = z.infer<typeof analysisOutputSchema>;

/** OpenAI response_format için el yazımı JSON Schema (strict: true uyumlu). */
export const analysisJsonSchema = {
  name: "ai_analysis",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "summary",
      "risks",
      "perOption",
      "suggestedCriteria",
      "confidence",
      "confidenceReason",
    ],
    properties: {
      summary: { type: "string" },
      risks: { type: "array", items: { type: "string" } },
      perOption: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["optionId", "strengths", "weaknesses"],
          properties: {
            optionId: { type: "string" },
            strengths: { type: "array", items: { type: "string" } },
            weaknesses: { type: "array", items: { type: "string" } },
          },
        },
      },
      suggestedCriteria: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["name", "defaultWeight"],
          properties: {
            name: { type: "string" },
            defaultWeight: { type: "integer" },
          },
        },
      },
      confidence: { type: "string", enum: ["low", "medium", "high"] },
      confidenceReason: { type: "string" },
    },
  },
} as const;

/** Depo şekli: perOption dizisi → {optionId: {strengths, weaknesses}} map'i. */
export function toStoredAnalysis(output: AnalysisOutput): {
  summary: string;
  risks: string[];
  perOption: Record<string, { strengths: string[]; weaknesses: string[] }>;
  suggestedCriteria: Array<{ name: string; defaultWeight: number }>;
  confidence: "low" | "medium" | "high";
  confidenceReason: string;
} {
  return {
    summary: output.summary,
    risks: output.risks,
    perOption: Object.fromEntries(
      output.perOption.map((o) => [
        o.optionId,
        { strengths: o.strengths, weaknesses: o.weaknesses },
      ]),
    ),
    suggestedCriteria: output.suggestedCriteria,
    confidence: output.confidence,
    confidenceReason: output.confidenceReason,
  };
}
