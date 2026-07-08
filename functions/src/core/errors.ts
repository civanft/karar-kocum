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
  | "moderated"
  | "ai-unavailable"
  | "unimplemented"
  | "internal";

const HTTPS_CODE: Record<AppErrorCode, FunctionsErrorCode> = {
  unauthenticated: "unauthenticated",
  "invalid-argument": "invalid-argument",
  "rate-limited": "resource-exhausted",
  "quota-exceeded": "resource-exhausted",
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

/**
 * Handler'ların tek çıkış kapısı: AppError → HttpsError; bilinmeyen hata →
 * log'a tam, istemciye anonim 'internal'. Her hata metrik olarak sayılır.
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

  // Bilinmeyen: içerik loglanır (PII'siz alanlarla), istemciye sızdırılmaz.
  log("error", "request_failed_unexpected", ctx, {
    errorCode: "internal",
    errorMessage: error instanceof Error ? error.message : String(error),
    stack: error instanceof Error ? error.stack : undefined,
  });
  return new HttpsError("internal", "Beklenmeyen bir hata oluştu.", {
    appCode: "internal",
  });
}
