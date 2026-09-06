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
  /** Tüketilmiş (replay edilen) App Check limited-use token'ı. */
  | "app-check-replay"
  | "invalid-argument"
  | "rate-limited"
  | "quota-exceeded"
  | "daily-limit"
  | "moderated"
  | "ai-unavailable"
  /** Sağlayıcı çağrısının sonucu BİLİNMİYOR (belirsiz pencere). */
  | "ai-uncertain"
  /** Sağlayıcı KESİN olarak başarısız (şema/uzunluk/kalıcı ret). */
  | "ai-failed"
  /** Analiz üretilirken karar değişti — sonuç bağlanamaz. */
  | "superseded"
  /** Hesap silme bariyeri açık: bu UID için yeni veri oluşturulamaz. */
  | "account-deleting"
  | "unimplemented"
  | "internal";

const HTTPS_CODE: Record<AppErrorCode, FunctionsErrorCode> = {
  unauthenticated: "unauthenticated",
  // Firebase'in kendi App Check reddiyle aynı taşıma kodu.
  "app-check-replay": "unauthenticated",
  "invalid-argument": "invalid-argument",
  "rate-limited": "resource-exhausted",
  "quota-exceeded": "resource-exhausted",
  "daily-limit": "resource-exhausted",
  moderated: "failed-precondition",
  "ai-unavailable": "unavailable",
  "ai-uncertain": "unavailable",
  "ai-failed": "internal",
  // Eşzamanlı değişiklik nedeniyle iptal — HTTP semantiği `aborted`.
  superseded: "aborted",
  // Kalıcı ön koşul ihlali: hesap siliniyor, tekrar denemek durumu değiştirmez.
  "account-deleting": "failed-precondition",
  unimplemented: "unimplemented",
  internal: "internal",
};

/**
 * İstemciye gönderilen RETRY YÖNERGESİ (İş Paketi 2B).
 *
 * Boolean bir `retryable` yeterli değildi: "tekrar denenebilir" ile "AYNI
 * idempotency anahtarıyla tekrar denenebilir" farklı şeylerdir. Aynı anahtarla
 * tekrarlanamayacak bir durumu retryable işaretlemek istemciyi sonsuz döngüye
 * sokar (denetim bulgusu #2).
 *
 *  - "same": iş sunucuda başlamadı ya da tamamlanmayı bekliyor; AYNI
 *    requestId ile tekrar güvenlidir ve tamamlayıcıdır.
 *  - "new":  bu requestId tükendi; kullanıcı isterse YENİ bir istek başlatır.
 *  - "none": tekrar denemek sonucu değiştirmez.
 */
export type RetryDirective = "same" | "new" | "none";

/** Her AppErrorCode için sunucunun bildirdiği varsayılan yönerge. */
const RETRY_DIRECTIVE: Record<AppErrorCode, RetryDirective> = {
  // İş journal'a ULAŞMADAN reddedildi → aynı anahtar hâlâ kullanılabilir.
  unauthenticated: "same",
  "app-check-replay": "same",
  // Rezervasyon transaction'ı iptal oldu; hiçbir şey tüketilmedi.
  "rate-limited": "new",
  "ai-unavailable": "new",
  // Sonucu değişmeyecek durumlar.
  "invalid-argument": "none",
  "quota-exceeded": "none",
  "daily-limit": "none",
  moderated: "none",
  unimplemented: "none",
  // Bu requestId tükendi.
  "ai-uncertain": "new",
  "ai-failed": "new",
  superseded: "new",
  // Hesap siliniyor: hiçbir tekrar bunu değiştirmez.
  "account-deleting": "none",
  // Genel iç hata: finalization bekliyor olabilir → aynı anahtar tamamlar.
  internal: "same",
};

export class AppError extends Error {
  constructor(
    readonly code: AppErrorCode,
    message: string,
    /** İstemciye AÇIK detay (retryAfterSeconds vb.) — asla iç bilgi koyma. */
    readonly details?: Record<string, unknown>,
    /** Koda göre varsayılanı EZER (ör. journal durumu daha kesin bilgi verir). */
    readonly retry: RetryDirective = RETRY_DIRECTIVE[code],
  ) {
    super(message);
    this.name = "AppError";
  }
}

export function defaultRetryDirective(code: AppErrorCode): RetryDirective {
  return RETRY_DIRECTIVE[code];
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
    });
    return new HttpsError(HTTPS_CODE[error.code], error.message, {
      appCode: error.code,
      // İstemcinin idempotency anahtarını ne yapacağını sunucu SÖYLER.
      retry: error.retry,
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
    // Sunucu tarafında ne olduğu bilinmiyor: AYNI anahtarla tekrar denemek
    // güvenli taraftır (iş tamamlanmışsa saklanan sonuç döner).
    retry: "same" satisfies RetryDirective,
  });
}
