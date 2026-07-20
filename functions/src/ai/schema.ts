/**
 * AI analiz şemaları — GEMINI-MVP-MIMARI.md §4 düz şeması.
 * Girdi limitleri Flutter Limits + firestore.rules ile senkron (üç katman).
 */
import { z } from "zod";

// ---- Girdi: istemci payload'ı yalnız kimlik taşır ----

export const analyzeRequestSchema = z.object({
  decisionId: z.string().min(1).max(64),
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

// ---- Çıktı: düz analiz şeması (6C-1 §4) ----

export const analysisOutputSchema = z.object({
  summary: z.string().min(1).max(2000),
  strengths: z.array(z.string().min(1).max(300)).max(5),
  weaknesses: z.array(z.string().min(1).max(300)).max(5),
  risks: z.array(z.string().min(1).max(300)).max(5),
  recommendation: z.string().min(1).max(500),
  confidence: z.enum(["low", "medium", "high"]),
});

export type AnalysisOutput = z.infer<typeof analysisOutputSchema>;
