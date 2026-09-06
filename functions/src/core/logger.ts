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
  "token",
  "tokens",
  "__proto__",
  "constructor",
  "prototype",
]);

const SECRET_FIELD = /apikey|authorization|password|passwd|secret|accesstoken|refreshtoken|idtoken|bearertoken|cookie|privatekey|credential/i;
const SECRET_VALUE = /\b(?:sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b/g;

function sanitizedValue(value: unknown, depth: number): unknown {
  if (depth > 5) return "[REDACTED]";
  if (typeof value === "string") {
    if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(value)) return "[REDACTED]";
    return value.replace(SECRET_VALUE, "[REDACTED]").slice(0, 2000);
  }
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (Array.isArray(value)) return value.slice(0, 50).map((item) => sanitizedValue(item, depth + 1));
  if (typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return sanitizedObject(value as Record<string, unknown>, depth + 1);
  }
  return "[REDACTED]";
}

function sanitizedObject(fields: Record<string, unknown>, depth: number): Record<string, unknown> {
  const clean: Record<string, unknown> = {};
  if (depth > 5) return clean;
  for (const [key, value] of Object.entries(fields).slice(0, 50)) {
    const normalized = key.replace(/[^a-z0-9]/gi, "").toLowerCase();
    if (!FORBIDDEN_FIELDS.has(key.toLowerCase()) &&
        !FORBIDDEN_FIELDS.has(normalized) && !SECRET_FIELD.test(normalized)) {
      clean[key] = sanitizedValue(value, depth);
    }
  }
  return clean;
}

export function sanitizeFields(
  fields: Record<string, unknown>,
): Record<string, unknown> {
  return sanitizedObject(fields, 0);
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
