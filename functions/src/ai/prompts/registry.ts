/**
 * Prompt sürüm kayıt defteri — AI-ANALIZ-TASARIMI.md §7.
 * Prompt'lar repo'da sürümlü dosyalar; AKTİF sürüm Remote Config'ten
 * (anahtar: analyze_prompt_version) okunur → deploy'suz ileri/geri alma.
 * RC erişilemezse env → 'v1' düşüşü (fonksiyon asla prompt'suz kalmaz).
 */
import { getRemoteConfig } from "firebase-admin/remote-config";

import type { DecisionContent } from "../schema.js";
import * as v1 from "./analyze_v1.js";

export interface AnalyzePrompt {
  version: string;
  system: string;
  buildUserMessage: (content: DecisionContent) => string;
}

const REGISTRY: Record<string, AnalyzePrompt> = {
  [v1.PROMPT_VERSION]: {
    version: v1.PROMPT_VERSION,
    system: v1.SYSTEM_PROMPT,
    buildUserMessage: v1.buildUserMessage,
  },
};

export const DEFAULT_PROMPT_VERSION = v1.PROMPT_VERSION;

export function getPrompt(version: string): AnalyzePrompt {
  // Bilinmeyen sürüm (RC yazım hatası) sessizce v1'e düşer — üretimde
  // "prompt bulunamadı" ile analiz durdurmaktan iyidir; metrikle izlenir.
  return REGISTRY[version] ?? REGISTRY[DEFAULT_PROMPT_VERSION]!;
}

let cached: { version: string; expiresAtMs: number } | null = null;

/** Aktif sürüm: RC (5 dk önbellek) → env → varsayılan. */
export async function resolveActivePromptVersion(
  now: () => number = Date.now,
): Promise<string> {
  if (cached && cached.expiresAtMs > now()) return cached.version;
  let version =
    process.env["ANALYZE_PROMPT_VERSION"] ?? DEFAULT_PROMPT_VERSION;
  try {
    const template = await getRemoteConfig().getServerTemplate();
    const value = template
      .evaluate()
      .getString("analyze_prompt_version");
    if (value) version = value;
  } catch {
    // RC erişilemedi — env/varsayılan ile devam (kesinti nedeni olamaz).
  }
  cached = { version, expiresAtMs: now() + 5 * 60_000 };
  return version;
}

/** Test kancası. */
export function clearPromptVersionCache(): void {
  cached = null;
}
