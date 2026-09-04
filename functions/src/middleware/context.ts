/**
 * İstek bağlamı kurulumu — boru hattı adım [1-2] (AI-ANALIZ-TASARIMI.md §1.2).
 *
 * App Check: `enforceAppCheck: true` GEÇERSİZ token'ı engeller,
 * `consumeAppCheckToken: true` limited-use token'ı TÜKETİR — ama tüketilmiş
 * bir token TEKRAR oynatıldığında isteği ENGELLEMEZ; yalnız
 * `request.app.alreadyConsumed = true` işaretler. Bu yüzden replay reddi
 * BURADA, herhangi bir yan etkiden önce açıkça yapılır (İş Paketi 2).
 */
import { randomUUID } from "node:crypto";

import type { CallableRequest } from "firebase-functions/v2/https";

import { AppError } from "../core/errors.js";
import { hashUid, log } from "../core/logger.js";
import type { RequestContext } from "../core/types.js";

/**
 * Auth bağlamı kurulmadan hata oluştuğunda güvenli hata eşleme/loglama bağlamı.
 * Ham UID yoktur; sabit değerler PII sızıntısını ve AppError'ın `internal`
 * olarak maskelenmesini önler.
 */
export function contextlessLogContext(fn: string): RequestContext {
  return {
    fn,
    jobId: "no-auth",
    uid: "",
    uidHash: "anonymous",
    startedAtMs: Date.now(),
  };
}

export function buildContext(
  fn: string,
  request: CallableRequest,
): RequestContext {
  const uid = request.auth?.uid;
  if (!uid) {
    // Bağlamsız fırlatma: uid yok, hash'lenecek kimlik de yok.
    throw new AppError("unauthenticated", "Oturum gerekli.");
  }
  // REPLAY REDDİ — her türlü yan etkiden (log dahil) ÖNCE. İstemci yeni bir
  // limited-use token alıp AYNI requestId ile güvenle tekrar deneyebilir,
  // bu yüzden istemci tarafında retryable sınıflandırılır. Mesaj teknik
  // ayrıntı (token/App Check) sızdırmaz.
  if (request.app?.alreadyConsumed === true) {
    throw new AppError(
      "app-check-replay",
      "Doğrulama yenilenmeli — lütfen tekrar dene.",
    );
  }
  const ctx: RequestContext = {
    fn,
    jobId: randomUUID(),
    uid,
    uidHash: hashUid(uid),
    startedAtMs: Date.now(),
  };
  log("info", "request_started", ctx, {
    appCheckVerified: request.app != null, // enforceAppCheck garantisi; izleme
    authProvider: request.auth?.token.firebase?.sign_in_provider,
  });
  return ctx;
}
