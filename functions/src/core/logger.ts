/**
 * Yapılandırılmış log — AI-ANALIZ-TASARIMI.md §9.2 hijyen kuralları:
 *  - ham uid loglanmaz (uidHash), karar içeriği/AI çıktısı ASLA loglanmaz
 *  - her satır event adı + bağlam alanları taşır → log-based metric'e uygun
 */
import { createHash } from "node:crypto";

import { logger as fbLogger } from "firebase-functions/v2";

import type { RequestContext } from "./types.js";

export function hashUid(uid: string): string {
  return createHash("sha256").update(uid).digest("hex").slice(0, 12);
}

type Level = "debug" | "info" | "warn" | "error";

/** Yasak alan adları — yanlışlıkla içerik loglamayı derlemede caydır,
 *  çalışma zamanında ayıkla (savunma derinliği). */
const FORBIDDEN_FIELDS = new Set([
  "title",
  "options",
  "criteria",
  "pros",
  "cons",
  "summary",
  "content",
  "prompt",
  "uid",
]);

export function sanitizeFields(
  fields: Record<string, unknown>,
): Record<string, unknown> {
  const clean: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (!FORBIDDEN_FIELDS.has(key)) clean[key] = value;
  }
  return clean;
}

export function log(
  level: Level,
  event: string,
  ctx: RequestContext,
  fields: Record<string, unknown> = {},
): void {
  fbLogger[level](event, {
    fn: ctx.fn,
    jobId: ctx.jobId,
    uidHash: ctx.uidHash,
    ...sanitizeFields(fields),
  });
}
