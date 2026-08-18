/**
 * Hata katmanı — AI-ANALIZ-TASARIMI.md §8 taksonomisi.
 * İlke: iç hata metinleri (upstream, stack) istemciye ASLA sızmaz;
 * istemci yalnız kod + güvenli mesaj + yapılandırılmış detay görür.
 */
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

import { log } from "./logger.js";
import type { RequestContext } from "./types.js";

export type AppErrorCode =
  | "unauthenticated"
  | "invalid-argument"
  | "rate-limited"
  | "quota-exceeded"
  | "daily-limit"
  | "moderated"
  | "ai-unavailable"
  | "unimplemented"
  | "internal";

const HTTPS_CODE: Record<AppErrorCode, FunctionsErrorCode> = {
  unauthenticated: "unauthenticated",
  "invalid-argument": "invalid-argument",
  "rate-limited": "resource-exhausted",
  "quota-exceeded": "resource-exhausted",
  "daily-limit": "resource-exhausted",
  moderated: "failed-precondition",
  "ai-unavailable": "unavailable",
  unimplemented: "unimplemented",
  internal: "internal",
};

export class AppError extends Error {
  constructor(
    readonly code: AppErrorCode,
    message: string,
    /** İstemciye AÇIK detay (retryAfterSeconds vb.) — asla iç bilgi koyma. */
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
    this.name = "AppError";
  }
}

const SAFE_DIAGNOSTIC_TOKEN = /^[A-Za-z0-9_.-]{1,64}$/;

function safeDiagnosticToken(value: unknown): string {
  return typeof value === "string" && SAFE_DIAGNOSTIC_TOKEN.test(value)
    ? value
    : "unknown";
}

function unexpectedErrorDiagnostic(error: unknown): {
  errorCode: string;
  errorType: string;
} {
  const candidate =
    typeof error === "object" && error !== null && "code" in error
      ? (error as { code?: unknown }).code
      : undefined;
  return {
    errorCode: safeDiagnosticToken(candidate),
    errorType: safeDiagnosticToken(
      error instanceof Error ? error.name : typeof error,
    ),
  };
}

/**
 * Handler'ların tek çıkış kapısı: AppError → HttpsError; bilinmeyen hata →
 * log'a güvenli teşhis, istemciye anonim 'internal'. Her hata metrik sayılır.
 */
export function toHttpsError(error: unknown, ctx: RequestContext): HttpsError {
  if (error instanceof HttpsError) return error; // zaten dönüştürülmüş

  if (error instanceof AppError) {
    log("warn", "request_failed", ctx, {
      errorCode: error.code,
      errorMessage: error.message,
    });
    return new HttpsError(HTTPS_CODE[error.code], error.message, {
      appCode: error.code,
      ...error.details,
    });
  }

  // Bilinmeyen: ham message/stack/yol/UID loglanmaz; yalnız biçim denetimli
  // teşhis alanları kalır. İstemciye de anonim hata döner.
  log("error", "request_failed_unexpected", ctx, {
    ...unexpectedErrorDiagnostic(error),
  });
  return new HttpsError("internal", "Beklenmeyen bir hata oluştu.", {
    appCode: "internal",
  });
}
